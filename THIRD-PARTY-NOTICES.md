# 第三方来源与许可

西西远程（CC Remote）提供自己的 Windows 与 Android 界面、设备管理及产品
集成，并在产品包内使用 RustDesk 的原生远程控制组件。

## RustDesk

- 上游项目：https://github.com/rustdesk/rustdesk
- 上游版本：1.5.0
- 主源码提交：`fada664df7a294d1d1a9ca3e7cd3637069122f17`
- `hbb_common` 提交：`229b904508364c8997aad0fb5af57effac859f60`
- 主要许可：GNU Affero General Public License, version 3；全文见 [LICENSE](LICENSE)。

Windows 客户端重新编译了自己的 Flutter 应用与 Windows 入口，内置固定的上游
原生 DLL；Android 客户端重新编译了 Flutter 和 Kotlin/Java 应用，复用经过校验的
Rust/C++ 原生库。安装西西远程无需另外安装官方 RustDesk 客户端。

两端完整对应源码、生成桥、来源记录及集成修改在 [版本快照](SOURCE.md)中提供。
各依赖、平台文件和资源保留原有的版权及许可声明；它们各自的许可仍适用。
Flutter、通用 SDK 和构建工具不作为独立产品随本仓库分发。

## 连接与中转服务

预览服务使用 [RustDesk Server OSS](https://github.com/rustdesk/rustdesk-server)
1.1.16。服务器开源代码与许可见上游对应版本。产品源码中只保留已打包的公开
连接配置；实际服务器私钥、数据库、密码和日志不在此仓库。

## 品牌资源

`assets/brand/` 中的西西远程图标为本项目原创矢量设计。网站使用的 GitHub
标识来自 [GitHub Octicons](https://github.com/primer/octicons)，按 MIT 许可使用；
归属和许可正文保留在网站对应源码中。
