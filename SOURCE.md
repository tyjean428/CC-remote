# 对应版本源码

本仓库为西西远程提供产品介绍和发布版本的完整源码快照。Windows 与 Android
使用各自的工程快照，保留两端实际发布时的界面、平台代码、生成桥、Rust 原生
源码、依赖锁、构建工具及原有许可声明。

| 平台 | 安装包版本 | 完整源码 |
| --- | --- | --- |
| Windows | 0.5.2-preview | [Windows 快照](sources/windows/0.5.2-preview/) |
| Android | 0.1.6-preview | [Android 快照](sources/android/0.1.6-preview/) |

进入对应目录，先阅读 `README.md` 和 `manifest.json`。清单标明安装包 SHA256、
源码来源及文件校验记录，构建说明与脚本保存在各自快照内。使用 GitHub 的
“Code → Download ZIP”可以取得整个仓库，也可以通过 Git 克隆。

快照内保留发布时使用的公开连接配置；签名私钥、访问密码、服务器私钥、设备
数据库、运行日志和开发工具缓存不属于公开发布内容。你应使用自己的签名证书。

公开导出只整理非运行的测试样例、工具路径和机器生成记录；实际应用代码、
平台实现、桥、依赖锁和公开配置保持发布版本的字节。导出说明见各快照清单。
原始本地源包与公开导出包分别记录校验值，不将两者混为同一个归档。

远控引擎基于 RustDesk 1.5.0：

- 主源码固定提交：`fada664df7a294d1d1a9ca3e7cd3637069122f17`
- `hbb_common` 固定提交：`229b904508364c8997aad0fb5af57effac859f60`
- 许可与来源：[LICENSE](LICENSE)、[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)

安装包与源码的提供不代表所有设备和连接方向已完成验收。实际使用范围与预览
说明见 [产品首页](README.md)。
