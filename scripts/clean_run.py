#!/usr/bin/env python3
"""Preview or remove the working files of one closed run, keeping its summary."""
import argparse
import fcntl
import json
import os
import shutil
import stat
import sys

from runtime import ROOT, safe, save, now, load_run, directory, ensure
from processes import assert_quiescent


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('id')
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    ensure()
    directory(ROOT / 'records')
    lockpath = safe(ROOT / '.lab.lock')
    fd = os.open(lockpath, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        report, data = load_run(args.id)
        assert_quiescent(data)
        if data['status'] == 'running':
            raise ValueError('stop the tool and finish the run before cleaning')
        target = safe(ROOT / '.runtime' / 'runs' / args.id)
        print(json.dumps(dict(target=str(target), apply=args.apply, preserve=str(report))))
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
