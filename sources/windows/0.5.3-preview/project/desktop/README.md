# 西西远程独立桌面客户端

本目录实现独立 Flutter Windows 产品及单一安装程序，替代 `client/` 中要求单独安装官方 RustDesk 服务的早期 WinForms 面板。用户安装西西远程后直接打开，输入对方 ID 发起连接，不需安装或打开另一款客户端。

自己的 Flutter AOT、Windows runner、导航、设备管理、共享与设置入口重新编译。原生远控引擎 DLL 作为包内组件复用固定官方 1.5.0 字节，不复用官方 app.so 或启动官方 rustdesk.exe。来源、AGPL 许可及对应源码随产品提供。设置内不预置远控密码，接入授权与密码验证保留。

构建使用项目 Flutter 3.24.5 缓存、已安装的 MSVC 14.44 和 Windows SDK 10.0.22621.0，通过 CMake NMake 调用正常 Flutter Windows AOT/资产目标。无需改系统 Developer Mode、安装另一个 Visual Studio、改全局 PATH 或代理。项目临时 ASCII 映射在 finally 验证归属后移除，插件目录使用项目内 junction，所有工具及环境只在构建进程内生效。

```powershell
./desktop/build-support/Generate-Icon.ps1
./desktop/build-support/Build-Desktop.ps1 -Action Plan
./desktop/build-support/Build-Desktop.ps1 -Action Prepare
./desktop/build-support/Build-Desktop.ps1 -Action Build
./desktop/build-support/Package-Desktop.ps1
```

安装到当前用户的 `%LOCALAPPDATA%/Programs/XiXiRemote`，自己的入口及内置组件在版本目录中。安装程序登记自己的 Windows 卸载项、桌面和开始菜单入口；不会安装官方 RustDesk、系统服务、驱动、预设远控密码或修改防火墙。安装包含必要 MSVC app-local 运行库。

当前共享在程序运行时提供。开机自动恢复、系统登录屏幕及提权窗口控制不是该预览版的已验收能力。手机端可持久化的系统授权与录屏会话分别处理，不能承诺进程被杀或重启后录屏授权永久有效。

0.5.3-preview 的默认 ID 服务为 `64.176.235.139:24443`，NAT 测试端口 `24442`，中继 `64.176.235.139:21117`。仅完整匹配旧内置 `443` 公开配置时自动迁移并合并对应设备列表，自定义配置保持。Windows 发布资产由 `desktop/assets/default-connection.json` 固定，构建与分发均校验。

0.5.3-preview 独立桌面工作台以选定银线色值与按钮材质为依据，与手机分别设计布局。持久左侧导航、横向连接／本机信息、整行设备表格、搜索工具栏及紧凑鼠标操作按钮；默认主窗口 1100×740。小窗口仍保留左侧图标导航，共享、设置及连接配置使用桌面页面／弹窗。

12 项组件检查包括 3 种窗口、2 种字体缩放、设备编辑、横向布局、搜索及键盘发起连接。渲染截图使用演示编号。实机 `standalone-status.json` 仅输出公开服务字段、本机 ID 和连接状态，不输出密码及完整原生选项。

本版构建及安装程序自检结果见 `runtime/desktop-standalone-package.json` 和发布目录 `verification.json`；以前的安装运行记录 `runtime/desktop-standalone.json` 不作为新版联测结果。组件渲染不等于远端画面、输入或后台联测通过。

共享与设置使用统一标签／内容／动作列、218px 动作宽度、46px 按钮最小高度和一致字号。窄窗口自动纵排。输入 ID 点击连接自动保存设备，已有自定义名称保持，存储不可用时仍可发起连接。
