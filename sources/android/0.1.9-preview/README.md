# XiXi Remote android 0.1.9-preview: corresponding source

This source snapshot corresponds to `XiXiRemote.apk` with SHA256 `ceb5b57220c6e4ad827176a2c002425ed319137c56a4e0b4d305d65870d249d1`. `source/` contains the complete patched RustDesk/hbb_common/application source and generated bridge for this exact platform version. Windows and Android snapshots are intentionally separate.

For reconstruction see `SOURCE-BUILD.md and xixi-build-support/`. The build-support files require the documented fixed project layout, pinned upstream checkout, toolchains, and unmodified official native-library input; this is not an offline SDK bundle. Generated iOS-only path state is omitted, and Python tooling is discovered from PATH. Existing public connection assets remain unchanged; prepare public build inputs as described by the included scripts, without copying real runtime identity, passwords, signing material or private keys.

See `PUBLICATION-NOTES.md` for the narrowly limited ancillary changes and `PUBLICATION-FILES.json` for per-file original/public SHA256. The program source, generated bridge, native source, dependency locks and compiled public assets remain byte-identical. The AGPL-3.0 text is in `source/LICENCE`; original and third-party notices are retained.
