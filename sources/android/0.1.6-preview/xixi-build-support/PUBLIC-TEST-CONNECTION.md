# 内置公开连接配置

从 0.1.3-preview 起，安装后无需手填服务器。构建时从 runtime/vps-public-profile.json 生成 assets/XIXI-DEFAULT-CONNECTION.json；从 runtime/client-profile.json 生成 assets/XIXI-PREVIOUS-CONNECTION.json，仅用于识别本项目此前的局域网配置。

两份资产各只包含整数 schemaVersion: 1 和字符串 idServer、relayServer、publicKey。默认地址为同一公网 IPv4，ID 端口 443 或 21116，中转端口 21117；旧地址为同一 RFC1918 IPv4 的 21116/21117。公钥必须是规范 Base64 的 32 字节。重复字段、无效类型和重解析路径均拒绝，额外源字段不进入资产。设备 ID、密码、私钥、导入 token 和进程记录不打包。

启动时，空白配置或准确匹配旧局域网地址、公钥且无 API 服务的配置，会通过原生 setServerConfig 保存默认服务并再次读取核验；自定义服务、不同公钥、部分配置和 API 账号配置保留。仅更新四个服务字段，密码及权限沿用原流程。设置中可主动选择“使用西西默认连接服务”，高级服务器编辑仍保留。配置保存不代表网络可达或共享已授权。

两份资产纳入前端 SHA 快照，APK 必须与 staging 和当前白名单投影逐字节相同；对应源码 ZIP 包含同样资产及构建代码。服务变化后须重新构建。源码重建需要提供上述两个公开配置文件，不包含整个 runtime 目录。

0.1.4-preview 修正首页对底层分组 ID 的处理：显示分组编号，复制不含空格的规范编号。不会因此启用屏幕采集或输入权限。
