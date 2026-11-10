"""Transactional first-run setup. Never writes inside the source checkout."""
import fcntl
import getpass
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import secrets
import shutil
import subprocess
import sys
import tarfile
import time
import uuid

from runtime import ROOT, CODE_ROOT, safe, ensure
from lab import save, now
from processes import execute, assert_quiescent, assert_idle, tracked_call

LOCAL = ROOT / '.local'
STAGE = ROOT / '.setup'
JOURNAL = ROOT / 'setup.json'
TOOLS = ('ipatool', 'unfairplay', 'keychain-bridge')


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def remove_tree(path):
    safe(path)
    if not shutil.rmtree.avoids_symlink_attacks:
        raise RuntimeError('Safe recursive removal is unavailable.')
    if path.exists():
        def retry(function, target, error):
            candidate = Path(target)
            safe(candidate)
            if candidate.is_symlink():
                raise error[1]
            safe(candidate.parent).chmod(0o700)
            if candidate.is_dir():
                candidate.chmod(0o700)
            function(target)
        shutil.rmtree(path, onerror=retry)


def validate_tools(local=None):
    local = LOCAL if local is None else local
    data = json.loads(safe(local / 'tools.json').read_text())
    for name in TOOLS:
        if digest(safe(local / 'bin' / name)) != data[name]:
            raise RuntimeError('Tool checksum mismatch: ' + name)
    return data


def ready():
    if not LOCAL.exists():
        return False
    validate_tools()
    return any(safe(LOCAL / 'models').glob('*.bin'))


def unpack(archive, destination):
    # Extract only directories and regular files, after checking the whole archive.
    with tarfile.open(archive) as tar:
        members = tar.getmembers()
        if len(members) > 100000 or any(m.size < 0 for m in members) or sum(m.size for m in members) > 2 * 1024**3:
            raise ValueError('Archive exceeds extraction limits.')
        seen = set()
        for m in members:
            rel = Path(m.name)
            if rel.is_absolute() or '..' in rel.parts or not (m.isdir() or m.isfile()) or m.name in seen:
                raise ValueError('Unsafe archive member.')
            seen.add(m.name)
        destination.mkdir(parents=True, mode=0o700)
        for m in members:
            path = destination / m.name
            if m.isdir():
                path.mkdir(parents=True, mode=0o700, exist_ok=True)
            else:
                path.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
                with path.open('xb') as output, tar.extractfile(m) as source:
                    shutil.copyfileobj(source, output)
                path.chmod(0o700 if m.mode & 0o111 else 0o600)


def run(stage, command, env, record, *, secret=None, interactive=False, cwd=None):
    step = {'stage': stage, 'started': now()}
    record.setdefault('steps', []).append(step)
    save(JOURNAL, record)
    print('▶ ' + stage, flush=True)
    env = env.copy()
    reader = None
    code = 130
    started = time.monotonic()
    try:
        if secret is not None:
            if not 12 <= len(secret) <= 4096:
                raise ValueError('Invalid secret length.')
            reader, writer = os.pipe()
            try:
                os.write(writer, secret)
            finally:
                os.close(writer)
            env['DEV_IPA_PASSPHRASE_FD'] = str(reader)
        logs = safe(STAGE / 'logs')
        logs.mkdir(mode=0o700, exist_ok=True)
        with (logs / (stage + '.stdout')).open('wb') as out, (logs / (stage + '.stderr')).open('wb') as err:
            code = execute(command, record=record, persist=lambda: save(JOURNAL, record),
                           terminal=interactive or command[0] == '/usr/bin/sudo',
                           cwd=cwd or STAGE, env=env,
                           stdout=None if interactive else out,
                           stderr=None if interactive else err,
                           pass_fds=() if reader is None else (reader,),
                           progress=None if interactive else lambda: print(
                               '  ' + stage + ': elapsed ' + str(int(time.monotonic() - started)) + 's', flush=True))
        if code:
            raise RuntimeError(stage + ' failed (exit ' + str(code) + ').')
    finally:
        if reader is not None:
            os.close(reader)
        step.update(ended=now(), exit_code=code)
        save(JOURNAL, record)


def clean_pending():
    """Called with the global lock; preserve a committed installation after a crash."""
    if not STAGE.exists():
        return
    safe(STAGE)
    record = json.loads(safe(JOURNAL).read_text())
    assert_quiescent(record)
    account = record.get('account', '')
    if not re.fullmatch(r'[0-9a-f]{32}', account):
        raise RuntimeError('Unrecognized setup transaction; refusing cleanup.')
    owner = safe(STAGE / '.owner')
    entries = list(STAGE.iterdir())
    # A crash during marker creation has no tools or secrets yet. Recognize only
    # our two owned marker filenames with a prefix of this journal's nonce.
    allocation_only = not record.get('keychain_intent') and all(
        p.name in ('.owner', '.owner.tmp') and not p.is_symlink() and p.is_file()
        and p.stat().st_uid == os.getuid() and account.startswith(p.read_text())
        for p in entries)
    if allocation_only:
        remove_tree(STAGE)
        record.update(status='rolled-back', ended=now())
        save(JOURNAL, record)
        return
    if owner.read_text() != account:
        raise RuntimeError('Setup marker mismatch.')
    committed = False
    if LOCAL.exists():
        config = validate_tools()
        if config.get('keychain_account') != account:
            raise RuntimeError('Existing installation differs from pending setup.')
        committed = config.get('initialized') is True
        if not committed:
            raise RuntimeError('Incomplete committed installation; refusing removal.')
    if record.get('ownership_pending') and not committed:
        restore_model_ownership(record, dict(os.environ, TMPDIR=str(STAGE / 'tmp')), STAGE / 'local')
    if record.get('keychain_intent') and not committed:
        config = validate_tools(STAGE / 'local')
        if config.get('keychain_account') != account:
            raise RuntimeError('Pending Keychain scope mismatch.')
        # Deletion is safe even if the crash happened before SecItemAdd.
        tracked_call([str(STAGE / 'local/bin/keychain-bridge'), 'delete', account],
                     record=record, persist=lambda: save(JOURNAL, record), check=True)
    if not committed and record.get('status') == 'failed' and (STAGE / 'logs').exists():
        diagnostics = safe(ROOT / 'diagnostics/last-setup')
        remove_tree(diagnostics)
        diagnostics.parent.mkdir(mode=0o700, exist_ok=True)
        shutil.copytree(STAGE / 'logs', diagnostics)
    remove_tree(STAGE)
    record.update(status='passed' if committed else ('build-verified' if record.get('status') == 'build-verified' else 'rolled-back'), ended=now())
    save(JOURNAL, record)


def preflight():
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise RuntimeError('IPA Loom currently requires an Apple Silicon Mac.')
    if sys.version_info < (3, 9):
        raise RuntimeError('Python 3.9 or later is required.')
    subprocess.run(['/usr/bin/xcrun', '--find', 'swiftc'], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(['/usr/bin/xcrun', '--find', 'clang'], check=True, stdout=subprocess.DEVNULL)


def ipatool_version_label(pins):
    version = pins['ipatool']['version']
    if not re.fullmatch(r'v?[0-9]+\.[0-9]+\.[0-9]+', version):
        raise ValueError('Invalid pinned ipatool version.')
    return version.lstrip('v') + '-ipa-loom'


def build(record, env, pins=None):
    pins = pins or json.loads((CODE_ROOT / 'config/dependencies.json').read_text())
    patch = CODE_ROOT / 'patches/ipatool/0001-local-runtime.patch'
    if digest(patch) != pins['patch_sha256']:
        raise RuntimeError('Patch checksum mismatch.')
    local = STAGE / 'local'
    (local / 'bin').mkdir(parents=True, mode=0o700)
    for name in ('state', 'cache', 'models'):
        (local / name).mkdir(mode=0o700)
    for name in ('go', 'ipatool', 'unfairplay'):
        archive = STAGE / (name + '.tar.gz')
        pin = pins[name]
        if not pin['url'].startswith('https://'):
            raise ValueError('HTTPS download required.')
        run('download-' + name, ['/usr/bin/curl', '-q', '--fail', '--location', '--proto', '=https',
            '--proto-redir', '=https', '--connect-timeout', '20', '--max-time', '1800',
            '--output', str(archive), pin['url']], env, record, interactive=True)
        if digest(archive) != pin['sha256']:
            raise RuntimeError('Download checksum mismatch: ' + name)
        unpack(archive, STAGE / name)
    sources = [p for p in (STAGE / 'ipatool').iterdir() if p.is_dir()]
    if len(sources) != 1:
        raise RuntimeError('Unexpected source archive layout.')
    source = sources[0]
    run('patch-check', ['/usr/bin/git', 'apply', '--check', str(patch)], env, record, cwd=source)
    run('patch', ['/usr/bin/git', 'apply', str(patch)], env, record, cwd=source)
    telemetry = STAGE / 'telemetry'
    telemetry.mkdir(mode=0o700)
    (telemetry / 'mode').write_text('off\n')
    env.update(TEST_TELEMETRY_DIR=str(telemetry), GOMODCACHE=str(STAGE / 'gopath/pkg/mod'),
               GOENV='off', GOTOOLCHAIN='local', GOPATH=str(STAGE / 'gopath'),
               GOCACHE=str(STAGE / 'go-build'), CLANG_MODULE_CACHE_PATH=str(STAGE / 'clang'),
               GOPROXY='https://proxy.golang.org,direct', GOSUMDB='sum.golang.org')
    run('check-telemetry', [str(STAGE / 'go/go/bin/go'), 'env', 'GOTELEMETRYDIR', 'GOTELEMETRY'], env, record)
    if (STAGE / 'logs/check-telemetry.stdout').read_text().splitlines() != [str(telemetry), 'off']:
        raise RuntimeError('Go telemetry isolation is unsupported; build stopped.')
    run('build-ipatool', [str(STAGE / 'go/go/bin/go'), 'build', '-trimpath',
        '-ldflags', '-X github.com/majd/ipatool/v2/cmd.version=' + ipatool_version_label(pins),
        '-o', str(local / 'bin/ipatool'), '.'], env, record, cwd=source)
    binaries = list((STAGE / 'unfairplay').glob('*/unfairplay'))
    if len(binaries) != 1:
        raise RuntimeError('Unexpected UnfairPlay archive layout.')
    shutil.copy2(binaries[0], local / 'bin/unfairplay')
    run('build-keychain', ['/usr/bin/xcrun', 'swiftc', '-module-cache-path', str(STAGE / 'swift-cache'),
        str(CODE_ROOT / 'native/keychain.swift'), '-o', str(local / 'bin/keychain-bridge')], env, record)
    for name in TOOLS:
        (local / 'bin' / name).chmod(0o700)
    for name in ('ipatool', 'unfairplay'):
        run('check-' + name, [str(local / 'bin' / name), '--version'], env, record)
    interfaces = [('ipatool', 'download', ['--app-id', '--platform', '--output']),
                  ('ipatool', 'auth', ['login']),
                  ('unfairplay', 'setup', ['--app', '--ipa', '--model-dir']),
                  ('unfairplay', 'decrypt', ['--input', '--model', '--output', '--report', '--strip-account-data'])]
    for tool, command, required in interfaces:
        stage = 'interface-' + tool + '-' + command
        run(stage, [str(local / 'bin' / tool), command, '--help'], env, record)
        help_text = (STAGE / 'logs' / (stage + '.stdout')).read_text()
        if any(flag not in help_text for flag in required):
            raise RuntimeError('Upstream command interface changed: ' + tool + ' ' + command)
    config = {name: digest(local / 'bin' / name) for name in TOOLS}
    config.update(keychain_account=record['account'], initialized=False)
    save(local / 'tools.json', config)
    return local, config


def installed_info(app):
    plist = app / 'Info.plist'
    wrapped = list((app / 'Wrapper').glob('*.app/Info.plist'))
    if wrapped:
        if len(wrapped) != 1:
            raise ValueError('Ambiguous installed app wrapper.')
        plist = wrapped[0]
    elif not plist.exists():
        plist = app / 'Contents/Info.plist'
    if plist.stat().st_size > 8 * 1024**2:
        raise ValueError('Installed app metadata exceeds size limit.')
    info = plistlib.loads(plist.read_bytes())
    from pipeline import app_identity
    return app_identity(info)


def restore_model_ownership(record, env, local):
    models = safe(local / 'models')
    if not models.is_dir():
        raise RuntimeError('Expected model directory is unavailable; staging preserved.')
    run('model-ownership', ['/usr/bin/sudo', '/usr/sbin/chown', '-R', '-P',
        str(os.getuid()) + ':' + str(os.getgid()), str(models)], env, record)
    record.pop('ownership_pending', None)
    save(JOURNAL, record)


def recover_model(record, env, local, app, ipa):
    record['ownership_pending'] = True
    save(JOURNAL, record)
    try:
        run('recover-model', ['/usr/bin/sudo', '/usr/bin/env', 'TMPDIR=' + env['TMPDIR'],
            str(local / 'bin/unfairplay'), 'setup', '--app', str(app), '--ipa', str(ipa),
            '--model-dir', str(local / 'models')], env, record)
    finally:
        assert_quiescent(record)
        restore_model_ownership(record, env, local)
    if any(p.is_symlink() for p in (local / 'models').rglob('*')):
        raise RuntimeError('Unexpected model symlink.')


def initialize(record, env, local, config, target=None):
    from pipeline import parse_target, ipa_info, verify_result
    if not sys.stdin.isatty():
        raise RuntimeError('First setup requires your own Terminal for Apple login and sudo.')
    print('Install and open an iPhone/iPad app from the Mac App Store using your Apple account.', flush=True)
    app = Path(input('Installed .app path: ').strip().strip('"\'')).expanduser().resolve()
    if app.suffix != '.app' or not app.is_dir():
        raise ValueError('An installed .app directory is required.')
    installed = installed_info(app)
    value = input('Matching Store URL or IPA' + (' [' + target + ']' if target else '') + ': ').strip() or target
    if not value:
        raise ValueError('A matching IPA or Store target is required.')
    kind, identifier = parse_target(value)
    env.update(XDG_STATE_HOME=str(local / 'state'), DEV_IPA_CACHE=str(local / 'cache'),
               UNFAIRPLAY_MODEL_DIR=str(local / 'models'))
    # Generate an unlock key; the user only enters Apple credentials/2FA and sudo.
    secret = secrets.token_urlsafe(48).encode()
    print('Apple credentials are encrypted locally; the unlock key will be saved in Keychain after verification.')
    run('apple-login', [str(local / 'bin/ipatool'), 'auth', 'login'], env, record, secret=secret, interactive=True)
    ipa = STAGE / 'source.ipa'
    if kind == 'file':
        from pipeline import MAX_IPA_BYTES
        if Path(identifier).stat().st_size > MAX_IPA_BYTES:
            raise ValueError('Input IPA exceeds file size limit.')
        shutil.copyfile(identifier, ipa)
    else:
        run('download-ipa', [str(local / 'bin/ipatool'), 'download', '--app-id', identifier,
            '--platform', 'iphone', '--output', str(ipa)], env, record, secret=secret, interactive=True)
    info = ipa_info(ipa)
    if installed != info:
        raise RuntimeError('Installed app and IPA identity/version differ; setup was not run.')
    recover_model(record, env, local, app, ipa)
    if not list((local / 'models').glob('*.bin')):
        raise RuntimeError('No model was recovered.')
    output = STAGE / 'verified.ipa'
    report = STAGE / 'logs/decryption-report.json'
    run('verify-model', [str(local / 'bin/unfairplay'), 'decrypt', '--input', str(ipa),
        '--model', str(local / 'models'), '--output', str(output), '--report', str(report),
        '--strip-account-data'], env, record)
    record['verification'] = verify_result(info, output, report)
    record['keychain_intent'] = True
    save(JOURNAL, record)
    tracked_call([str(local / 'bin/keychain-bridge'), 'add', record['account']],
                   record=record, persist=lambda: save(JOURNAL, record), input=secret, check=True, stdout=subprocess.DEVNULL)
    del secret
    config['initialized'] = True
    save(local / 'tools.json', config)
    # Same-volume atomic promotion; there is never an overwrite of an old install.
    if LOCAL.exists():
        raise RuntimeError('Installation appeared during setup; refusing replacement.')
    local.rename(LOCAL)
    record['status'] = 'passed'
    save(JOURNAL, record)


def setup(target=None, build_only=False, pins=None):
    if not build_only and not LOCAL.exists() and not sys.stdin.isatty():
        raise RuntimeError('First setup requires your own Terminal; no downloads were started.')
    ensure()
    with os.fdopen(os.open(safe(ROOT / '.lab.lock'), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600), 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        assert_idle(ROOT)
        receipt = safe(ROOT / 'cleanup.json')
        if receipt.exists():
            pending = json.loads(receipt.read_text())
            if pending.get('action') == '--reset' and pending.get('status') == 'started':
                raise RuntimeError('Finish the interrupted --reset --apply before creating a new installation.')
        clean_pending()
        if LOCAL.exists():
            if ready():
                print('IPA Loom is already configured')
                return
            raise RuntimeError('Existing incomplete runtime is preserved. Use --reset after reviewing it.')
        preflight()
        account = uuid.uuid4().hex
        record = {'schema': 1, 'account': account, 'status': 'running', 'started': now(), 'steps': []}
        save(JOURNAL, record)
        safe(STAGE).mkdir(mode=0o700)
        marker = STAGE / '.owner.tmp'
        with marker.open('x') as output:
            output.write(account)
            output.flush()
            os.fsync(output.fileno())
        marker.rename(STAGE / '.owner')
        (STAGE / 'tmp').mkdir(mode=0o700)
        env = os.environ.copy()
        for name in ('DEV_IPA_PASSPHRASE_FD', 'GOFLAGS', 'GOROOT', 'GOCACHEPROG', 'GONOSUMDB', 'GONOPROXY', 'GOPRIVATE'):
            env.pop(name, None)
        env['TMPDIR'] = str(STAGE / 'tmp')
        try:
            local, config = build(record, env, pins)
            if build_only:
                record['status'] = 'build-verified'
                save(JOURNAL, record)
            else:
                initialize(record, env, local, config, target)
        except BaseException as exc:
            record.update(status='failed', failure_type=type(exc).__name__)
            save(JOURNAL, record)
            raise
        finally:
            # Recovery also covers an interruption after the atomic promotion.
            if record.get('ownership_pending') or record.get('process_state'):
                print('Recovery required: staging preserved', file=sys.stderr)
            else:
                clean_pending()
        print('Setup check complete' if build_only else 'IPA Loom is ready')
