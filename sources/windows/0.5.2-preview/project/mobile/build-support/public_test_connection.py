"""Build-only public defaults and a narrowly scoped previous-LAN migration.

Only four public fields may enter the APK. No private key, device ID, password,
token, process record, or other runtime field is copied into an asset or record.
"""
import base64
import ipaddress
import json
import pathlib
import stat

ASSET_SOURCE_PATH = "flutter/assets/XIXI-DEFAULT-CONNECTION.json"
ASSET_APK_PATH = "assets/flutter_assets/assets/XIXI-DEFAULT-CONNECTION.json"
PREVIOUS_SOURCE_PATH = "flutter/assets/XIXI-PREVIOUS-CONNECTION.json"
PREVIOUS_APK_PATH = "assets/flutter_assets/assets/XIXI-PREVIOUS-CONNECTION.json"
PUBLIC_FIELDS = ("schemaVersion", "idServer", "relayServer", "publicKey")
PRIVATE_NETWORKS = tuple(ipaddress.IPv4Network(prefix) for prefix in
                         ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"))


def _unique_object(pairs):
    value = {}
    for name, field in pairs:
        if name in value:
            raise RuntimeError("Duplicate field in public test profile")
        value[name] = field
    return value


def _endpoint(value, expected_ports, previous):
    if not isinstance(value, str) or len(value) > 64 or value.count(":") != 1:
        raise RuntimeError("Public endpoint must be a plain IPv4:port")
    host, port = value.split(":")
    try:
        address = ipaddress.IPv4Address(host)
    except ipaddress.AddressValueError:
        raise RuntimeError("Public test endpoint must contain canonical IPv4") from None
    valid_host = any(address in network for network in PRIVATE_NETWORKS) if previous else address.is_global
    if str(address) != host or port not in tuple(str(p) for p in expected_ports) or not valid_host:
        raise RuntimeError("Endpoint host scope or native port differs from the build contract")
    return host


def project_profile(value, previous=False):
    if not isinstance(value, dict) or type(value.get("schemaVersion")) is not int or value["schemaVersion"] != 1:
        raise RuntimeError("Public test profile requires schemaVersion 1")
    id_host = _endpoint(value.get("idServer"), (21116,) if previous else (443, 21116), previous)
    relay_host = _endpoint(value.get("relayServer"), (21117,), previous)
    if id_host != relay_host:
        raise RuntimeError("ID and relay endpoints must share the same build host")
    key = value.get("publicKey")
    if not isinstance(key, str) or len(key) != 44:
        raise RuntimeError("Public test profile requires a 32-byte public key")
    try:
        key_bytes = base64.b64decode(key, validate=True)
    except ValueError:
        raise RuntimeError("Public test key must be canonical Base64") from None
    if len(key_bytes) != 32 or base64.b64encode(key_bytes).decode("ascii") != key:
        raise RuntimeError("Public test profile requires a canonical 32-byte public key")
    return {name: value[name] for name in PUBLIC_FIELDS}


def encode_profile(value, previous=False):
    return (json.dumps(project_profile(value, previous), indent=2, ensure_ascii=True) + "\n").encode("utf-8")


def _read_profile_bytes(project, relative, previous):
    project = pathlib.Path(project).resolve()
    profile = project / relative
    if not profile.resolve().is_relative_to(project):
        raise RuntimeError("Public test profile must remain inside the project")
    for path in (profile, profile.parent):
        details = path.lstat()
        if path.is_symlink() or getattr(details, "st_file_attributes", 0) & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0):
            raise RuntimeError("Redirected public test profile paths are refused")
    if not profile.is_file() or not 0 < profile.stat().st_size <= 16384:
        raise RuntimeError("Public test profile must be a bounded local JSON file")
    data = profile.read_bytes()
    if not 0 < len(data) <= 16384:
        raise RuntimeError("Public test profile exceeds the bounded JSON size")
    value = json.loads(data.decode("utf-8-sig"), object_pairs_hook=_unique_object)
    return encode_profile(value, previous)


def current_profile_bytes(project):
    return _read_profile_bytes(project, "runtime/vps-public-profile.json", False)


def previous_profile_bytes(project):
    return _read_profile_bytes(project, "runtime/client-profile.json", True)
