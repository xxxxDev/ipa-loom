#!/usr/bin/env python3
"""Check a working tree, index snapshot, or commit without publishing it."""
import argparse
import hashlib
import os
import re
import stat
import subprocess
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
MAX_FILE = 1024 * 1024
PRIVATE_PARTS = {'.local', '.runtime', '.private', '.setup', 'records', 'logs',
                 'diagnostics', '.git', '.claude', 'tests', 'test', '__pycache__'}
PAIRS = [('README.md', 'README.zh-TW.md')]
# Only these manually reviewed pixels may bypass UTF-8 text checks. Re-review
# every replacement before updating its hash; an inventory entry alone is not enough.
SCREENSHOTS = {
    'docs/assets/screens/ipa-loom-help.png': '6f55cdbe112221c249862058fd193a3056c74041d67ca1b5618102539e672b7e',
    'docs/assets/screens/ipa-loom-workflow.png': 'd9161b8b927288bee584809aab4819b34c188b76480f4ba817d562347b9d046c',
}


def source_text(name, data):
    if name in SCREENSHOTS:
        if (not data.startswith(b'\x89PNG\r\n\x1a\n')
                or hashlib.sha256(data).hexdigest() != SCREENSHOTS[name]):
            raise ValueError('Screenshot differs from reviewed image: ' + name)
        return ''
    return data.decode('utf-8')


def git(*args):
    env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull,
               GIT_NO_REPLACE_OBJECTS='1', GIT_TERMINAL_PROMPT='0')
    return subprocess.check_output(
        ['git', '--no-optional-locks', '-c', 'core.fsmonitor=false', *args],
        cwd=ROOT, env=env, stderr=subprocess.PIPE)


def public_path(name):
    path = PurePosixPath(name)
    return (bool(name) and not path.is_absolute() and str(path) == name
            and not any(part in ('', '.', '..') for part in name.split('/'))
            and not PRIVATE_PARTS.intersection(path.parts)
            and ('.zh-TW.' not in path.name or name == 'README.zh-TW.md')
            and not any(ord(c) < 32 or ord(c) == 127 for c in name)
            and '\\' not in name
            and not path.name.startswith(('.env', 'test_'))
            and path.name not in ('AGENTS.md', 'CLAUDE.md', 'PROJECT-STATE.md')
            and '.test.' not in path.name and '.spec.' not in path.name
            and not path.name.endswith(('_test.go', '_test.py'))
            and path.suffix.lower() not in {'.ipa', '.sinf', '.supf', '.supp', '.bin',
                                           '.capture', '.recovery', '.keychain-db', '.log', '.pyc'})


def working_source():
    files = {}
    directories_seen = set()
    for current, directories, names in os.walk(ROOT, followlinks=False):
        base = Path(current)
        for directory in list(directories):
            path = base / directory
            name = path.relative_to(ROOT).as_posix()
            if name == '.git':
                directories.remove(directory)
                continue
            directories_seen.add(name)
            if path.is_symlink():
                files[name] = 'symlink'
                directories.remove(directory)
        for filename in names:
            path = base / filename
            name = path.relative_to(ROOT).as_posix()
            if name == '.git':  # Git worktrees use a metadata file here.
                continue
            mode = path.lstat().st_mode
            files[name] = 'file' if stat.S_ISREG(mode) else 'special'

    def read(name):
        path = ROOT / name
        if files.get(name) != 'file' or any(p.is_symlink() for p in [path, *path.parents]):
            raise ValueError('Non-regular file or symlink: ' + name)
        with path.open('rb') as stream:
            data = stream.read(MAX_FILE + 1)
        if len(data) > MAX_FILE:
            raise ValueError('Unexpected large file: ' + name)
        return source_text(name, data)

    return files, directories_seen, read, 'working tree (not the index or a commit)'


def git_source(staged=False, ref=None):
    files = {}
    if staged:
        records = git('ls-files', '--stage', '-z')
        label = 'index snapshot (staged blobs, not working-tree files)'
    else:
        if not ref or not ref.strip():
            raise ValueError('A nonempty commit reference is required.')
        commit = git('rev-parse', '--verify', '--end-of-options', ref + '^{commit}').decode().strip()
        records = git('ls-tree', '-r', '-z', '--full-tree', commit)
        label = 'commit ' + commit
    for record in records.split(b'\0'):
        if not record:
            continue
        header, raw_name = record.split(b'\t', 1)
        name = raw_name.decode('utf-8')
        first, second, third = header.decode('ascii').split()
        if staged:
            mode, oid, stage = first, second, third
            if stage != '0':
                raise ValueError('Unmerged index entry: ' + name)
        else:
            mode, kind, oid = first, second, third
            if kind != 'blob':
                raise ValueError('Non-blob Git entry: ' + name)
        if mode not in ('100644', '100755'):
            raise ValueError('Symlink or non-regular Git entry: ' + name)
        if name in files:
            raise ValueError('Duplicate Git entry: ' + name)
        files[name] = oid
    if not files:
        raise ValueError('No candidate files in the selected Git snapshot.')

    def read(name):
        if name not in files:
            raise ValueError('Missing file: ' + name)
        oid = files[name]
        if int(git('cat-file', '-s', oid)) > MAX_FILE:
            raise ValueError('Unexpected large file: ' + name)
        return source_text(name, git('cat-file', 'blob', oid))

    return files, set(), read, label


def check(staged=False, ref=None):
    try:
        files, directories, read, label = git_source(staged, ref) if staged or ref is not None else working_source()
        print('Checking: ' + label)
        entries = read('PUBLIC-FILES.txt').splitlines()
        expected = set(entries)
        errors = []
        if not entries or len(entries) != len(expected):
            errors.append('Empty or duplicate public inventory.')
        for name in sorted(set(files) - expected):
            errors.append('Unexpected source file: ' + name)
        for name in sorted(expected - set(files)):
            errors.append('Inventory file missing: ' + name)
        allowed_dirs = {str(p) for name in entries for p in PurePosixPath(name).parents if str(p) != '.'}
        for name in sorted(directories - allowed_dirs):
            errors.append('Unexpected physical directory: ' + name)
        texts = {}
        for name in entries:
            if not public_path(name):
                errors.append('Invalid public path: ' + name)
                continue
            try:
                text = read(name)
            except (OSError, UnicodeError, ValueError) as error:
                errors.append(type(error).__name__ + ' reading: ' + name)
                continue
            texts[name] = text
            language_text = text
            if name == 'README.md':
                # A language-switch link uses the destination language's own name.
                language_text = language_text.replace(
                    '<a href="README.zh-TW.md">'
                    + ''.join(map(chr, (0x7e41, 0x9ad4, 0x4e2d, 0x6587)))
                    + '</a>', '', 1)
            if name != 'README.zh-TW.md' and any(0x3400 <= ord(character) <= 0x9fff for character in language_text):
                errors.append('Chinese text outside the translated README: ' + name)
            # Bounded sanity checks, never a substitute for human review.
            if re.search(r'/Users/[A-Za-z0-9_.-]+/', text):
                errors.append('Local home path in: ' + name)
            if re.search(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', text):
                errors.append('Private-key marker in: ' + name)
            if name.endswith('.patch') and re.search(r'^\+\+\+ .*_test\.go$', text, re.M):
                errors.append('Private test patch in: ' + name)
            if name.endswith('.py'):
                try:
                    compile(text, name, 'exec')
                except (SyntaxError, ValueError):
                    errors.append('Invalid Python syntax in: ' + name)
        for first, second in PAIRS:
            if first not in texts or second not in texts:
                errors.append('Missing bilingual document: ' + first + ' / ' + second)
            elif len(texts[first].splitlines()) != len(texts[second].splitlines()):
                errors.append('Bilingual line-count mismatch: ' + first)
        if errors:
            print('\n'.join(errors))
            return 1
        print(f'PASS: {len(expected)} files match the selected public inventory (text and hash-pinned screenshots); Python syntax checked.')
        print('No files exported, staged, committed, or published. Review content, author metadata, history and final archives separately.')
        return 0
    except (OSError, UnicodeError, ValueError, subprocess.CalledProcessError):
        print('FAIL: selected source could not be read. Check the inventory, Git state and requested commit.')
        return 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    source = parser.add_mutually_exclusive_group()
    source.add_argument('--staged', action='store_true', help='check the current index blobs')
    source.add_argument('--ref', metavar='COMMIT', help='check an immutable commit tree; print its full object id')
    arguments = parser.parse_args()
    raise SystemExit(check(arguments.staged, arguments.ref))
