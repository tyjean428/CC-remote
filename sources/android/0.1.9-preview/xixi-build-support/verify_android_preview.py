"""Statically verify the project preview APK and package its corresponding source.

No ADB, device installation, native library loading, or remote connection is used.
"""
import argparse
import hashlib
import json
import pathlib
import re
import struct
import subprocess
import zipfile
from flutter_permission_overlay import transform_server_model

from public_test_connection import ASSET_APK_PATH, ASSET_SOURCE_PATH, PREVIOUS_APK_PATH, PREVIOUS_SOURCE_PATH, HISTORY_APK_PATH, HISTORY_SOURCE_PATH, HISTORY_PROJECT_PATH, PUBLIC_FIELDS, current_profile_bytes, previous_profile_bytes, history_profile_bytes


def digest(data):
    return hashlib.sha256(data).hexdigest()


def replace_once(text, old, new, description):
    if text.count(old) != 1:
        raise RuntimeError('Unexpected source anchor: ' + description)
    return text.replace(old, new, 1)


def dex_classes(data):
    if not data.startswith(b"dex\n"):
        raise RuntimeError("Unexpected DEX format")
    string_count, string_offset, type_count, type_offset = struct.unpack_from("<IIII", data, 56)
    class_count, class_offset = struct.unpack_from("<II", data, 96)
    strings = []
    for i in range(string_count):
        offset = struct.unpack_from("<I", data, string_offset + i * 4)[0]
        while data[offset] & 0x80:
            offset += 1
        offset += 1
        end = data.index(0, offset)
        strings.append(data[offset:end].decode("utf-8", "replace"))
    types = [strings[struct.unpack_from("<I", data, type_offset + i * 4)[0]] for i in range(type_count)]
    return {types[struct.unpack_from("<I", data, class_offset + i * 32)[0]] for i in range(class_count)}


def command(arguments):
    result = subprocess.run([str(x) for x in arguments], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    stdout = result.stdout.decode("utf-8", "replace").replace("\r\n", "\n")
    stderr = result.stderr.decode("utf-8", "replace").replace("\r\n", "\n")
    if result.returncode:
        raise RuntimeError("Verification tool failed: " + stdout + stderr)
    return stdout


def source_bundle(project, source, destination):
    release = json.loads((project / "mobile/build-support/android-tools.lock.json").read_text(encoding="utf-8-sig"))
    excluded_dirs = {".git", ".dart_tool", ".gradle", "build", "node_modules", "jniLibs", "__pycache__", ".idea"}
    excluded_names = {"local.properties", "key.properties", ".flutter-plugins", ".flutter-plugins-dependencies", ".packages"}
    excluded_suffixes = {".p12", ".jks", ".keystore", ".dpapi", ".apk", ".aab", ".pyc"}
    notice = (
        "# 西西远程 Android 预览版对应源码\n\n"
        f"预览版本：{release['previewVersionName']}，versionCode {release['previewVersionCode']}。\n\n"
        "该包包含此次预览 APK 实际构建的 RustDesk 固定源码、hbb_common、六份生成桥、"
        "西西移动界面模块和 Android 应用标识修改，保留 AGPL-3.0 与第三方声明。\n\n"
        "这是 Flutter release AOT 配合项目预览证书签名的测试包；证书私钥和密码不随源码提供。"
        "不要把该签名用于正式发布。Android 可与官方 com.carriez.flutter_hbb 应用共存。\n\n"
        "准备路径：把 xixi-build-support/ 内容放回主项目 mobile/build-support/，并保留"
        "包内 mobile/、第三方声明和固定源码锁。主项目需准备固定 Git checkout 的"
        "upstream/rustdesk-1.5.0（含锁定 hbb_common）、锁定 Flutter3.24.5 Git SDK，"
        "现有 Python/Git/tar/7-Zip 与 Android SDK 的 build-tools36/API36/platform-tools/许可。"
        "依次运行 mobile/build-support/Prepare-BridgeTools.ps1、Generate-Bridge.ps1、"
        "Prepare-Android.ps1 和 Build-AndroidPreview.ps1 对应 Prepare/Generate/Build 动作；"
        "桥生成还需要该脚本已记录的本机 MSVC/UCRT 头文件。"
        "脚本要求主项目目录布局；源码 ZIP 中的 source/ 是此次已经应用修改的确切构建树，"
        "不是省略依赖后可脱网直接编译的单文件项目。依赖版本在 Cargo.lock/pubspec.lock/工具锁中。\n\n"
        "原生库此次未重新编译：从官方 RustDesk 1.5.0 通用 APK 的三个 ABI 中提取 "
        "librustdesk.so 和 libc++_shared.so；输入 APK SHA256 与每份库 SHA256 记录在 "
        "xixi-build-support/android-tools.lock.json 及 native-reuse.json，官方 APK 不被修改。"
        "源码 ZIP 不重复附带这六份原生二进制，Prepare 脚本会核验后提取。"
        "正式源码 native 构建应采用上游 Android workflow 的依赖和工具链。\n\n"
        "此次另附 assets/XIXI-DEFAULT-CONNECTION.json 的公开公网默认配置及 "
        "assets/XIXI-PREVIOUS-CONNECTION.json 的旧局域网配置；单配置只含 schemaVersion、"
        "ID/中转服务地址及服务器公钥，不含设备 ID、密码或私钥。首次安装及已知旧测试配置自动应用默认服务，"
        "自定义服务保留。另附 mobile/assets/XIXI-PREVIOUS-PUBLIC-CONNECTIONS.json 及同名 Flutter 资产，固定记录旧公网24443和443的完整身份。0.1.8 精准迁到 videopmt.com:24443/21117；所有旧 scopes 保留，沿原一次性 marker 链保留此前删除，目标同ID现名优先。重建前需准备 runtime/vps-public-profile.json 与 runtime/client-profile.json 的公开配置及包内固定公网历史资产，"
        "构建脚本会按严格白名单生成资产，不复制原 runtime 文件。\n\n"
        "本包只经过构建与静态包检查；手机安装、JNI/FFI 运行、远控、权限、后台、锁屏、"
        "重启及互联网场景仍须实际验证。\n"
    )
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(source.rglob("*")):
            if not path.is_file():
                continue
            relative = path.relative_to(source)
            if any(part in excluded_dirs for part in relative.parts) or path.name in excluded_names or path.suffix.lower() in excluded_suffixes:
                continue
            archive.write(path, "source/" + relative.as_posix())
        for path in sorted((project / "mobile/build-support").glob("*")):
            if path.is_file() and path.suffix in {".ps1", ".py", ".json", ".md"}:
                archive.write(path, "xixi-build-support/" + path.name)
        for filename in ("source.lock.json", "prepare-source.ps1"):
            archive.write(project / "mobile" / filename, "mobile/" + filename)
        for path in sorted((project / "mobile/lib").glob("*.dart")):
            archive.write(path, "mobile/lib/" + path.name)
        archive.write(project / "mobile/assets/xixi_launcher.xml", "mobile/assets/xixi_launcher.xml")
        archive.write(project / HISTORY_PROJECT_PATH, HISTORY_PROJECT_PATH)
        for name in ('XixiUnattended.kt', 'XixiRecoveryPolicy.kt'):
            archive.write(project / 'mobile/android' / name, 'mobile/android/' + name)
        for name in ('XixiRecoveryPolicyTest.kt', 'test_unattended_overlay.py'):
            archive.write(project / 'mobile/test-native' / name, 'mobile/test-native/' + name)
        archive.write(project / "THIRD-PARTY-NOTICES.md", "THIRD-PARTY-NOTICES.md")
        archive.write(project / "tools/mobile-build/native-reuse.json", "native-reuse.json")
        archive.write(project / "tools/mobile-build/preview-sources.json", "records/preview-sources.json")
        archive.write(project / "tools/bridge-prep/bridge-generation.json", "records/bridge-generation.json")
        archive.writestr("SOURCE-BUILD.md", notice)
    with zipfile.ZipFile(destination) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("Corresponding source archive failed CRC verification")


def verify(project, apk):
    cache = project / "tools/mobile-build"
    source = cache / "source"
    lock = json.loads((project / "mobile/build-support/android-tools.lock.json").read_text(encoding="utf-8-sig"))
    version_name, version_code = lock["previewVersionName"], lock["previewVersionCode"]
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+-preview", version_name) or type(version_code) is not int or not 0 < version_code <= 2100000000:
        raise RuntimeError("Invalid locked preview version")
    tools = json.loads((cache / "android-tools.json").read_text(encoding="utf-8-sig"))
    native = json.loads((cache / "native-reuse.json").read_text(encoding="utf-8-sig"))
    source_lock = json.loads((project / "mobile/source.lock.json").read_text(encoding="utf-8-sig"))
    expected_native = {(abi, filename) for abi in lock["nativeRust"] for filename in ("librustdesk.so", "libc++_shared.so")}
    actual_native = [(entry["abi"], entry["file"]) for entry in native["nativeFiles"]]
    if len(actual_native) != 6 or len(set(actual_native)) != 6 or set(actual_native) != expected_native:
        raise RuntimeError("Native reuse record must contain exactly six pinned ABI/library pairs")
    if native["apkSha256"] != lock["officialApk"]["sha256"] or native["sourceCommit"] != source_lock["upstream"]["commit"]:
        raise RuntimeError("Native reuse input APK/source record differs from pinned locks")
    if native.get("previewVersionName") != version_name or native.get("previewVersionCode") != version_code:
        raise RuntimeError("Native reuse staging record predates the current frontend version")
    frontend_record = json.loads((cache / "preview-sources.json").read_text(encoding="utf-8-sig"))
    if frontend_record["previewVersionName"] != version_name or frontend_record["previewVersionCode"] != version_code or frontend_record["sourceCommit"] != source_lock["upstream"]["commit"]:
        raise RuntimeError("Prepared frontend source record differs from current lock")
    expected_frontend = {"flutter/lib/mobile/pages/home_page.dart", "flutter/pubspec.lock", "flutter/pubspec.yaml", ASSET_SOURCE_PATH, PREVIOUS_SOURCE_PATH, HISTORY_SOURCE_PATH}
    expected_frontend.add("flutter/android/app/src/main/res/drawable/xixi_launcher.xml")
    expected_frontend.add('flutter/lib/models/server_model.dart')
    expected_frontend.update("flutter/lib/xixi/" + path.name for path in (project / "mobile/lib").glob("*.dart"))
    recorded_frontend = [entry["path"] for entry in frontend_record["frontendSources"]]
    kotlin_root = 'flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/'
    expected_overlay = {kotlin_root + name for name in ('XixiUnattended.kt', 'XixiRecoveryPolicy.kt',
        'MainService.kt', 'MainActivity.kt', 'InputService.kt', 'BootReceiver.kt')}
    expected_overlay.add('flutter/android/app/src/main/res/xml/accessibility_service_config.xml')
    expected_inputs = {'mobile/android/XixiUnattended.kt', 'mobile/android/XixiRecoveryPolicy.kt',
        'mobile/build-support/unattended_overlay.py', 'mobile/build-support/flutter_permission_overlay.py',
        'mobile/build-support/prepare_android_source.py'}
    for record_key, base, expected_paths in [('nativeOverlaySources', source, expected_overlay),
                                          ('nativeOverlayInputs', project, expected_inputs)]:
        records = frontend_record.get(record_key, [])
        paths = [entry['path'] for entry in records]
        if len(paths) != len(set(paths)) or set(paths) != expected_paths:
            raise RuntimeError('Unattended overlay source record is incomplete')
        for entry in records:
            path = base / entry['path']
            if not path.resolve().is_relative_to(base.resolve()) or digest(path.read_bytes()) != entry['sha256']:
                raise RuntimeError('Unattended source changed after staging: ' + entry['path'])
    if len(recorded_frontend) != len(set(recorded_frontend)) or set(recorded_frontend) != expected_frontend:
        raise RuntimeError("Prepared frontend source list differs from the current owned modules")
    for entry in frontend_record["frontendSources"]:
        path = source / entry["path"]
        if not path.resolve().is_relative_to(source.resolve()) or digest(path.read_bytes()) != entry["sha256"]:
            raise RuntimeError("Prepared frontend changed after staging: " + entry["path"])
        if entry["path"] == ASSET_SOURCE_PATH:
            if digest(current_profile_bytes(project)) != entry["sha256"]:
                raise RuntimeError("Current public test connection changed; rebuild before publishing")
            continue
        if entry["path"] == PREVIOUS_SOURCE_PATH:
            if digest(previous_profile_bytes(project)) != entry["sha256"]:
                raise RuntimeError("Previous public connection changed; rebuild before publishing")
            continue
        if entry["path"] == HISTORY_SOURCE_PATH:
            if digest(history_profile_bytes(project)) != entry["sha256"]:
                raise RuntimeError("Reviewed historical public connections changed; rebuild before publishing")
            continue
        if entry['path'] == 'flutter/lib/models/server_model.dart':
            original = project / 'upstream/rustdesk-1.5.0' / entry['path']
            replayed = transform_server_model(original.read_text(encoding='utf-8'), replace_once)
            if digest(replayed.encode('utf-8')) != entry['sha256']:
                raise RuntimeError('Permission model differs from reproducible pinned overlay')
            continue
        if entry["path"].startswith("flutter/lib/xixi/"):
            original = project / "mobile/lib" / path.name
        elif entry["path"] == "flutter/android/app/src/main/res/drawable/xixi_launcher.xml":
            original = project / "mobile/assets/xixi_launcher.xml"
        else:
            original = project / "upstream/rustdesk-1.5.0" / entry["path"]
        if digest(original.read_bytes()) != entry["sha256"]:
            raise RuntimeError("Current frontend changed after staging; rebuild before publishing: " + entry["path"])
    official = project / lock["officialApk"]["path"]
    if digest(official.read_bytes()) != lock["officialApk"]["sha256"]:
        raise RuntimeError("Official input APK identity changed")
    sdk_relative = pathlib.Path(tools["sdkRoot"]).resolve().relative_to(project.resolve())
    build_tools = project / sdk_relative / "build-tools/36.0.0"
    badging = command([build_tools / "aapt.exe", "dump", "badging", apk])
    if "package: name='com.xixi.remote.preview'" not in badging or f"versionName='{version_name}'" not in badging or f"versionCode='{version_code}'" not in badging:
        raise RuntimeError("APK applicationId or version differs from preview contract")
    if "application-label:'西西远程'" not in badging or "sdkVersion:'22'" not in badging or "targetSdkVersion:'36'" not in badging:
        raise RuntimeError("APK label or SDK limits differ from preview contract")
    manifest = command([build_tools / "aapt.exe", "dump", "xmltree", apk, "AndroidManifest.xml"])
    if "com.carriez.flutter_hbb.MainActivity" not in manifest or '"rustdesk"' in manifest:
        raise RuntimeError("Preview manifest component/deep-link coexistence check failed")
    resource_dump = command([build_tools / "aapt.exe", "dump", "--values", "resources", apk])
    screenshot_paths = set(re.findall(
        r'com\.xixi\.remote\.preview:xml/accessibility_service_config:[^\n]*\n\s*\(string(?:8|16)\) "(res/[^"\r\n]+\.xml)"',
        resource_dump))
    if len(screenshot_paths) != 1:
        raise RuntimeError('Compiled accessibility metadata is absent or ambiguous')
    screenshot_xml = command([build_tools / 'aapt.exe', 'dump', 'xmltree', apk, screenshot_paths.pop()])
    if not re.search(r'android:canTakeScreenshot\([^)]*\)=\(type 0x12\)0xffffffff', screenshot_xml):
        raise RuntimeError('Compiled accessibility screenshot capability is not enabled')
    launcher_ids = set(re.findall(r"spec resource (0x[0-9a-f]+) com\.xixi\.remote\.preview:drawable/xixi_launcher:", resource_dump))
    if len(launcher_ids) != 1:
        raise RuntimeError("Compiled own launcher vector resource is absent or ambiguous")
    launcher_id = launcher_ids.pop()
    manifest_lines = manifest.splitlines()
    application_lines = [i for i, line in enumerate(manifest_lines) if re.fullmatch(r"\s*E: application \(line=[0-9]+\)", line)]
    if len(application_lines) != 1:
        raise RuntimeError("Expected exactly one compiled application element")
    application_index = application_lines[0]
    application_indent = len(manifest_lines[application_index]) - len(manifest_lines[application_index].lstrip())
    application_attrs = []
    for line in manifest_lines[application_index + 1:]:
        if not line.startswith(" " * (application_indent + 2) + "A: "):
            break
        application_attrs.append(line)
    application_attrs = "\n".join(application_attrs)
    for attribute in ("icon", "roundIcon"):
        references = re.findall(r"android:" + attribute + r"\([^)]*\)=@(0x[0-9a-f]+)\b", application_attrs)
        if references != [launcher_id]:
            raise RuntimeError("Compiled application launcher icon does not resolve to our vector: " + attribute)
    # AGP resource optimization shortens ZIP paths (for example res/wp.xml).
    # Resolve the actual packaged file from the verified named resource ID.
    launcher_paths = set(re.findall(r"^\s*resource " + re.escape(launcher_id)
                                   + r" com\.xixi\.remote\.preview:drawable/xixi_launcher:[^\n]*\n\s*\(string(?:8|16)\) \"(res/[^\"\r\n]+\.xml)\"", resource_dump, re.MULTILINE))
    if len(launcher_paths) != 1:
        raise RuntimeError("Own launcher vector ZIP path is absent or ambiguous")
    launcher_path = launcher_paths.pop()
    reported_icons = set(re.findall(r"^application-icon-[0-9]+:'([^']+)'$", badging, re.MULTILINE))
    if reported_icons != {launcher_path}:
        raise RuntimeError("Application badging icons differ from the named launcher vector")
    compiled_launcher = command([build_tools / "aapt.exe", "dump", "xmltree", apk, launcher_path])
    if not re.search(r"^\s*E: vector \(line=[0-9]+\)$", compiled_launcher, re.MULTILINE):
        raise RuntimeError("Own launcher resource is not a compiled Android vector")
    signed = command([build_tools / "apksigner.bat", "verify", "--verbose", "--print-certs", apk])
    if "Verified using v2 scheme (APK Signature Scheme v2): true" not in signed:
        raise RuntimeError("Expected verified APK v2 signature")
    if "Verified using v1 scheme (JAR signing): true" not in signed:
        raise RuntimeError("Expected verified APK v1 signature for minSdk22 compatibility")
    classes = set()
    dex_payloads = []
    app_libraries = []
    with zipfile.ZipFile(apk) as preview, zipfile.ZipFile(official) as original:
        if preview.testzip() is not None:
            raise RuntimeError("APK failed CRC verification")
        for entry in native["nativeFiles"]:
            if entry["file"] == "librustdesk.so" and entry["sha256"] != lock["nativeRust"][entry["abi"]]:
                raise RuntimeError("Native Rust library record differs from its fixed ABI hash")
            name = f"lib/{entry['abi']}/{entry['file']}"
            data = preview.read(name)
            if len(data) != entry["bytes"] or digest(data) != entry["sha256"] or data != original.read(name):
                raise RuntimeError("Reused native binary changed: " + name)
        for abi in lock["nativeRust"]:
            name = f"lib/{abi}/libapp.so"
            data = preview.read(name)
            if not data.startswith(b"\x7fELF") or data == original.read(name):
                raise RuntimeError("Own Flutter AOT was not produced: " + abi)
            machine = struct.unpack_from("<H", data, 18)[0]
            if machine != {"arm64-v8a": 183, "armeabi-v7a": 40, "x86_64": 62}[abi]:
                raise RuntimeError("Flutter AOT ELF machine differs from its ABI: " + abi)
            if not preview.read(f"lib/{abi}/libflutter.so").startswith(b"\x7fELF"):
                raise RuntimeError("Flutter engine payload absent: " + abi)
            app_libraries.append({"abi": abi, "bytes": len(data), "elfMachine": machine, "sha256": digest(data)})
        for name in preview.namelist():
            if re.fullmatch(r"classes(?:\d+)?\.dex", name):
                payload = preview.read(name)
                classes.update(dex_classes(payload))
                dex_payloads.append(payload)
        for method in (b'xixi_unattended_state', b'xixi_enable_unattended', b'xixi_retry_unattended', b'takeScreenshot',
                       b'accessibilityEnabled', b'accessibilityConnected', b'accessibilityStatusKnown',
                       b'recoveryTimedOut'):
            if not any(method in payload for payload in dex_payloads):
                raise RuntimeError('Compiled unattended channel/API is absent')
        if "Lffi/FFI;" not in classes or not any(name.startswith("Lorg/rustls/platformverifier/") for name in classes):
            raise RuntimeError("JNI FFI or Rustls verifier classes absent from DEX definitions")
        policy_class = 'Lcom/carriez/flutter_hbb/XixiRecoveryPolicy;'
        mapping_path = source / 'flutter/build/app/outputs/mapping/release/mapping.txt'
        mapping_sha = None
        if policy_class not in classes:
            mapping_bytes = mapping_path.read_bytes()
            mapping_sha = digest(mapping_bytes)
            mapped = re.findall(r'^com\.carriez\.flutter_hbb\.XixiRecoveryPolicy -> ([A-Za-z0-9_.$]+):$',
                                mapping_bytes.decode('utf-8').replace('\r\n', '\n'), re.MULTILINE)
            if len(mapped) != 1:
                raise RuntimeError('Recovery policy R8 mapping is absent or ambiguous')
            policy_class = 'L' + mapped[0].replace('.', '/') + ';'
            if policy_class not in classes:
                raise RuntimeError('Compiled recovery policy is absent from actual DEX definitions')
        license_assets = ["assets/flutter_assets/assets/" + name for name in ("XIXI-LICENSE.txt", "XIXI-THIRD-PARTY-NOTICES.txt", "XIXI-SOURCE.txt")]
        launcher = {"resourceId": launcher_id, "path": launcher_path, "compiledSha256": digest(preview.read(launcher_path))}
        for name in license_assets:
            asset_name = pathlib.PurePosixPath(name).name
            if not preview.read(name).strip() or preview.read(name) != (source / "flutter/assets" / asset_name).read_bytes():
                raise RuntimeError("License/source asset absent: " + name)
        test_connection_bytes = preview.read(ASSET_APK_PATH)
        if test_connection_bytes != (source / ASSET_SOURCE_PATH).read_bytes() or test_connection_bytes != current_profile_bytes(project):
            raise RuntimeError("Public test connection asset differs from the current strict projection")
        test_connection_asset = {"apkPath": ASSET_APK_PATH, "sourcePath": ASSET_SOURCE_PATH,
                                 "bytes": len(test_connection_bytes), "sha256": digest(test_connection_bytes),
                                 "fieldNames": list(PUBLIC_FIELDS), "appliesAutomatically": True,
                                 "migration": "Empty options, recognized previous LAN, or complete reviewed old public 24443/443 identity migrate to approved domain; custom/API preserved; old scopes and deletion-respecting migration markers retained"}
        previous_bytes = preview.read(PREVIOUS_APK_PATH)
        if previous_bytes != (source / PREVIOUS_SOURCE_PATH).read_bytes() or previous_bytes != previous_profile_bytes(project):
            raise RuntimeError("Previous connection asset differs from strict public projection")
        previous_asset = {"apkPath": PREVIOUS_APK_PATH, "sourcePath": PREVIOUS_SOURCE_PATH,
                          "bytes": len(previous_bytes), "sha256": digest(previous_bytes), "fieldNames": list(PUBLIC_FIELDS)}
        historical_bytes = preview.read(HISTORY_APK_PATH)
        if historical_bytes != (source / HISTORY_SOURCE_PATH).read_bytes() or historical_bytes != history_profile_bytes(project):
            raise RuntimeError("Historical public connections asset differs from reviewed identities")
        historical_asset = {"apkPath": HISTORY_APK_PATH, "sourcePath": HISTORY_SOURCE_PATH,
                            "bytes": len(historical_bytes), "sha256": digest(historical_bytes),
                            "fieldNames": ["schemaVersion", "profiles"], "profileCount": 2}
    source_zip = cache / "xixi-remote-preview-source.zip"
    source_bundle(project, source, source_zip)
    checked_sources = [source / "flutter/lib/mobile/pages/home_page.dart", source / "flutter/pubspec.lock", source / "flutter/pubspec.yaml", source / ASSET_SOURCE_PATH, source / PREVIOUS_SOURCE_PATH, source / HISTORY_SOURCE_PATH,
                       source / "flutter/android/app/build.gradle", source / "flutter/android/build.gradle", source / "flutter/android/settings.gradle", source / "flutter/android/gradle.properties",
                       source / "flutter/android/app/src/main/AndroidManifest.xml",
                       source / "flutter/android/app/src/main/res/drawable/xixi_launcher.xml"]
    checked_sources.extend(source / "flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb" / name
                           for name in ('XixiUnattended.kt', 'XixiRecoveryPolicy.kt', 'MainService.kt',
                                        'MainActivity.kt', 'InputService.kt', 'BootReceiver.kt', 'FloatingWindowService.kt'))
    checked_sources.append(source / 'flutter/lib/models/server_model.dart')
    checked_sources.extend(sorted((source / "flutter/lib/xixi").glob("*.dart")))
    record = {
        "applicationId": lock["applicationId"], "label": "西西远程", "versionName": version_name, "versionCode": version_code, "minSdk": 22, "targetSdk": 36,
        "apkSha256": digest(apk.read_bytes()), "apkBytes": apk.stat().st_size,
        "sourceZipSha256": digest(source_zip.read_bytes()), "sourceZipBytes": source_zip.stat().st_size,
        "nativeReuse": native["nativeFiles"], "ownFlutterAot": app_libraries, "dexClassCount": len(classes),
        "signatureVerification": signed, "licenseAssets": license_assets,
        "launcherIcon": launcher,
        "publicTestConnectionAsset": test_connection_asset,
        "previousConnectionAsset": previous_asset,
        "previousPublicConnectionsAsset": historical_asset,
        "sourceFiles": [{"path": path.relative_to(source).as_posix(), "sha256": digest(path.read_bytes())} for path in checked_sources],
        "officialApkUnchanged": True, "installed": False, "jniRuntimeVerified": False, "remoteSessionVerified": False,
        "unattendedBackend": {"api": "AccessibilityService.takeScreenshot", "minimumAndroidApi": 30,
            "compiledCapabilityVerified": True, "compiledChannelVerified": True,
            'systemPermissionSeparatedFromBinding': True, 'boundedRecoveryWaitMs': 15000,
            'savedHostRestoredOnForeground': True, 'explicitUserStopPreserved': True,
            'explicitRetryDoesNotExtendAutomaticWait': True, 'temporaryCaptureDemandNotPersisted': True,
            'recoveryPolicyDexClass': policy_class, 'r8MappingSha256': mapping_sha,
            "nativeOverlaySources": frontend_record['nativeOverlaySources'], "deviceVerified": False},
    }
    (cache / "preview-verification.json").write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
    print("APK signature/manifest/ZIP/native/AOT/DEX/license checks passed. Corresponding source ZIP created; no device install was run.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=pathlib.Path, required=True)
    parser.add_argument("--apk", type=pathlib.Path, required=True)
    args = parser.parse_args()
    project = args.project.absolute()
    apk = args.apk.absolute()
    expected = [project / "tools/mobile-build/source/flutter/build/app/outputs" / path for path in ("flutter-apk/app-release.apk", "apk/release/app-release.apk")]
    if apk.resolve() not in {path.resolve() for path in expected}:
        raise RuntimeError("Only the owned project preview APK output may be verified")
    verify(project, apk)
