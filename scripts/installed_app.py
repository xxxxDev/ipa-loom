"""Read an installed iOS bundle into a private IPA without writing to the source."""
import errno
import hashlib
import os
from pathlib import Path
import plistlib
import stat
import time
import zipfile

MAX_FILES = 100000
MAX_BYTES = 32 * 1024**3
MAX_IPA_BYTES = 8 * 1024**3
MAX_PLIST_BYTES = 8 * 1024**2


def _directory(path):
    """Anchor every directory lookup to an open parent; never follow a link."""
    path = Path(os.path.abspath(path))
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.parts[1:]:
            try:
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            except OSError as error:
                if error.errno in (errno.ELOOP, errno.ENOTDIR):
                    raise ValueError('The app path must not pass through a symbolic link or a non-folder.')
                if error.errno == errno.ENOENT:
                    raise ValueError('No installed app at that path.')
                raise
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


def _info(fd):
    handle = os.open('Info.plist', os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    with os.fdopen(handle, 'rb') as source:
        st = os.fstat(source.fileno())
        if not stat.S_ISREG(st.st_mode) or st.st_size > MAX_PLIST_BYTES:
            raise ValueError('Installed app Info.plist is not a bounded regular file.')
        data = source.read(MAX_PLIST_BYTES + 1)
        if len(data) > MAX_PLIST_BYTES:
            raise ValueError('Installed app Info.plist exceeds size limit.')
    value = plistlib.loads(data)
    if not isinstance(value, dict):
        raise ValueError('Installed app Info.plist must be a dictionary.')
    return value


def resolve_app(value):
    path = Path(os.path.abspath(Path(value).expanduser()))
    if path.suffix.lower() != '.app':
        raise ValueError('An installed .app directory is required.')
    fd = _directory(path)
    try:
        try:
            info = _info(fd)
        except FileNotFoundError:
            info = {}
        if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
            # macOS wraps iOS apps. Do not follow the outer WrappedBundle symlink.
            try:
                wrapper = os.open('Wrapper', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            except FileNotFoundError:
                raise ValueError('Only installed iPhone/iPad apps are supported, not native Mac apps.')
            try:
                candidates = [n for n in os.listdir(wrapper) if n.endswith('.app')]
                if len(candidates) != 1:
                    raise ValueError('Expected exactly one iOS app inside Wrapper.')
                child = os.open(candidates[0], os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=wrapper)
            finally:
                os.close(wrapper)
            os.close(fd)
            fd = child
            path = path / 'Wrapper' / candidates[0]
            info = _info(fd)
        if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
            raise ValueError('Only installed iPhone/iPad apps are supported, not native Mac apps.')
        executable = info.get('CFBundleExecutable')
        if not isinstance(executable, str) or executable in ('', '.', '..') or '/' in executable or '\\' in executable:
            raise ValueError('Invalid installed app executable name.')
        if not stat.S_ISREG(os.stat(executable, dir_fd=fd, follow_symlinks=False).st_mode):
            raise ValueError('Installed app executable must be a regular file.')
        if any(c in path.name for c in ('/', '\\')) or any(ord(c) < 32 or ord(c) == 127 for c in path.name):
            raise ValueError('Unsupported installed app bundle name.')
        return path
    finally:
        os.close(fd)


def _stamp(st):
    return (st.st_dev, st.st_ino, st.st_mode, st.st_size, st.st_mtime_ns, st.st_ctime_ns)


def scan_bundle(path, archive=None):
    """Hash each entry and optionally copy it to ZIP; reject links and mutations."""
    snapshot = {}
    total = 0
    last_progress = time.monotonic()
    root = _directory(path)

    def walk(fd, prefix=''):
        nonlocal total, last_progress
        before = _stamp(os.fstat(fd))
        snapshot[prefix] = ('directory', before)
        if archive is not None:
            directory = zipfile.ZipInfo('Payload/' + path.name + '/' + prefix)
            directory.create_system = 3
            directory.external_attr = (os.fstat(fd).st_mode << 16) | 0x10
            archive.writestr(directory, b'')
        names = sorted(os.listdir(fd))
        if len(names) + len(snapshot) > MAX_FILES:
            raise ValueError('Installed app has too many entries.')
        for name in names:
            if '\\' in name or any(ord(c) < 32 or ord(c) == 127 for c in name):
                raise ValueError('Unsupported installed app entry name.')
            relative = prefix + name
            st = os.stat(name, dir_fd=fd, follow_symlinks=False)
            if stat.S_ISDIR(st.st_mode):
                child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                try:
                    if _stamp(os.fstat(child)) != _stamp(st):
                        raise ValueError('Installed app changed during directory lookup.')
                    walk(child, relative + '/')
                finally:
                    os.close(child)
            elif stat.S_ISREG(st.st_mode):
                if st.st_size > MAX_BYTES or total + st.st_size > MAX_BYTES:
                    raise ValueError('Installed app exceeds size limit.')
                handle = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
                with os.fdopen(handle, 'rb') as source:
                    if _stamp(os.fstat(source.fileno())) != _stamp(st):
                        raise ValueError('Installed app changed during file lookup.')
                    digest = hashlib.sha256()
                    size = 0
                    target = None
                    try:
                        if archive is not None:
                            entry = zipfile.ZipInfo('Payload/' + path.name + '/' + relative)
                            entry.create_system = 3
                            entry.external_attr = st.st_mode << 16
                            entry.compress_type = zipfile.ZIP_DEFLATED
                            target = archive.open(entry, 'w', force_zip64=True)
                        while True:
                            chunk = source.read(1024 * 1024)
                            if not chunk:
                                break
                            size += len(chunk)
                            if size > st.st_size:
                                raise ValueError('Installed app changed while being copied.')
                            digest.update(chunk)
                            if target:
                                target.write(chunk)
                                if archive.fp.tell() > MAX_IPA_BYTES:
                                    raise ValueError('Packaged IPA exceeds size limit.')
                            if time.monotonic() - last_progress >= 5:
                                print('  Inspecting/copying installed app; processed ' + str(total + size) + ' bytes', flush=True)
                                last_progress = time.monotonic()
                    finally:
                        if target:
                            target.close()
                    if size != st.st_size or _stamp(os.fstat(source.fileno())) != _stamp(st):
                        raise ValueError('Installed app changed while being read.')
                total += size
                snapshot[relative] = ('file', _stamp(st), digest.hexdigest())
            else:
                raise ValueError('Links and special files inside the iOS bundle are not supported.')
            if len(snapshot) > MAX_FILES:
                raise ValueError('Installed app has too many entries.')
        if _stamp(os.fstat(fd)) != before:
            raise ValueError('Installed app directory changed while being read.')
    try:
        walk(root)
        return snapshot
    finally:
        os.close(root)


def package_app(path, output):
    path = resolve_app(path)
    with zipfile.ZipFile(output, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=1) as archive:
        snapshot = scan_bundle(path, archive)
    if output.stat().st_size > MAX_IPA_BYTES:
        raise ValueError('Packaged IPA exceeds size limit.')
    if scan_bundle(path) != snapshot:
        raise ValueError('Installed app changed during packaging; retry after its update finishes.')
    return path, snapshot
