"""Create only a project-local preview source overlay and verified JNI payloads."""
import argparse
import hashlib
import json
import pathlib
import re
import shutil
import struct
import xml.etree.ElementTree as ET
import zipfile
from unattended_overlay import apply_unattended
from flutter_permission_overlay import apply_flutter_permissions

from public_test_connection import ASSET_SOURCE_PATH, PREVIOUS_SOURCE_PATH, HISTORY_SOURCE_PATH, current_profile_bytes, previous_profile_bytes, history_profile_bytes

ANDROID = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", ANDROID)
ET.register_namespace("tools", "http://schemas.android.com/tools")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def replace_once(text, old, new, description):
    if text.count(old) != 1:
        raise RuntimeError(f"Unexpected source anchor: {description}")
    return text.replace(old, new, 1)


def exports(data):
    if data[:4] != b"\x7fELF":
        raise RuntimeError("Native payload is not ELF")
    wide = data[4] == 2
    endian = "<" if data[5] == 1 else ">"
    header = struct.unpack_from(endian + ("HHIQQQIHHHHHH" if wide else "HHIIIIIHHHHHH"), data, 16)
    section_format = endian + ("IIQQQQIIQQ" if wide else "IIIIIIIIII")
    sections = [struct.unpack_from(section_format, data, header[5] + i * header[10]) for i in range(header[11])]
    names = set()
    for section in sections:
        if section[1] != 11:
            continue
        strings_section = sections[section[6]]
        strings = data[strings_section[4]: strings_section[4] + strings_section[5]]
        for offset in range(section[4], section[4] + section[5], section[9]):
            symbol = struct.unpack_from(endian + ("IBBHQQ" if wide else "IIIBBH"), data, offset)
            if symbol[3 if wide else 5] == 0:
                continue
            end = strings.find(b"\0", symbol[0])
            names.add(strings[symbol[0]:end].decode("utf-8", "strict"))
    return names


def prepare(project, source, cache):
    lock = json.loads((project / "mobile/build-support/android-tools.lock.json").read_text(encoding="utf-8-sig"))
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+-preview", lock["previewVersionName"]) or type(lock["previewVersionCode"]) is not int or not 0 < lock["previewVersionCode"] <= 2100000000:
        raise RuntimeError("Invalid locked Android preview name/code")
    source_lock = json.loads((project / "mobile/source.lock.json").read_text(encoding="utf-8-sig"))
    bridge = json.loads((project / "tools/bridge-prep/bridge-generation.json").read_text(encoding="utf-8-sig"))
    if bridge["sourceCommit"] != source_lock["upstream"]["commit"] or not bridge["published"]:
        raise RuntimeError("Bridge generation is not verified for our source")
    upstream = project / "upstream/rustdesk-1.5.0"
    for artifact in bridge["artifacts"]:
        original = upstream / artifact["path"]
        if sha(original) != artifact["sha256"]:
            raise RuntimeError("Published bridge was modified: " + artifact["path"])
        target = source / artifact["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, target)
    mobile_root = project / "mobile/lib"
    mobile_files = sorted(mobile_root.glob("*.dart"))
    if not mobile_files:
        raise RuntimeError("No top-level owned mobile Dart modules found")
    overlay = source / "flutter/lib/xixi"
    overlay.mkdir(parents=True, exist_ok=True)
    for original in mobile_files:
        if not re.fullmatch(r"[a-z0-9_]+\.dart", original.name) or original.is_symlink() or original.resolve().parent != mobile_root.resolve():
            raise RuntimeError("Mobile overlay must be a top-level owned Dart file: " + original.name)
        shutil.copy2(original, overlay / original.name)
    shutil.copy2(upstream / "flutter/lib/mobile/pages/home_page.dart", source / "flutter/lib/mobile/pages/home_page.dart")
    shutil.copy2(upstream / "flutter/pubspec.lock", source / "flutter/pubspec.lock")
    apk = project / lock["officialApk"]["path"]
    if apk.stat().st_size != lock["officialApk"]["bytes"] or sha(apk) != lock["officialApk"]["sha256"]:
        raise RuntimeError("Official APK identity differs from pinned verification")
    header = (source / "flutter/macos/Runner/bridge_generated.h").read_text(encoding="utf-8")
    expected = set(re.findall(r"\b(wire_[A-Za-z0-9_]+)\s*\(", header))
    native_records = []
    with zipfile.ZipFile(apk) as archive:
        for abi, rust_hash in lock["nativeRust"].items():
            rust_bytes = archive.read(f"lib/{abi}/librustdesk.so")
            if hashlib.sha256(rust_bytes).hexdigest() != rust_hash:
                raise RuntimeError("Native Rust digest differs: " + abi)
            symbols = exports(rust_bytes)
            wires = {name for name in symbols if name.startswith("wire_")}
            if expected != wires or "Java_ffi_FFI_init" not in symbols:
                raise RuntimeError("JNI/wire export contract differs: " + abi)
            for filename in ("librustdesk.so", "libc++_shared.so"):
                data = archive.read(f"lib/{abi}/{filename}")
                destination = source / "flutter/android/app/src/main/jniLibs" / abi / filename
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(data)
                native_records.append({"abi": abi, "file": filename, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    if sha(apk) != lock["officialApk"]["sha256"]:
        raise RuntimeError("Official APK changed during preparation")

    gradle_path = source / "flutter/android/app/build.gradle"
    gradle = gradle_path.read_text(encoding="utf-8")
    gradle = replace_once(gradle, 'applicationId "com.carriez.flutter_hbb"', 'applicationId "com.xixi.remote.preview"', "applicationId")
    verifier = list((project / "tools/bridge-prep/cargo-home/registry/src").glob("*/rustls-platform-verifier-android-0.1.1/maven"))
    if len(verifier) != 1:
        raise RuntimeError("Expected exactly one cached rustls-platform-verifier Android 0.1.1 Maven repository")
    local_maven = cache / "rustls-maven"
    shutil.copytree(verifier[0], local_maven, dirs_exist_ok=True)
    old_start = gradle.index("String findRustlsPlatformVerifierMavenDir() {")
    old_end = gradle.index("\n\nrepositories {", old_start)
    gradle = gradle[:old_start] + "String findRustlsPlatformVerifierMavenDir() {\n    return System.getenv('XIXI_RUSTLS_MAVEN')\n}\n" + gradle[old_end:]
    gradle = replace_once(gradle, 'compileSdkVersion 36', 'compileSdkVersion 36\n    buildToolsVersion "36.0.0"\n    packagingOptions { jniLibs { keepDebugSymbols += ["**/*.so"] } }', "SDK/native preservation")
    signing = """    signingConfigs {
      xixiPreview {
        storeFile file(System.getenv('XIXI_PREVIEW_KEYSTORE'))
        storePassword System.getenv('XIXI_PREVIEW_STORE_PASSWORD')
        keyAlias 'xixi_preview'
        keyPassword System.getenv('XIXI_PREVIEW_STORE_PASSWORD')
      }
"""
    gradle = replace_once(gradle, "    signingConfigs {\n", signing, "isolated preview signing")
    gradle = replace_once(gradle, "signingConfig signingConfigs.release", "signingConfig signingConfigs.xixiPreview", "release AOT preview signing")
    gradle_path.write_text(gradle, encoding="utf-8", newline="\n")
    settings_path = source / "flutter/android/settings.gradle"
    settings = settings_path.read_text(encoding="utf-8")
    settings = replace_once(settings, 'file("local.properties").withInputStream { properties.load(it) }',
                            'file("local.properties").withReader(\'UTF-8\') { properties.load(it) }\n        file("local.properties").withOutputStream { properties.store(it, null) }',
                            "UTF-8 SDK paths followed by standard Java properties escaping")
    settings_path.write_text(settings, encoding="utf-8", newline="\n")
    # Keep old plugins' API31/32/33/34 declarations: API36 adds nullability
    # annotations incompatible with some pinned plugin Kotlin source.
    root_gradle_path = source / "flutter/android/build.gradle"
    root_gradle = root_gradle_path.read_text(encoding="utf-8")
    root_gradle += """
// Project preview only: use the prepared build tools; preserve plugin API levels.
subprojects { previewProject ->
    previewProject.plugins.withId('com.android.library') {
        previewProject.androidComponents.finalizeDsl { libraryDsl ->
            libraryDsl.buildToolsVersion = '36.0.0'
        }
    }
}
"""
    root_gradle_path.write_text(root_gradle, encoding="utf-8", newline="\n")
    wrapper_path = source / "flutter/android/gradle/wrapper/gradle-wrapper.properties"
    wrapper = wrapper_path.read_text(encoding="utf-8")
    if "gradle-8.11.1-all.zip" not in wrapper:
        raise RuntimeError("Gradle wrapper distribution differs from the verified version")
    wrapper += "\ndistributionSha256Sum=" + lock["gradle"]["sha256"] + "\n"
    wrapper_path.write_text(wrapper, encoding="utf-8", newline="\n")

    manifest_path = source / "flutter/android/app/src/main/AndroidManifest.xml"
    tree = ET.parse(manifest_path)
    manifest = tree.getroot()
    manifest.attrib.pop("package", None)
    application = manifest.find("application")
    application.set(f"{{{ANDROID}}}label", "西西远程")
    launcher = project / "mobile/assets/xixi_launcher.xml"
    if launcher.is_symlink() or launcher.resolve().parent != (project / "mobile/assets").resolve():
        raise RuntimeError("Launcher asset must remain in the owned mobile/assets directory")
    launcher_tree = ET.parse(launcher)
    if launcher_tree.getroot().tag != "vector" or launcher.stat().st_size > 16384:
        raise RuntimeError("Expected a bounded Android vector launcher asset")
    launcher_target = source / "flutter/android/app/src/main/res/drawable/xixi_launcher.xml"
    launcher_target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(launcher, launcher_target)
    application.set(f"{{{ANDROID}}}icon", "@drawable/xixi_launcher")
    application.set(f"{{{ANDROID}}}roundIcon", "@drawable/xixi_launcher")
    for node in application.iter():
        name = node.get(f"{{{ANDROID}}}name", "")
        if name.startswith("."):
            node.set(f"{{{ANDROID}}}name", lock["kotlinNamespace"] + name)
        if node.tag == "service" and name == ".InputService":
            node.set(f"{{{ANDROID}}}label", "西西远程输入")
        for intent_filter in list(node.findall("intent-filter")):
            if any(data.get(f"{{{ANDROID}}}scheme") == "rustdesk" for data in intent_filter.findall("data")):
                node.remove(intent_filter)
            else:
                for action in list(intent_filter.findall("action")):
                    if action.get(f"{{{ANDROID}}}name") == "com.carriez.flutter_hbb.DEBUG_BOOT_COMPLETED":
                        intent_filter.remove(action)
    tree.write(manifest_path, encoding="utf-8", xml_declaration=True)
    for strings_path in (source / "flutter/android/app/src/main/res").glob("values*/strings.xml"):
        strings_tree = ET.parse(strings_path)
        for value in strings_tree.getroot().findall("string"):
            if value.get("name") == "app_name":
                value.text = "西西远程"
            elif value.get("name") in {"accessibility_service_description", "foreground_service_special_use_subtype"} and value.text:
                value.text = value.text.replace("RustDesk", "西西远程")
        strings_tree.write(strings_path, encoding="utf-8", xml_declaration=True)
    kotlin_root = source / "flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb"
    label_changes = {
        "MainService.kt": [('const val DEFAULT_NOTIFY_TITLE = "RustDesk"', 'const val DEFAULT_NOTIFY_TITLE = "西西远程"'),
                           ('val channelName = "RustDesk Service"', 'val channelName = "西西远程服务"'),
                           ('description = "RustDesk Service Channel"', 'description = "西西远程服务通知"')],
        "BootReceiver.kt": [('"RustDesk is Open"', '"西西远程已打开"')],
        "FloatingWindowService.kt": [('translate("Show RustDesk")', 'translate("Show RustDesk").replace("RustDesk", "西西远程")')],
    }
    for filename, changes in label_changes.items():
        label_path = kotlin_root / filename
        label_text = label_path.read_text(encoding="utf-8")
        for old, new in changes:
            label_text = replace_once(label_text, old, new, filename + " product label")
        label_path.write_text(label_text, encoding="utf-8", newline="\n")
    assets = source / "flutter/assets"
    gradle_properties = source / "flutter/android/gradle.properties"
    gradle_text = gradle_properties.read_text(encoding="utf-8")
    gradle_text = replace_once(gradle_text, "org.gradle.jvmargs=-Xmx1024M", "org.gradle.jvmargs=-Xmx4096M", "APK packaging heap")
    gradle_properties.write_text(gradle_text + "\norg.gradle.workers.max=1\n", encoding="utf-8", newline="\n")
    if not re.search(r"^    - assets/\s*$", (source / "flutter/pubspec.yaml").read_text(encoding="utf-8"), re.MULTILINE):
        raise RuntimeError("Fixed Flutter pubspec must include the assets/ directory")
    test_connection = source / ASSET_SOURCE_PATH
    test_connection.write_bytes(current_profile_bytes(project))
    previous_connection = source / PREVIOUS_SOURCE_PATH
    previous_connection.write_bytes(previous_profile_bytes(project))
    historical_connection = source / HISTORY_SOURCE_PATH
    historical_connection.write_bytes(history_profile_bytes(project))
    shutil.copy2(source / "LICENCE", assets / "XIXI-LICENSE.txt")
    shutil.copy2(project / "THIRD-PARTY-NOTICES.md", assets / "XIXI-THIRD-PARTY-NOTICES.txt")
    source_notice = ("西西远程预览版使用 RustDesk 开源远控引擎，保留 AGPL-3.0。\n"
                     f"预览版本: {lock['previewVersionName']} / versionCode {lock['previewVersionCode']}。\n"
                     f"固定上游: https://github.com/rustdesk/rustdesk/tree/{source_lock['upstream']['commit']}\n"
                     "本预览版的对应修改源码随 APK 另提供。权限、后台、锁屏与无人值守须实际验证。\n")
    (assets / "XIXI-SOURCE.txt").write_text(source_notice, encoding="utf-8")
    frontend = [source / "flutter/lib/mobile/pages/home_page.dart", source / "flutter/pubspec.lock", source / "flutter/pubspec.yaml"]
    frontend.extend(overlay / original.name for original in mobile_files)
    frontend.append(launcher_target)
    frontend.append(test_connection)
    frontend.append(previous_connection)
    frontend.append(historical_connection)
    native_overlay = apply_unattended(project, source, replace_once)
    frontend.extend(apply_flutter_permissions(project, source, replace_once))
    native_inputs = [project / path for path in ('mobile/android/XixiUnattended.kt',
        'mobile/android/XixiRecoveryPolicy.kt', 'mobile/build-support/unattended_overlay.py',
        'mobile/build-support/flutter_permission_overlay.py', 'mobile/build-support/prepare_android_source.py')]
    (cache / "preview-sources.json").write_text(json.dumps({"previewVersionName": lock["previewVersionName"], "previewVersionCode": lock["previewVersionCode"], "sourceCommit": bridge["sourceCommit"], "frontendSources": [{"path": path.relative_to(source).as_posix(), "sha256": sha(path)} for path in frontend],
        "nativeOverlaySources": [{"path": path.relative_to(source).as_posix(), "sha256": sha(path)} for path in native_overlay],
        "nativeOverlayInputs": [{"path": path.relative_to(project).as_posix(), "sha256": sha(path)} for path in native_inputs]}, ensure_ascii=False, indent=2), encoding="utf-8")
    (cache / "native-reuse.json").write_text(json.dumps({"sourceCommit": bridge["sourceCommit"], "apkSha256": lock["officialApk"]["sha256"], "wireFunctions": len(expected), "jniClass": "ffi.FFI", "applicationId": lock["applicationId"], "namespace": lock["kotlinNamespace"], "previewVersionName": lock["previewVersionName"], "previewVersionCode": lock["previewVersionCode"], "nativeFiles": native_records, "runtimeVerified": False}, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=pathlib.Path, required=True)
    parser.add_argument("--source", type=pathlib.Path, required=True)
    args = parser.parse_args()
    project = args.project.resolve()
    cache = project / "tools/mobile-build"
    source = args.source.resolve()
    if source != (cache / "source").resolve():
        raise RuntimeError("Source must be the isolated project tools/mobile-build/source directory")
    prepare(project, source, cache)
    print("Prepared isolated preview source; only verified Rust/C++ shared libraries were reused.")
