# Third-party notices

The Windows control panel integrates unmodified upstream binaries as separate processes. The mobile module adds a Silver device-management home to pinned RustDesk Flutter source. The original upstream names and licenses are retained; neither UI implements or replaces the RustDesk remote desktop protocol.

## RustDesk Windows client

- Version: 1.5.0, Windows x64.
- Upstream: https://github.com/rustdesk/rustdesk
- Corresponding tagged source: https://github.com/rustdesk/rustdesk/tree/1.5.0
- License: AGPL-3.0, provided with the binary in `tools/rustdesk/LICENSE.txt`.
- The exact official asset URL and SHA256 are recorded in `dependencies.lock.json`.

## RustDesk Android client

- Version: 1.5.0, the official universal signed APK.
- Corresponding tagged source: https://github.com/rustdesk/rustdesk/tree/1.5.0
- License: AGPL-3.0; upstream license: https://raw.githubusercontent.com/rustdesk/rustdesk/1.5.0/LICENCE
- The official asset URL and SHA256 are recorded under `android` in `dependencies.lock.json`.
- The verified official APK in `tools/android/rustdesk.apk` remains unmodified. It is the native-library input for the separate XiXi Android preview build, as well as the original client used in earlier connection tests.
- The XiXi preview build compiles its own Flutter application and Android/Kotlin code from the pinned source and the modules in `mobile/`. It reuses only the verified upstream `librustdesk.so` and `libc++_shared.so` for three Android ABIs; the upstream Flutter application binary is not reused. The native-library provenance and hashes are recorded in the build's `native-reuse.json`.
- The preview uses application ID `com.xixi.remote.preview` and a separate preview signing certificate so it can coexist with the official application. Artifact verification records establish whether a particular build completed; compilation and static verification do not establish successful phone installation or remote-control operation.

## XiXi Flutter source overlay

- Corresponding RustDesk source is pinned to `fada664df7a294d1d1a9ca3e7cd3637069122f17` with `hbb_common` at `229b904508364c8997aad0fb5af57effac859f60` in `mobile/source.lock.json`.
- New mobile modules and the reproducible home-page integration script are supplied in `mobile/`. The AGPL-3.0 license text is retained in `mobile/LICENCE`.
- The existing upstream Flutter home entry is adapted; native capture, input, authentication and remote-session implementation are retained. The six bridge artifacts have been generated from the pinned source with flutter_rust_bridge 1.80.1, with provenance and hashes recorded in `tools/bridge-prep/bridge-generation.json`. Runtime compatibility still requires testing the independently built APK on a phone.
- The preview source archive includes the actual staged application source, generated bridge, XiXi overlay, dependency locks, build-support scripts, native-library provenance and license notices. Preview signing keys and passwords are excluded. The build scripts and verification records in `mobile/build-support/` describe the build rather than asserting that every local build has succeeded.
- Flutter 3.24.5 is a development dependency under `tools/flutter-sdk`, with its original BSD LICENSE retained; it is not shipped as a separate runtime payload by this project.

## RustDesk Server OSS

- Version: 1.1.16. Windows x64 archive and Linux amd64 archive are recorded separately; the official Windows archive is unsigned.
- Upstream: https://github.com/rustdesk/rustdesk-server
- Corresponding tagged source: https://github.com/rustdesk/rustdesk-server/tree/1.1.16
- License: AGPL-3.0, provided with the binaries in `tools/rustdesk-server/LICENSE.txt`.
- The official Windows archive URL and SHA256 are recorded under `server` in `dependencies.lock.json`; its extracted Windows binary hashes are recorded in `tools/verified-files.json`.
- The official Linux archive URL and SHA256 are recorded under `serverLinux` in `dependencies.lock.json`. `scripts/Get-WslDependencies.ps1` downloads or verifies the Linux archive without executing or extracting it.

## Alpine Linux WSL root filesystem

- Version: Alpine Linux 3.24.2, official x86_64 mini root filesystem.
- Official distribution download: https://alpinelinux.org/downloads/
- Official archive and SHA256 text: https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/x86_64/
- Corresponding package build recipes: https://gitlab.alpinelinux.org/alpine/aports/-/tree/3.24-stable
- Corresponding distribution package repository: https://dl-cdn.alpinelinux.org/alpine/v3.24/main/x86_64/
- Package metadata and license declarations: https://pkgs.alpinelinux.org/packages?branch=v3.24&arch=x86_64
- The distribution contains packages with their respective licenses; it is not described here as having one blanket package license. The rootfs URL and SHA256 are recorded under `alpineRootfs` in `dependencies.lock.json`.

These notices identify the upstream programs, distribution and corresponding sources. XiXi UI and tooling integrate the upstream core; they do not claim to have independently implemented it. The mobile home is modified through a source overlay; Rust protocol and native service sources are not changed by this UI work. Original license texts and package license declarations remain the references for their respective components.
