"""Windows build defaults. Read only four fixed public fields from owned assets."""
import json
import pathlib
import stat


def _unique_object(pairs):
    value = {}
    for name, field in pairs:
        if name in value:
            raise ValueError('Duplicate Windows public profile field')
        value[name] = field
    return value


def _profile_bytes(project, previous, previous_ip=False):
    root = pathlib.Path(project).resolve()
    name = 'previous-ip-connection.json' if previous_ip else ('previous-public-connection.json' if previous else 'default-connection.json')
    profile = root / 'desktop/assets' / name
    for path in (profile, *profile.parents):
        details = path.lstat()
        if path.is_symlink() or getattr(details, 'st_file_attributes', 0) & getattr(stat, 'FILE_ATTRIBUTE_REPARSE_POINT', 0):
            raise ValueError('Redirected Windows public profile path')
        if path == root:
            break
    if profile.resolve().parent != root / 'desktop/assets' or not profile.is_file() or not 0 < profile.stat().st_size <= 16384:
        raise ValueError('Windows public profile is not a bounded owned asset')
    data = profile.read_bytes()
    if not 0 < len(data) <= 16384:
        raise ValueError('Windows public profile exceeds size limit')
    value = json.loads(data.decode('utf-8-sig'), object_pairs_hook=_unique_object)
    expected = {
        'schemaVersion': 1,
        'idServer': ('64.176.235.139:' + ('443' if previous else '24443')) if previous or previous_ip else 'videopmt.com:24443',
        'relayServer': '64.176.235.139:21117' if previous or previous_ip else 'videopmt.com:21117',
        'publicKey': 'xeGt6mV0n19F0pGH81NoSJNOUKRWqmXmmwObSEzENEg=',
    }
    if value != expected or type(value['schemaVersion']) is not int:
        raise ValueError('Windows public profile differs from the domain release contract')
    return (json.dumps(expected, indent=2) + '\n').encode('utf-8')


def current_windows_profile_bytes(project):
    return _profile_bytes(project, False)


def previous_windows_public_profile_bytes(project):
    return _profile_bytes(project, True)


def previous_windows_ip_profile_bytes(project):
    return _profile_bytes(project, False, previous_ip=True)
