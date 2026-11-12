#!/usr/bin/env python3
"""IPA Loom's user entry point."""
import fcntl
import json
import os
import subprocess
import sys
import zipfile
from pathlib import Path

from runtime import ROOT, safe, ensure, inspect
from setup import LOCAL, JOURNAL, clean_pending, ready, remove_tree, setup, validate_tools
from runtime import save, now
from processes import assert_idle, tracked_call


def maintenance(action, apply=False):
    if action == '--doctor':
        if not inspect():
            print('Setup required')
            return 1
        if safe(ROOT / '.setup').exists():
            print('Pending setup: use --recover')
            return 1
        receipt = safe(ROOT / 'cleanup.json')
        if receipt.exists() and json.loads(receipt.read_text()).get('status') == 'started':
            print('Incomplete cleanup: resume the same cleanup command')
            return 1
        try:
            assert_idle(ROOT)
        except RuntimeError as error:
            print(str(error))
            return 1
        configured = ready()
        print('Ready' if configured else 'Setup required')
        print('Private data: ' + str(ROOT))
        return 0 if configured else 1
    ensure()
    with os.fdopen(os.open(safe(ROOT / '.lab.lock'), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600), 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        assert_idle(ROOT)
        if action == '--recover':
            clean_pending()
            print('Pending setup recovered')
            return 0
        # Cleanup does not remove the data-root marker or lock inode.
        names = ['.runtime', 'diagnostics'] if action == '--clean-runs' else ['.local', '.runtime', 'diagnostics', 'records', 'setup.json']
        print('Removal scope: ' + ', '.join(names))
        print('Root: ' + str(ROOT))
        if not apply:
            print('Preview only. Add --apply to delete')
            return 0
        clean_pending()
        receipt = ROOT / 'cleanup.json'
        previous = json.loads(safe(receipt).read_text()) if receipt.exists() else {}
        if previous.get('status') == 'started' and previous.get('action') != action:
            raise RuntimeError('Resume the interrupted cleanup command before another cleanup action.')
        account = None
        if action == '--reset' and LOCAL.exists():
            config = validate_tools()
            account = config.get('keychain_account', '')
            if len(account) != 32 or any(c not in '0123456789abcdef' for c in account):
                raise ValueError('Invalid Keychain account.')
            keychain_done = (previous.get('action') == action and previous.get('status') == 'started'
                             and previous.get('keychain_done') is True and previous.get('keychain_account') == account)
            if not keychain_done:
                deletion = {'action':action, 'status':'started', 'keychain_account':account, 'keychain_done':False}
                tracked_call([str(LOCAL / 'bin/keychain-bridge'), 'delete', account],
                             record=deletion, persist=lambda: save(receipt,deletion), check=True)
        # Keep a resumable deletion receipt outside the folders being removed.
        save(receipt, {'action': action, 'status': 'started', 'keychain_done': action == '--reset', 'keychain_account': account, 'started': now()})
        for name in names:
            path = safe(ROOT / name)
            if path.is_dir():
                remove_tree(path)
            elif path.exists():
                path.unlink()
        save(receipt, {'action': action, 'status': 'passed', 'ended': now()})
        print('Cleanup complete')
        return 0


def main():
    args = sys.argv[1:]
    action = args[0] if args else None
    if action in ('--doctor', '--recover', '--reset', '--clean-runs'):
        if len(args) > 2 or any(x != '--apply' for x in args[1:]) or ('--apply' in args and action in ('--doctor', '--recover')):
            raise ValueError('Unexpected maintenance arguments.')
        return maintenance(action, '--apply' in args)
    if action in ('--setup', '--check-build'):
        if len(args) > 1:
            raise ValueError('Use setup options alone.')
        setup(build_only=action == '--check-build')
        return 0
    if action in ('--help', '-h'):
        if len(args) != 1:
            raise ValueError('Use --help alone.')
        print((Path(__file__).with_name('usage.txt')).read_text(), end='')
        return 0
    import pipeline
    parsed = pipeline.parse_arguments(args)
    parsed_target = pipeline.parse_target(parsed.target) if parsed.target else None
    if parsed_target and parsed_target[0] == 'installed-app' and not ready():
        raise RuntimeError('Installed-app decryption needs an existing verified model. Run --setup with a matching Mac App Store app and IPA first.')
    if not LOCAL.exists():
        # First setup builds the model from the chosen app and decrypts it as the first result.
        seed_store_id = setup(target=parsed.target)
        # If a different app was asked for on the command line, decrypt that one too; the chosen
        # app is already the first result, so it is never decrypted twice.
        if parsed_target and parsed_target != ('store', seed_store_id):
            pipeline.main()
        return 0
    pipeline.main()
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print('Interrupted; cleanup attempted', file=sys.stderr)
        sys.exit(130)
    except EOFError:
        print('Cancelled at a prompt; cleanup attempted', file=sys.stderr)
        sys.exit(130)
    except (OSError, ValueError, RuntimeError, KeyError, subprocess.CalledProcessError, zipfile.BadZipFile) as exc:
        print('Stopped: ' + str(exc), file=sys.stderr)
        sys.exit(1)
