#!/usr/bin/env python3
"""Detect upstream releases; optionally build candidates without promoting them."""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import quote, urlparse

CODE_ROOT = Path(__file__).resolve().parents[1]
REPOS = {'ipatool': 'majd/ipatool', 'unfairplay': 'DrWhax/unfairplay'}


def fetch(url, destination=None):
    host = urlparse(url).hostname
    if urlparse(url).scheme != 'https' or host not in ('api.github.com', 'github.com'):
        raise ValueError('Unexpected upstream URL.')
    command = ['/usr/bin/curl', '-q', '--fail', '--silent', '--show-error', '--location',
               '--proto', '=https', '--proto-redir', '=https', '--connect-timeout', '20', '--max-time', '600', url]
    if destination:
        subprocess.run(command + ['--output', str(destination)], check=True)
        return None
    return subprocess.check_output(command)


def metadata(repo, path):
    return json.loads(fetch('https://api.github.com/repos/' + repo + '/' + path))


def stable_version(tag):
    match = re.fullmatch(r'v?(\d+)\.(\d+)\.(\d+)', tag)
    if not match:
        raise ValueError('Unrecognized stable upstream version: ' + tag)
    return tuple(map(int, match.groups()))


def detect(pins):
    report = {'schema': 1, 'status': 'checked', 'promotion': 'never-automatic', 'upstreams': {}}
    releases = {}
    for name, repo in REPOS.items():
        release = metadata(repo, 'releases/latest')
        tag = release['tag_name']
        if release.get('draft') or release.get('prerelease'):
            raise ValueError('Latest endpoint returned a non-stable release.')
        newer = stable_version(tag) > stable_version(pins[name]['version'])
        report['upstreams'][name] = {'pinned': pins[name]['version'], 'latest': tag,
            'newer': newer, 'published_at': release.get('published_at'),
            'url': 'https://github.com/' + repo + '/releases/tag/' + quote(tag, safe='')}
        releases[name] = release
    return report, releases


def candidate_pins(pins, releases, report, workspace):
    candidate = copy.deepcopy(pins)
    for name, item in report['upstreams'].items():
        if not item['newer']:
            continue
        release = releases[name]
        tag = release['tag_name']
        repo = REPOS[name]
        if name == 'ipatool':
            commit = metadata(repo, 'commits/' + quote(tag, safe=''))['sha']
            if not re.fullmatch('[0-9a-f]{40}', commit):
                raise ValueError('Invalid upstream commit.')
            url = 'https://api.github.com/repos/' + repo + '/tarball/' + commit
            archive = workspace / 'candidate-source.tar.gz'
            fetch(url, archive)
            # Observed hash pins this candidate's second fetch; it is not a signed release attestation.
            h = hashlib.sha256()
            with archive.open('rb') as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b''):
                    h.update(chunk)
            sha = h.hexdigest()
            candidate[name].update(version=tag, commit=commit, url=url, sha256=sha)
            item['source_hash_basis'] = 'HTTPS snapshot of resolved upstream commit; maintainer review required'
        else:
            filename = 'unfairplay-' + tag + '-darwin-arm64.tar.gz'
            assets = {a['name']: a for a in release.get('assets', [])}
            asset = assets.get(filename)
            if not asset:
                raise ValueError('Candidate lacks the expected arm64 archive.')
            url = asset['browser_download_url']
            expected_prefix = 'https://github.com/' + repo + '/releases/download/' + tag + '/'
            if not url.startswith(expected_prefix):
                raise ValueError('Candidate asset is outside the expected release.')
            digest = asset.get('digest') or ''
            if re.fullmatch('sha256:[0-9a-f]{64}', digest):
                sha = digest[7:]
            else:
                checksums = assets.get('SHA256SUMS')
                if not checksums or not checksums['browser_download_url'].startswith(expected_prefix):
                    raise ValueError('Candidate has no publisher checksum; review manually.')
                lines = fetch(checksums['browser_download_url']).decode().splitlines()
                matches = [line.split()[0] for line in lines if len(line.split()) == 2 and line.split()[1].lstrip('*') == filename]
                if len(matches) != 1 or not re.fullmatch('[0-9a-f]{64}', matches[0]):
                    raise ValueError('Missing or ambiguous candidate checksum.')
                sha = matches[0]
            candidate[name].update(version=tag, url=url, sha256=sha)
    return candidate


def verify(candidate, report, workspace):
    if sys.platform != 'darwin':
        raise RuntimeError('Candidate build checks require an Apple Silicon Mac.')
    manifest = workspace / 'candidate.json'
    manifest.write_text(json.dumps(candidate, indent=2) + '\n')
    env = {k: os.environ[k] for k in ('HOME', 'LANG', 'LC_ALL') if k in os.environ}
    env.update(PATH='/usr/bin:/bin:/usr/sbin:/sbin', IPA_LOOM_DATA_HOME=str(workspace / 'data'))
    result = subprocess.run([sys.executable, '-B', str(CODE_ROOT / 'scripts/candidate_build.py'), str(manifest)], env=env)
    report['candidate_build'] = 'passed' if result.returncode == 0 else 'failed'
    report['candidate_pins'] = candidate
    report['required_before_promotion'] = ['review source/license changes and hashes',
        'a full authorized run', 'maintainer-reviewed dependency pin change and date release']
    report['status'] = 'needs-full-run' if result.returncode == 0 else 'incompatible-or-build-failed'
    return result.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', action='store_true', help='Build newer candidates in disposable storage; never log in or upgrade.')
    parser.add_argument('--report', type=Path, help='Write a redacted metadata report to this explicit path.')
    args = parser.parse_args()
    pins = json.loads((CODE_ROOT / 'config/dependencies.json').read_text())
    report = {'schema': 1, 'status': 'failed', 'promotion': 'never-automatic'}
    code = 0
    try:
        report, releases = detect(pins)
        for name, info in report['upstreams'].items():
            print(name + ': ' + info['pinned'] + ' -> ' + info['latest'] + (' (candidate)' if info['newer'] else ' (current)'))
        if args.verify and any(item['newer'] for item in report['upstreams'].values()):
            workspace = Path(tempfile.mkdtemp(prefix='ipa-loom-candidate-')).resolve()
            builder_returned = False
            builder_started = False
            try:
                candidate = candidate_pins(pins, releases, report, workspace)
                builder_started = True
                code = verify(candidate, report, workspace)
                builder_returned = True
            finally:
                # A killed builder can leave detached children. Never assume its
                # return, or a vanished PID, proves that the scratch tree is idle.
                from processes import assert_quiescent
                cleanable = not builder_started or builder_returned
                journal = workspace / 'data/setup.json'
                if cleanable and journal.exists():
                    state = json.loads(journal.read_text())
                    try:
                        assert_quiescent(state)
                    except RuntimeError:
                        cleanable = False
                    cleanable = cleanable and not state.get('ownership_pending')
                if cleanable:
                    shutil.rmtree(workspace)
                else:
                    print('Candidate workspace retained for process inspection: ' + str(workspace), file=sys.stderr)
        elif args.verify:
            report['candidate_build'] = 'not-needed'
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.CalledProcessError) as error:
        report.update(status='check-failed', error_type=type(error).__name__)
        print('Update check failed: ' + type(error).__name__, file=sys.stderr)
        code = 1
    finally:
        if args.report:
            # Only curated metadata is exported, never raw build logs or environment values.
            with args.report.open('x') as output:
                json.dump(report, output, indent=2)
                output.write('\n')
    return code


if __name__ == '__main__':
    raise SystemExit(main())
