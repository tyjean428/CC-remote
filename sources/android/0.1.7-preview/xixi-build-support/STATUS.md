# Android 构建准备记录

## 已完成的真实桥生成

2026-10-03 已在这台 Windows 上实际生成并发布六个桥文件，使用 RustDesk 固定提交 `fada664df7a294d1d1a9ca3e7cd3637069122f17` 与 hbb_common `229b904508364c8997aad0fb5af57effac859f60`。没有手写替代接口或采用其它 RustDesk commit 的生成产物。

生成工具为项目内 Rust 1.75.0、Flutter 3.22.3 / Dart 3.4.4、官方 FRB codegen 1.80.1（默认包含 UUID）、libclang 14.0.6。官方 bridge workflow 安装 cargo-expand 1.0.95，但这个版本的 FRB 源码实际调用 cargo metadata 与 syn 源码解析，不调用 cargo-expand；本路线因此没有编译这项无用工具，也没有编译远控原生库。

`Prepare-BridgeTools.ps1` 默认只打印下载计划；Prepare 下载并校验后仅在 `tools/bridge-prep/` 解包。固定工具压缩包合计 599,328,117 字节，另有 Flutter 源码、工具和 Pub/Cargo 依赖缓存。Rust 组件依据官方 channel manifest 的 SHA256，FRB 依据官方 release 的 SHA256 校验。旧 LLVM 资产及 Dart 对象没有找到官方 SHA256，采用官方响应/对象元数据的 MD5 校验，同时记录本地 SHA256，不把本地计算值称为官方发布校验值。LLVM 安装器没有执行，仅用现有 7-Zip 提取 libclang 和头文件。

`Generate-Bridge.ps1` 默认 Plan；Generate 从 Git 固定提交建立独立源码副本，按官方 workflow 仅在副本中将 extended_text 14.0.0 调为 13.0.0。Windows 的 Flutter pub get 插件后处理会要求 Developer Mode；桥生成采用明确 FLUTTER_ROOT 的 dart pub get 解析同样的依赖，避免改 Windows 设置。libclang 标准头文件路径显式使用项目 LLVM 与本机已安装的 MSVC/UCRT，不安装系统组件。

当前完整生成日志没有 ffigen 的 SEVERE/fatal header 诊断；两份生成 Dart 文件的实际静态分析结果为 `No issues found`。脚本在严重头文件诊断、分析失败或生成文件为空时拒绝发布；只允许发布六个桥文件，既有文件若不是本脚本前次产物且 SHA 一致，则拒绝覆盖。

| 发布文件 | 字节数 |
| --- | ---: |
| src/bridge_generated.rs | 164380 |
| src/bridge_generated.io.rs | 59154 |
| flutter/lib/generated_bridge.dart | 448995 |
| flutter/lib/generated_bridge.freezed.dart | 23588 |
| flutter/macos/Runner/bridge_generated.h | 62541 |
| flutter/ios/Runner/bridge_generated.h | 62541 |

完整产物 SHA256、源码/工作流/依赖锁文件 SHA、工具版本和头文件路径见 `tools/bridge-prep/bridge-generation.json`；下载校验见 `tools/bridge-prep/verified-downloads.json`。上游 Cargo.lock 没有改变。两个 PowerShell 脚本通过 Windows PowerShell 5.1 和 PowerShell 7 parser；真实生成是在 PowerShell 7 上完成，不能把语法检查称为 PowerShell 5.1 下整条生成流程的运行验证。

```powershell
# 在项目根目录；Generate 成功后仅发布六个生成文件。
./mobile/build-support/Prepare-BridgeTools.ps1 -Action Plan
./mobile/build-support/Prepare-BridgeTools.ps1 -Action Prepare
./mobile/build-support/Generate-Bridge.ps1 -Action Plan
./mobile/build-support/Generate-Bridge.ps1 -Action Generate -Publish
```

缓存、Cargo/Pub homes、临时目录、Flutter/Dart profile 以及 PATH 都通过构建进程设置，结束后恢复。没有调用 rustup、改全局 PATH/代理、安装 APK、接触 ADB 或启停远控服务。首次旧脚本初始化 Flutter 时更新了用户 APPDATA 中的 `.flutter_tool_state`；后续脚本已隔离 APPDATA/LOCALAPPDATA/USERPROFILE 到项目缓存，不删除或覆盖用户已有配置。

## 复用原生库的静态边界

对原封不动的官方 `tools/android/rustdesk.apk` 做 ZIP/ELF 静态检查：新生成 C header 的 315 个 wire 函数名，与 arm64-v8a、armeabi-v7a、x86_64 三份 librustdesk.so 的 315 个 wire 导出名逐一一致，没有缺少或额外项。这项检查证明符号名称匹配，不证明参数布局、签名、运行兼容或实际连接成功。

JNI 固定类为 `ffi.FFI`，服务回调方法名/签名也需要保持。新包可使用独立 applicationId，并保留内部 Kotlin namespace；必须重新构建自身 Flutter AOT/Kotlin/UI，不能复制原 APK 的 libapp.so 来宣称更换了界面。完整 Android 构建仍需处理 Rustls Android AAR、protobuf、Flutter 插件、Android SDK、独立应用标识、签名和许可。

## 当前 Android 预览构建

当前锁为 0.1.7-preview / versionCode 8，默认 ID 服务使用独立 24443（NAT 24442）、中转 21117，443 留给网站。已知旧内置 443 配置精准迁移，自定义配置保留；旧端口设备列表保留原源并一次合并，目标同 ID 优先且删除不复活。51 项测试通过；本版 APK 的实际签名、版本、源码和 SHA 校验，以 tools/mobile-build/preview-verification.json 精确匹配该版本为准。

0.1.3-preview 已完成实际编译、打包和 Verify，用户报告手机可以查看电脑画面。输入、流量网络、反向连接和后台行为仍待实机确认。先前 0.1.2 的 packageRelease 失败原因未定位；0.1.3 的失败 stacktrace 明确为 Java heap space，3072 MB 堆和两个 workers 的打包重试成功，该配置已写入源码生成器供后续构建使用。

自己的银白钴蓝九模块 UI、三架构 Flutter AOT 与 Kotlin/Java 重新构建，复用六份未修改官方 Rust/C++ 库。应用 ID com.xixi.remote.preview，内部 namespace com.carriez.flutter_hbb、JNI ffi.FFI 保留；minSdk22、targetSdk36。Manifest 图标引用、编译 vector、DEX 类、六份 native 字节、AOT 架构、预览证书 v1/v2 签名、源码一致性和许可资产均由 Verify 检查。源码 ZIP 排除签名材料、设备密码及运行私钥。

内置公开服务及旧局域网识别资产见 PUBLIC-TEST-CONNECTION.md。空白或已识别旧配置自动迁移，自定义服务保留；配置保存须回读确认，不表示远控会话通过。屏幕采集、输入和接入授权仍由系统与原服务流程执行。

Build-AndroidPreview.ps1 默认 Plan，Build 实际编译并校验，Diagnose 仅对当前受控 staging 作有限打包诊断，Verify 核对当前 APK 再复制。固定依赖、桥生成、源码和环境隔离流程保留，不修改系统代理或全局 PATH，不通过 ADB 安装。
0.1.7 的首轮 21116 目标构建因最终独立端口改为 24443 而主动停止，未发布。日志 tools/mobile-build/apk-build-0.1.7-interrupted-21116.log 保留；最终产物只接受当前 24443 默认资产与共享公开 profile 一致的 Verify。
