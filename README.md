# MC-LAN-Server（Windows 局域网 Fabric 26.3 模组服）

> 目标：双击 `start.bat` 启动独立 Fabric 服务端，同局域网的其他电脑在 Minecraft「多人游戏 → 直接连接」里输入 `192.168.1.12:25565` 即可进入。
> 本方案只做局域网，不包含 Cloudflare、内网穿透、公网联机。

---

## A. 当前状态（先看这里）

这台虚拟机已经完成从 Paper 到 **Fabric 26.3** 的迁移，并实际验证：

- 服务端：**Fabric Loader 0.20.1 + Minecraft 26.3**，协议 777，端口 **25565**，离线模式。
- 世界：原 Paper 世界已转换并加载，玩家 `xxxx` 的数据保留（坐标、背包等）。
- 26.1.2 原版客户端已通过 ViaFabric 成功进入正式服，日志记录 `logged in with entity id`。
- 26.3 原版客户端可用 `launch-client-26.3.bat`（Mesa llvmpipe）启动并进入。
- 已安装的服务端模组：

  | 模组 | 版本 | 作用 |
  |---|---|---|
  | Fabric API | 0.165.0+26.3 | 大多数 Fabric 模组的前置 |
  | ViaFabric | 0.4.22+188-26.x | 让旧版客户端连接 26.3 服务端 |
  | ViaVersion | 5.12.2-SNAPSHOT | ViaFabric 的协议转换核心 |
  | ViaBackwards | 5.12.2-SNAPSHOT | 把 26.3 服务端协议向下兼容到 26.1.2 |
  | Lithium | 0.26.2+mc26.3 | 服务端性能优化（不需要客户端安装） |

- Paper 服务端没有删除，完整保留在 **`C:\MC-LAN-Server-Paper`**，作为回退方案；详见 H。
- 迁移前的世界备份：`backups\pre-fabric-20261025-1635.zip`。
- 世界格式转换前的 Fabric 世界备份：`backups\fabric-world-pre-convert-*.zip`。

### 日常启动顺序

1. 双击 `C:\MC-LAN-Server\start.bat`（当前服务器可能已经在运行，不要重复启动）。
2. 打开 PCL2，确认版本为 **26.1.2**，点“启动”。
3. 游戏主菜单 →「多人游戏」→「直接连接」→ 输入 `192.168.1.12:25565`。
4. 停止服务器请双击 `stop.bat`，不要直接关窗口或按 Ctrl+C。

### 三种客户端怎么选

| 客户端 | 启动方式 | 能玩什么 |
|---|---|---|
| **26.1.2 原版**（推荐日常） | PCL2 选 26.1.2 | 原版内容；通过 ViaFabric 连接 26.3 服务端，**看不到模组新增的方块/物品/界面** |
| **26.3 原版** | 双击 `launch-client-26.3.bat` | 原版内容；使用 Mesa 软件 OpenGL，帧率低于 26.1.2 |
| **26.3 Fabric + 模组** | 双击 `launch-client-fabric-26.3.bat`（已装好 Fabric Loader 0.20.1 + Fabric API） | 完整模组内容；客户端还要安装与服务端相同的内容模组，详见 F.3 |

> 重要：ViaFabric 只解决“协议版本”兼容，不会把服务端的模组内容同步给 26.1.2 客户端。要实际使用新增方块、物品、生物等模组，客户端必须使用 **Fabric 26.3 + 相同模组**。

---

## B. 方案说明：为什么是 Fabric

1. **原版客户端仍能进**：ViaFabric + ViaVersion + ViaBackwards 让 26.1.2 客户端连接 26.3 服务端，PCL2 的日常入口不用改。
2. **可以加模组**：Fabric 生态的 Lithium、Sodium（客户端）、JEI、Create、农艺、冒险类模组等都可以按需添加。
3. **服务端性能**：Lithium 优化服务端 tick；Paper 的 Bukkit 插件体系不再使用。
4. **回退方便**：原 Paper 目录和世界备份都保留，出问题可以切回 Paper。

版本关系：

- 服务端：Fabric Loader 0.20.1 + Minecraft 26.3，协议 777。
- 日常客户端：Minecraft 26.1.2 原版（PCL2），通过 Via 进入。
- 26.3 客户端：原版 + Mesa llvmpipe，或 Fabric 26.3 + 模组。
- `26.4-snapshot-5` 已安装但不推荐：协议比 26.3 新，不能连当前服务器；且同样受 VMware 显卡驱动问题影响。

---

## C. 目录结构

```text
C:\MC-LAN-Server\
├─ start.bat                 # 双击启动（推荐入口）
├─ start.ps1                 # 启动逻辑：检查 Java/端口/jar，生成配置，打印连接地址
├─ stop.bat / stop.ps1       # 通过 RCON 安全停止并保存世界
├─ admin.bat / admin.ps1     # RCON 管理控制台
├─ backup.bat / backup.ps1   # 一键备份（含 world、mods、config 等）
├─ firewall.bat / .ps1       # 放行 TCP 25565，阻断外部 RCON 25575
├─ download-paper.bat/.ps1   # 仅用于回退 Paper，不要在 Fabric 主目录运行
├─ server.env                # 常用配置（版本、端口、正版验证、内存、MOTD）
├─ server.properties         # 由 start.ps1 自动补全/更新
├─ server-info.txt           # 当前服务端类型/版本信息
├─ fabric-server-launch.jar  # Fabric 启动器（616 字节）
├─ server.jar                # 原版 26.3 服务端 jar（Fabric 启动器需要）
├─ libraries\                # Fabric Loader 依赖库
├─ mods\                     # 启用的 Fabric 模组
├─ mods-disabled\            # 被禁用的模组（不会被加载）
├─ config\                   # 模组配置
├─ world\                    # 世界存档
│  ├─ level.dat
│  ├─ data\ region\ entities\ poi\ players\
│  └─ dimensions\minecraft\the_nether\、the_end\
├─ logs\                     # 服务器日志（latest.log）
├─ backups\                  # 一键备份 ZIP
├─ run\                      # PID 与 RCON 信息（勿外传）
├─ mods-add.bat / .ps1       # 添加模组（拖拽 jar 或下载链接）
├─ mods-list.bat / .ps1      # 查看启用/禁用模组
├─ mods-remove.bat / .ps1    # 禁用模组（移到 mods-disabled）
├─ mods-enable.bat / .ps1    # 重新启用模组
├─ mods-folder.bat           # 打开 mods 文件夹
├─ launch-client-26.3.bat    # 26.3 原版 + Mesa llvmpipe 启动器
├─ launch-client-fabric-26.3.bat/.ps1  # 26.3 Fabric 客户端 + Mesa 启动器
└─ README.md
```

> `mods\` 里只放 `.jar` 模组文件。`mods-disabled\` 里的文件不会被 Fabric 加载，适合临时排查冲突。
> `world\` 已经是 Fabric/原版布局：主世界在根目录，下界/末地在 `world\dimensions\minecraft\` 下。不要直接把 Paper 目录里的 `world` 覆盖过来。

---

## D. 启动、停止与管理

### 启动

双击 `start.bat`。窗口会打印：

- 本机局域网 IPv4 和连接地址（应为 `192.168.1.12:25565`）；
- 服务端版本与加载器；
- 最大人数、正版验证状态；
- 首次启动会写 `eula.txt`、补全 `server.properties`。

看到日志出现 `Done (…)! For help, type "help"` 后即可连接。

### 停止

双击 `stop.bat`。脚本通过本机 RCON 执行 `save-all` + `stop`，等待进程退出，避免世界损坏。

不要在服务器窗口点右上角关闭，也不要在窗口里按 Ctrl+C（可能来不及保存）。

### 管理命令

```bat
admin.bat                 :: 交互式控制台，可输入 list / say / op 玩家名 / whitelist add 玩家名
admin.bat list            :: 一次性执行
admin.bat "data get entity xxxx Pos"
```

RCON 端口是 25575，密码在 `run\rcon.txt`，不要外传。`firewall.bat` 已阻断外部访问 25575，只在本机使用；不要在路由器上放行 25575。

### 配置文件

常用项改 `server.env`，不要直接改 `server.properties` 的托管项：

```ini
MC_VERSION=26.3
SERVER_JAR=fabric-server-launch.jar
SERVER_PORT=25565
ONLINE_MODE=false
MOTD=§aFabric LAN Server §7| §eMinecraft 26.3
MAX_PLAYERS=10
VIEW_DISTANCE=10
SIMULATION_DISTANCE=10
SPAWN_PROTECTION=0
DIFFICULTY=normal
GAMEMODE=survival
PVP=true
WHITELIST=false
MIN_MEMORY=2G
MAX_MEMORY=4G
JVM_ARGS=
JAVA_EXE=
RCON_PORT=25575
```

- `ONLINE_MODE=false`：离线模式，朋友不需要正版账号；正版账号也能进。
- `ONLINE_MODE=true`：必须微软正版登录；同时要删除 hosts 里的 `sessionserver.mojang.com` 屏蔽（见 H.7）。
- 内存优先改 `MIN_MEMORY` / `MAX_MEMORY`；`JVM_ARGS` 用于追加其他 JVM 参数，不要填 `-jar`/`-cp`。

---

## E. 添加和管理模组（重点）

### E.1 最简单的添加方式：拖拽

1. 从 Modrinth / CurseForge 下载 **Fabric 26.3** 的 `.jar` 模组。
2. 把 `.jar` 直接拖到 **`mods-add.bat`** 上（可以一次拖多个）。
3. 脚本会检查文件、识别 `fabric.mod.json`、复制到 `mods\`。
4. 重启服务器：先 `stop.bat`，再 `start.bat`。
5. 看 `logs\latest.log` 是否有模组加载和 `Done`，没有报错即成功。

也可以双击 `mods-add.bat`，在窗口里粘贴本地路径或下载链接。

### E.2 用命令行添加

```bat
mods-add.bat C:\Users\你\Downloads\some-mod.jar
mods-add.bat "C:\Users\你\Downloads\模组 A.jar" "C:\Users\你\Downloads\模组 B.jar"
```

支持直接粘贴 **Modrinth 模组页面链接**，脚本会自动查询 26.3 + Fabric 的最新版本并下载：

```bat
mods-add.bat https://modrinth.com/mod/lithium
mods-add.bat https://modrinth.com/mod/sodium/version/xxxxx
```

也支持任意直接 `.jar` 下载链接：

```bat
mods-add.bat https://example.com/path/mod.jar
```

### E.3 查看、禁用、重新启用

```bat
mods-list.bat       :: 查看启用/禁用模组、版本、文件名、大小
mods-remove.bat     :: 交互式选择要禁用的模组（移到 mods-disabled）
mods-enable.bat     :: 把 mods-disabled 里的模组移回 mods
mods-folder.bat     :: 用资源管理器打开 mods 文件夹
```

`mods-remove.bat` 默认是“禁用”而不是删除：文件会移到 `mods-disabled\`，之后可以用 `mods-enable.bat` 恢复。确认不再需要时，再手动删除 `mods-disabled\` 里的文件。

也可以直接传文件名或模组 ID：

```bat
mods-remove.bat lithium-fabric-0.26.2+mc26.3.jar
mods-remove.bat fabric-api
```

### E.4 模组选择规则（很重要）

- **必须选 Fabric 版本**，不能选 Forge / NeoForge / Quilt 专用版本。
- **必须匹配 Minecraft 26.3**；模组页面通常会写 `26.3` 或 `26.x`。
- 大多数模组需要 **Fabric API**，不要移除它。
- 不要同时放同一个模组的多个版本；`mods-add.bat` 遇到同名文件会备份旧版本到 `mods-disabled`。
- 服务端模组和客户端模组要分清：
  - 只改服务端逻辑/性能的（如 Lithium、部分优化模组）通常只需服务端；
  - 新增方块、物品、生物、维度、GUI 的模组，**客户端必须装同一个模组和 Fabric API**，否则会连接失败或看不到内容；
  - 不确定时看模组页面的 “Environment: Client / Server / Both”。
- 加模组前建议先 `backup.bat`，尤其是会改变世界生成、方块 ID、实体 ID 的模组。
- 如果加完模组服务器起不来：先 `mods-remove.bat` 禁用最近添加的模组，再启动排查；日志在 `logs\latest.log`。

### E.5 当前模组不要随意移除

- `fabric-api`：大多数模组的前置。
- `ViaFabric` + `ViaVersion` + `ViaBackwards`：保留 26.1.2 客户端兼容。ViaFabric 自带的是 ViaVersion 5.12.1，而 ViaBackwards 5.12.2 需要单独的 `ViaVersion-5.12.2-SNAPSHOT.jar`；三个文件要一起保留。
- `Lithium`：服务端性能优化，客户端不需要安装。

---

## F. 客户端准备

### F.1 日常：PCL2 + 26.1.2 原版（推荐）

1. 打开 PCL2 → 版本选择 **Minecraft 26.1.2**（当前 `C:\.minecraft\PCL.ini` 已设为 26.1.2）。
2. 不要给这个实例装 Forge/Fabric 或改变方块/物品的模组。
3. 启动后「多人游戏」→「直接连接」→ `192.168.1.12:25565`。
4. 服务端已装 Via，26.1.2 可以进入 26.3 世界；但只能看到原版内容。

### F.2 26.3 原版 + Mesa

双击 `C:\MC-LAN-Server\launch-client-26.3.bat`。它会设置：

- `GALLIUM_DRIVER=llvmpipe`
- `MESA_GL_VERSION_OVERRIDE=4.6`
- `MESA_GLSL_VERSION_OVERRIDE=460`
- `PATH=C:\mesa\x64`
- `-Dorg.lwjgl.opengl.libname=C:\mesa\x64\opengl32.dll`

并自动连接 `192.168.1.12:25565`。Mesa llvmpipe 是 CPU 渲染，能玩但帧率低于 26.1.2；日常仍建议 PCL 启动 26.1.2。

### F.3 要玩模组内容：Fabric 26.3 客户端（已装好）

这台机器已经装好 **Fabric Loader 0.20.1 + Minecraft 26.3** 客户端，并放入了 Fabric API。直接双击：

```text
C:\MC-LAN-Server\launch-client-fabric-26.3.bat
```

它会用 Mesa llvmpipe 启动 Fabric 26.3，并自动连接 `192.168.1.12:25565`。

客户端模组目录（两个位置都已放 Fabric API，按你的启动方式选一个即可）：

- 使用 `launch-client-fabric-26.3.bat`：`C:\.minecraft\versions\fabric-loader-0.20.1-26.3\mods\`
- 使用 PCL2 且关闭版本隔离：`C:\.minecraft\mods\`
- 使用 PCL2 且开启版本隔离：PCL 为该实例创建的 `mods\` 目录

要玩服务端的内容模组：

1. 把服务端 `mods\` 里对应的内容模组 `.jar` **复制**到上面的客户端 `mods\` 目录（不要复制 Lithium、ViaFabric、ViaVersion、ViaBackwards 这类纯服务端模组）。
2. 客户端至少需要 **Fabric API**（已放好），以及服务端新增方块/物品/生物对应的模组。
3. 客户端和服务端的模组版本尽量完全一致；至少保证游戏版本都是 26.3、加载器都是 Fabric。
4. 如果客户端也受 VMware 显卡驱动影响，`launch-client-fabric-26.3.bat` 已经带上 Mesa 环境变量；用 PCL 直接启动 Fabric 26.3 可能只显示全景图。
5. 第一次启动如果停在“Welcome to Minecraft / Narrator”引导，点 **Continue** 即可；本机已经关闭该引导。

> 26.1.2 客户端即使装了 Fabric，也不能使用 26.3 的模组内容；模组内容需要 26.3 客户端。
> 只加服务端优化模组（如 Lithium）时，26.1.2 客户端仍可正常进入，不需要改客户端。

### F.4 PCL2 版本选择注意事项

- 当前 PCL 的日常版本是 **26.1.2**，不要选 `26.4-snapshot-5`。
- `26.4-snapshot-5` 协议比 26.3 新，连不上当前服务器；而且同样受显卡驱动问题影响。
- 如果 PCL 版本被改成 26.4，改回 26.1.2 后再启动。

---

## G. 世界、备份与恢复

### 一键备份

双击 `backup.bat`，服务器运行中或已停止都可以：

- 运行中：RCON `save-off` → `save-all flush` → 打包 → `save-on`；
- 已停止：直接读磁盘打包；
- 备份文件：`backups\mc-backup-年-月-日-时-分-秒.zip`；
- 内容包含：`world\`、`mods\`、`mods-disabled\`、`config\`、`plugins\`（如果存在）、`server.properties`、`server.env`、`eula.txt`、`ops.json`、`whitelist.json`、`banned-*.json`、`server-info.txt` 等；
- 不包含：`logs\`、`server.jar`、`libraries\`、`run\`（含 RCON 密码）等。

备份 ZIP 里的 `server.properties` 含 RCON 密码，不要发给别人或上传公开网盘。

### 恢复备份

1. 先 `stop.bat`，确认服务器完全退出。
2. 把当前 `world` 重命名为 `world.before-restore-时间`（不要直接删除）。
3. 解压备份 ZIP 里的 `world` 到 `C:\MC-LAN-Server\`，覆盖当前 `world`。
4. 如果只想恢复世界，不要解压备份里的 `server.env`，以免把端口/内存设置改回旧值。
5. 启动服务器，进游戏确认世界、背包、建筑正常后，再删除 `world.before-restore-时间`。

### 世界格式说明

Paper 的世界布局和 Fabric/原版不同：

- Paper：主世界、下界、末地都在 `world\dimensions\minecraft\` 下；
- Fabric/原版：主世界在 `world\` 根目录，下界/末地在 `world\dimensions\minecraft\` 下。

迁移时已经把 Paper 的 `overworld` 数据合并到 `world\` 根目录。日志里的 `Missing data pack paper` 是 Paper 专用数据包引用，Fabric 会忽略，不影响游戏。

---

## H. 常见故障排查

### H.1 26.1.2 客户端连不上 / 提示版本不兼容

1. 确认 `mods\` 里仍有 `ViaFabric`、`ViaVersion`、`ViaBackwards`。
2. 看 `logs\latest.log` 是否有：
   - `ViaVersion detected server version: 26.3 (777)`
   - `viabackwards 5.12.2-SNAPSHOT`
   - `Done (…)!`
3. 如果 ViaBackwards 提示 `YOUR VIAVERSION IS OUTDATED`，说明缺少单独的 `ViaVersion-5.12.2-SNAPSHOT.jar`，不要只留 ViaFabric 自带的 5.12.1。
4. 26.1.2 客户端连接前会请求 `sessionserver.mojang.com`，本机已在 hosts 中把它指向 `127.0.0.1`；如果以后改用正版模式，要删除这行。

### H.2 加模组后服务器起不来

1. 看 `logs\latest.log` 最后的 `ERROR` / `Caused by`。
2. 常见原因：
   - 模组不是 Fabric 26.3 版本；
   - 缺少前置（Fabric API 或其他库）；
   - 同一模组放了多个版本；
   - 模组之间冲突。
3. 用 `mods-remove.bat` 禁用最近添加的模组，再 `start.bat`；能启动后再逐个加回定位。
4. 加模组前先 `backup.bat`，避免世界被不兼容模组改坏。

### H.3 客户端能进但看不到模组内容

- 26.1.2 通过 Via 只能看到原版内容，这是正常的。
- 要看到新增方块/物品/生物，客户端必须使用 **Fabric 26.3 + 相同模组**（见 F.3）。
- 如果客户端缺少服务端的内容模组，可能连接被拒绝或提示缺少 registry 内容。

### H.4 端口 25565 被占用

```bat
netstat -ano | findstr :25565
```

找到 PID 后结束占用程序，或修改 `server.env` 的 `SERVER_PORT`。不要同时运行 Fabric 主服和 `C:\MC-LAN-Server-Paper` 的 Paper 服，它们默认都用 25565。

### H.5 Java 版本不对

- Fabric 26.3 需要 **Java 25 或更高（64 位）**；当前虚拟机使用 Java 27，已实测可启动。
- 如果提示 `Unsupported class file major version` 或找不到 Java，安装 Temurin/Microsoft OpenJDK 25+，然后在 `server.env` 写：

  ```ini
  JAVA_EXE=C:\Program Files\Eclipse Adoptium\jdk-25.x.x-hotspot\bin\java.exe
  ```

### H.6 26.3 客户端只有全景图 / 不显示主菜单

- 根因：VMware SVGA 驱动缺少 `GL_ARB_buffer_storage`。
- 解决：用 `launch-client-26.3.bat`（Mesa llvmpipe）。
- 如果以后 VMware Tools 更新到支持 OpenGL 4.6 + 该扩展的驱动，可以去掉 Mesa 设置，直接用 PCL 启动 26.3。

### H.7 hosts 与正版模式

当前 hosts 里有：

```text
127.0.0.1 sessionserver.mojang.com
```

作用是避免离线模式下客户端连接前卡在 Mojang 的 `blockedservers` 请求。离线模式没有副作用；如果以后改用微软正版账号 / `online-mode=true`，**必须删除这一行**，否则正版验证会失败。

### H.8 防火墙

- `firewall.bat` 放行入站 TCP 25565，并阻断外部 RCON 25575。
- 如果使用 360、火绒等第三方防火墙，还需要在它们界面里放行 25565。
- 虚拟机网络必须是**桥接（Bridged）**；NAT/仅主机模式外部电脑无法直接访问。

### H.9 想回退 Paper

Paper 完整保留在 `C:\MC-LAN-Server-Paper`：

1. 先 `stop.bat` 停止 Fabric 主服。
2. 进入 `C:\MC-LAN-Server-Paper`，双击 `start.bat`。
3. 它的 `server.env` 仍是 Paper 26.3、端口 25565、RCON 25575，插件 `ViaVersion` / `ViaBackwards` 仍在 `plugins\`。
4. 注意：Paper 目录里的世界是**迁移前的快照**；迁移后在 Fabric 服里的新进度不会自动同步回去。需要保留新进度时，先备份 Fabric 世界，再决定是否迁移。
5. 回退测试完成后，停止 Paper，再启动 Fabric 主服；不要同时运行两个。

`download-paper.bat` 只用于回退/重装 Paper。**不要在 Fabric 主目录运行它**，它会覆盖 `server.jar`（Fabric 启动器需要的原版 jar）。

---

## I. 验收清单

- [ ] `start.bat` 启动后日志出现 `Loading Minecraft 26.3 with Fabric Loader 0.20.1`、5 个模组加载、`Done`。
- [ ] `mods-list.bat` 显示 5 个启用模组，版本正确。
- [ ] 26.1.2 客户端通过 PCL2 连接 `192.168.1.12:25565`，服务端日志出现 `logged in with entity id`。
- [ ] 进入后位置/背包/建筑与迁移前一致。
- [ ] 放置/破坏方块，重启后仍然保留。
- [ ] `mods-add.bat` 拖入一个 Fabric 26.3 模组，重启后日志显示加载；`mods-remove.bat` 禁用后重启不再加载。
- [ ] `backup.bat` 生成的 ZIP 里包含 `world\`、`mods\`、`config\`、`server.properties`。
- [ ] `stop.bat` 安全停止，`run\server.pid` 消失；再次 `start.bat` 世界正常。
- [ ] `firewall.bat -Status` 显示 25565 放行；外部无法访问 25575。
- [ ] 另一台物理电脑能 ping 通 `192.168.1.12` 并进入服务器（VMware 需桥接、路由器未开 AP 隔离）。

---

## J. 已验证记录（2026-10-25）

- Paper 26.3 + ViaVersion/ViaBackwards：26.1.2 客户端多次成功加入。
- 26.3 原版客户端 + Mesa llvmpipe：主菜单正常，实际进入服务器。
- Fabric 26.3 测试服：Fabric API、ViaFabric、ViaVersion 5.12.2、ViaBackwards 5.12.2、Lithium 全部加载，`Done`。
- 26.1.2 客户端成功进入 Fabric 26.3 测试服（`logged in with entity id 25`）。
- 正式迁移：Paper 世界复制到 Fabric，overworld 数据合并到世界根目录，服务器启动并加载真实世界；26.1.2 客户端进入正式服，玩家 `xxxx` 数据保留。
- Fabric 26.3 客户端（Loader 0.20.1 + Fabric API）已安装，`launch-client-fabric-26.3.bat` 用 Mesa llvmpipe 启动并成功进入正式服（`logged in with entity id 164`），截图确认已进入游戏画面。
- 模组脚本：添加（重复检测）、列出、禁用、重新启用均已实际测试。
- 迁移前备份：`backups\pre-fabric-20261025-1635.zip`（约 7.8 MB）。
- 世界转换前备份：`backups\fabric-world-pre-convert-*.zip`（约 7.8 MB）。

---

## K. 参考：RCON 与常用命令

```bat
admin.bat list
admin.bat "say 服务器 5 分钟后重启"
admin.bat "op 玩家名"
admin.bat "whitelist add 玩家名"
admin.bat "save-all"
```

RCON 信息在 `run\rcon.txt`：

```text
SERVER_PORT=25565
RCON_PORT=25575
RCON_PASSWORD=<本机随机密码>
```

只在本机使用，不要暴露到局域网外。
