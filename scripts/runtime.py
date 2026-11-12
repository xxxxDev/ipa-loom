"""Private application storage, separate from the source checkout."""
import datetime
import json
import os
from pathlib import Path
import re
import stat
import uuid

PRODUCT = 'IPA Loom'
CODE_ROOT = Path(__file__).resolve().parents[1]
MARKER = 'ipa-loom-data-v1\n'
CLEAR_EOL = '\x1b[K'  # ANSI: clear from the cursor to the end of the line, so nothing trails


def progress_bar(step, width=10, block=3):
    """An indeterminate progress bar: a moving block. Plain ASCII so every terminal renders it."""
    pos = step % (width - block + 1)
    cells = ['.'] * width
    for i in range(pos, min(pos + block, width)):
        cells[i] = '#'
    return '[' + ''.join(cells) + ']'
raw = os.environ.get('IPA_LOOM_DATA_HOME')
ROOT = Path(raw).expanduser() if raw else Path.home() / 'Library/Application Support' / PRODUCT
if not ROOT.is_absolute():
    raise ValueError('IPA_LOOM_DATA_HOME must be absolute.')
# Normalize spelling without resolving symlinks: those must be rejected.
ROOT = Path(os.path.abspath(ROOT))


def safe(path):
    path = Path(path)
    path.relative_to(ROOT)
    for part in [path, *path.parents]:
        if part.is_symlink():
            raise ValueError('Symlink in private data path.')
    return path


def inspect():
    """Validate an existing private root without creating files or changing permissions."""
    safe(ROOT)
    if ROOT in (Path('/'), Path.home(), CODE_ROOT) or ROOT in CODE_ROOT.parents or CODE_ROOT in ROOT.parents:
        raise ValueError('Refusing unsafe data root.')
    if not ROOT.exists():
        return False
    if not ROOT.is_dir() or ROOT.stat().st_uid != os.getuid():
        raise ValueError('Private data root is not owned by this user.')
    if stat.S_IMODE(ROOT.stat().st_mode) & 0o077:
        raise ValueError('Private data root must have mode 700.')
    if safe(ROOT / '.ipa-loom-data').read_text() != MARKER:
        raise ValueError('Unrecognized data root; no files were removed.')
    return True


def ensure():
    os.umask(0o077)
    if not inspect():
        ROOT.mkdir(parents=True, mode=0o700)
        (ROOT / '.ipa-loom-data').write_text(MARKER)
    safe(ROOT / 'records').mkdir(mode=0o700, exist_ok=True)


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def save(path, value):
    safe(path)
    temp = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    with temp.open('x') as f:
        json.dump(value, f, ensure_ascii=False, indent=2)
        f.write('\n')
    os.replace(temp, path)


def directory(path):
    safe(path).mkdir(mode=0o700, parents=True, exist_ok=True)
    if not path.is_dir():
        raise ValueError('not a directory')


def load_run(run_id):
    if not re.fullmatch(r'[0-9a-f]{32}', run_id):
        raise ValueError('invalid run ID')
    report = safe(ROOT / 'records' / (run_id + '.json'))
    data = json.loads(report.read_text())
    if data.get('id') != run_id or data.get('schema') != 1:
        raise ValueError('invalid run record')
    return report, data
