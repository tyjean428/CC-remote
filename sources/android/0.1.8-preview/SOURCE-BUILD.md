# 西西远程 Android 预览版对应源码

预览版本：0.1.8-preview，versionCode 9。

该包包含此次预览 APK 实际构建的 RustDesk 固定源码、hbb_common、六份生成桥、西西移动界面模块和 Android 应用标识修改，保留 AGPL-3.0 与第三方声明。

这是 Flutter release AOT 配合项目预览证书签名的测试包；证书私钥和密码不随源码提供。不要把该签名用于正式发布。Android 可与官方 com.carriez.flutter_hbb 应用共存。

准备路径：把 xixi-build-support/ 内容放回主项目 mobile/build-support/，并保留包内 mobile/、第三方声明和固定源码锁。主项目需准备固定 Git checkout 的upstream/rustdesk-1.5.0（含锁定 hbb_common）、锁定 Flutter3.24.5 Git SDK，现有 Python/Git/tar/7-Zip 与 Android SDK 的 build-tools36/API34/platform-tools/许可。依次运行 mobile/build-support/Prepare-BridgeTools.ps1、Generate-Bridge.ps1、Prepare-Android.ps1 和 Build-AndroidPreview.ps1 对应 Prepare/Generate/Build 动作；桥生成还需要该脚本已记录的本机 MSVC/UCRT 头文件。脚本要求主项目目录布局；源码 ZIP 中的 source/ 是此次已经应用修改的确切构建树，不是省略依赖后可脱网直接编译的单文件项目。依赖版本在 Cargo.lock/pubspec.lock/工具锁中。

原生库此次未重新编译：从官方 RustDesk 1.5.0 通用 APK 的三个 ABI 中提取 librustdesk.so 和 libc++_shared.so；输入 APK SHA256 与每份库 SHA256 记录在 xixi-build-support/android-tools.lock.json 及 native-reuse.json，官方 APK 不被修改。源码 ZIP 不重复附带这六份原生二进制，Prepare 脚本会核验后提取。正式源码 native 构建应采用上游 Android workflow 的依赖和工具链。

此次另附 assets/XIXI-DEFAULT-CONNECTION.json 的公开公网默认配置及 assets/XIXI-PREVIOUS-CONNECTION.json 的旧局域网配置；单配置只含 schemaVersion、ID/中转服务地址及服务器公钥，不含设备 ID、密码或私钥。首次安装及已知旧测试配置自动应用默认服务，自定义服务保留。另附 mobile/assets/XIXI-PREVIOUS-PUBLIC-CONNECTIONS.json 及同名 Flutter 资产，固定记录旧公网24443和443的完整身份。0.1.8 精准迁到 videopmt.com:24443/21117；所有旧 scopes 保留，沿原一次性 marker 链保留此前删除，目标同ID现名优先。重建前需准备 runtime/vps-public-profile.json 与 runtime/client-profile.json 的公开配置及包内固定公网历史资产，构建脚本会按严格白名单生成资产，不复制原 runtime 文件。

本包只经过构建与静态包检查；手机安装、JNI/FFI 运行、远控、权限、后台、锁屏、重启及互联网场景仍须实际验证。
