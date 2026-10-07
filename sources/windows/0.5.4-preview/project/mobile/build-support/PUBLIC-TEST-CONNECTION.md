# 内置公开连接配置

0.1.8-preview 默认 ID 为 videopmt.com:24443，中转为 videopmt.com:21117，保留原服务器公钥。构建时从 runtime/vps-public-profile.json 生成 assets/XIXI-DEFAULT-CONNECTION.json；从 runtime/client-profile.json 生成 assets/XIXI-PREVIOUS-CONNECTION.json，继续识别本项目旧 LAN。受审历史 mobile/assets/XIXI-PREVIOUS-PUBLIC-CONNECTIONS.json 独立保留旧公网 64.176.235.139:24443 与 :443 的完整身份，并另打包到同名 Flutter 资产。

单配置仅含整数 schemaVersion: 1 和字符串 idServer、relayServer、publicKey。公网默认只接受规范公网 IPv4 或明确受审域名 videopmt.com，ID 端口 24443，中转端口 21117，同一主机；LAN 历史使用 RFC1918 的 21116/21117。公钥须为规范 Base64 的 32 字节。重复字段、无效类型和重解析路径拒绝；额外 runtime 字段不投影。公网历史资产固定为两份受审四字段配置，任何增改均拒绝，不从可变 runtime 或任意用户主机推导历史。

空白配置或旧 LAN 可沿既有规则采用默认服务；旧公网仅在 ID、relay、公钥全部匹配且 API 为空时自动迁到域名。通过原 setServerConfig 保存并回读确认，仅改变四个服务字段；自定义服务、API 账户、部分公网配置保留，本机设备身份、密码和权限沿用原流程。

设备列表仅复制已知旧公网 scopes 到当前域名 scope，目标同 ID 现名优先，所有旧 scopes 原样保留。沿既有一次性 bundled_port_migrations：若 443 已迁到 24443，使用 24443 的最新列表，不再次引入已删除的 443 设备；域名列表再次启动也不恢复用户删除项。整个合并一次写入，失败不持久化 marker、不阻止输入 ID 连接，并可重新读取重试。

三份资产纳入前端 SHA 快照，APK 必须与 staging、当前严格投影及固定历史逐字节一致；源码 ZIP 包含同样资产、历史原件、构建代码及迁移实现。服务变更须重新构建。源码重建需要两个公开 runtime 配置及包内独立历史资产，不包含整个 runtime、设备密码或私钥。设置仍可主动恢复默认或编辑自定义服务。配置保存不代表会话连接或共享授权已通过。
