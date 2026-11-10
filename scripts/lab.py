#!/usr/bin/env python3
'Local experiment ledger. Never runs upstream tools or removes host state.'
import argparse
import datetime
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import uuid

from runtime import ROOT, MARKER, ensure
from processes import assert_quiescent

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def safe(path):
    # Reject symlinks in all existing components, including the project root.
    for p in [path, *path.parents]:
        if p.is_symlink():
            raise ValueError('symlink path rejected: ' + str(p))
    path.relative_to(ROOT)
    return path

def directory(path):
    safe(path).mkdir(mode=0o700, parents=True, exist_ok=True)
    if not path.is_dir():
        raise ValueError('not a directory')

def save(path, value):
    safe(path)
    temp = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    with temp.open('x') as f:
        json.dump(value, f, ensure_ascii=False, indent=2)
        f.write('\n')
    os.replace(temp, path)

def load_run(run_id):
    if not re.fullmatch(r'[0-9a-f]{32}', run_id):
        raise ValueError('invalid run ID')
    report = safe(ROOT / 'records' / (run_id + '.json'))
    data = json.loads(report.read_text())
    if data.get('id') != run_id or data.get('schema') != 1:
        raise ValueError('invalid run record')
    return report, data

def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('start')
    p.add_argument('--target', choices=['app', 'synthetic'], required=True)
    p = sub.add_parser('finish')
    p.add_argument('id')
    p.add_argument('--status', choices=['passed', 'failed', 'blocked', 'interrupted'], required=True)
    p.add_argument('--exit-code', type=int, required=True)
    p.add_argument('--revision', default='not-run')
    p = sub.add_parser('clean')
    p.add_argument('id')
    p.add_argument('--apply', action='store_true')
    sub.add_parser('list')
    args = parser.parse_args()
    ensure()
    directory(ROOT / 'records')
    lockpath = safe(ROOT / '.lab.lock')
    fd = os.open(lockpath, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.command == 'start':
            run_id = uuid.uuid4().hex
            report = ROOT / 'records' / (run_id + '.json')
            # Record before allocation: interrupted allocation is discoverable.
            data = dict(schema=1, id=run_id, target=args.target, started=now(),
                        status='running', cleanup='pending', tool_revision='not-run',
                        external_changes=[], plaintext_verified=None)
            save(report, data)
            work = ROOT / '.runtime' / 'runs' / run_id
            for name in ['input', 'output', 'tmp', 'cache', 'tools', 'models', 'private-logs']:
                directory(work / name)
            print(json.dumps(dict(id=run_id, work=str(work))))
        elif args.command == 'list':
            for path in sorted((ROOT / 'records').glob('*.json')):
                data = json.loads(safe(path).read_text())
                print(json.dumps(data, ensure_ascii=False))
        else:
            report, data = load_run(args.id)
            assert_quiescent(data)
            if args.command == 'finish':
                if data['status'] != 'running':
                    raise ValueError('run is already closed')
                if not re.fullmatch(r'(?:not-run|[0-9a-f]{7,64})', args.revision):
                    raise ValueError('revision must be a commit hash or not-run')
                if args.status == 'passed' and args.exit_code != 0:
                    raise ValueError('passed requires exit code zero')
                data.update(status=args.status, exit_code=args.exit_code,
                            tool_revision=args.revision, ended=now())
                save(report, data)
                print(args.status)
            else:
                if data['status'] == 'running':
                    raise ValueError('stop the tool and finish the run before cleaning')
                target = safe(ROOT / '.runtime' / 'runs' / args.id)
                print(json.dumps(dict(target=str(target), apply=args.apply,
                                      preserve=str(report))))
                if args.apply:
                    if not shutil.rmtree.avoids_symlink_attacks:
                        raise ValueError('this Python lacks safe recursive deletion')
                    # Audit intent survives interruption or partial deletion.
                    data.update(cleanup='started', cleanup_started=now())
                    save(report, data)
                    if target.exists():
                        if not stat.S_ISDIR(target.lstat().st_mode):
                            raise ValueError('run target is not a directory')
                        shutil.rmtree(target)
                    data.update(cleanup='done', cleaned=now())
                    save(report, data)

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as exc:
        print('error: ' + str(exc), file=sys.stderr)
        sys.exit(1)
