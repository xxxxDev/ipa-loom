"""Child lifecycle records: uncertain termination must never authorize deletion."""
import json
import os
from pathlib import Path
import signal
import subprocess
import time


def assert_quiescent(record):
    if record.get('process_state'):
        raise RuntimeError('Unresolved child lifecycle; preserve files and inspect processes before recovery.')
    pid = record.get('active_child')
    if type(pid) is int:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        raise RuntimeError('A recorded child may still be running; cleanup refused.')


def assert_idle(root):
    from runtime import safe
    paths = [root / 'setup.json', root / 'cleanup.json', *safe(root / 'records').glob('*.json')]
    for path in paths:
        if safe(path).exists():
            assert_quiescent(json.loads(path.read_text()))


def execute(command, *, record, persist, terminal=False, progress=None, **kwargs):
    """Retain the controlling terminal for prompts; isolate other process groups.

    A hard-killed wrapper leaves a durable uncertainty marker. We deliberately
    do not infer that a disappeared PID proves all descendants have exited.
    """
    child = None
    completed = False
    record['process_state'] = 'starting'
    persist()
    try:
        child = subprocess.Popen(command, start_new_session=not terminal, **kwargs)
        record.update(process_state='running', active_child=child.pid)
        persist()
        while True:
            try:
                code = child.wait(timeout=5)
                completed = True
                return code
            except subprocess.TimeoutExpired:
                if progress:
                    progress()
    finally:
        uncertain = False
        if child is not None:
            if completed:
                if not terminal:
                    # wait() reaped the leader. Never signal a possibly reused ID.
                    try:
                        os.killpg(child.pid, 0)
                    except ProcessLookupError:
                        pass
                    else:
                        uncertain = True
            elif child.returncode is not None:
                # wait() may reap during its KeyboardInterrupt grace period.
                # Never signal a recycled PID/group after that point.
                uncertain = True
            else:
                # No wait/poll has reaped this leader in this branch.
                if not terminal:
                    try:
                        os.killpg(child.pid, signal.SIGTERM)
                        time.sleep(0.05)
                        os.killpg(child.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    except PermissionError:
                        # macOS may reject SIGKILL for a group whose leader exited
                        # after SIGTERM but has not been reaped. Reap only our child;
                        # never send another signal once its PID could be reused.
                        if child.poll() is None:
                            raise
                        try:
                            os.killpg(child.pid, 0)
                        except ProcessLookupError:
                            pass
                        else:
                            uncertain = True
                else:
                    child.terminate()
                    uncertain = True
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=5)
        if uncertain:
            record['process_state'] = 'uncertain'
        else:
            record.pop('process_state', None)
            record.pop('active_child', None)
        persist()
        if uncertain and completed:
            raise RuntimeError('Child process group remains after tool exit; files preserved.')


def tracked_call(command, *, record, persist, **kwargs):
    """Track small synchronous bridge operations without persisting secret output.

    subprocess.run reaps the direct command on ordinary completion. Interrupted
    calls remain uncertain: cleanup cannot race a native authorization operation.
    """
    record['process_state'] = 'starting'
    persist()
    try:
        result = subprocess.run(command, **kwargs)
    except subprocess.CalledProcessError:
        record.pop('process_state', None)
        persist()
        raise
    except BaseException:
        record['process_state'] = 'uncertain'
        persist()
        raise
    record.pop('process_state', None)
    persist()
    return result
