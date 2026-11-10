"""Private application storage, separate from the source checkout."""
import os
from pathlib import Path
import stat

PRODUCT = 'IPA Loom'
CODE_ROOT = Path(__file__).resolve().parents[1]
MARKER = 'ipa-loom-data-v1\n'
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
