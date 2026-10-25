# MC-LAN-Server（Windows 局域网 Minecraft 服务器）

> 目标：双击 `start.bat` 启动独立 Paper 服务端，同局域网的其他电脑在 Minecraft「多人游戏 → 直接连接」里输入 `192.168.x.x:25565` 即可进入。
> 本方案只做局域网，不包含 Cloudflare、内网穿透、公网联机。

---

## A. 方案选择：Paper，而不是原版 / Fabric / Forge

**推荐：Paper 26.3（当前已下载 build 218）。**

理由：

1. **PCL2 的原版客户端可以直接连**：Paper 是与原版协议兼容的服务端，客户端不需要安装任何模组。服务端已加 ViaVersion + ViaBackwards，26.1.2 客户端也能进；26.3 客户端可用 `launch-client-26.3.bat`（Mesa llvmpipe）正常启动。
2. **后续搭擂台/小游戏最方便**：Paper 支持 Bukkit/Spigot/Paper 插件，WorldGuard、Multiverse-Core、Essentials、LuckPerms、各类 PvP/小游戏插件都能用。
3. **性能和稳定性比原版好**：Paper 对区块、实体、网络做了优化，适合长期开服和反复重启。
4. **Fabric/Forge 只在“必须装模组”时才需要**：模组服要求客户端安装完全相同的加载器和模组，PCL2 朋友端也要同步，维护成本高。你现在的目标是原版客户端 + 局域网 + 以后加插件，Paper 是更合适的选择。

版本关系（以当前实际可用为准）：

- 服务端：Paper 26.3，协议版本 777。
- 客户端：PCL2 中选 **Minecraft 26.1.2 原版**（不要装 Forge/Fabric，不要加会改变方块/物品的模组）。服务端已装 ViaVersion + ViaBackwards，26.1.2 可以正常进入 26.3 世界。26.3 原版客户端需要配合 `launch-client-26.3.bat` 的 Mesa 环境才能显示主菜单（见 A0）。
- 如果以后确实要玩模组：把服务端换成同版本 Fabric/Forge，并让每个客户端安装同样的加载器和模组；本方案脚本仍可复用，只需替换 `server.jar` 和 `server.env` 中的 `MC_VERSION`。

**关于 PCL2 自动化（重要）**：

PCL2 是 GUI 启动器，没有受支持的命令行接口可以自动“进入某个世界 → 点击对局域网开放”。PCL2 的“联机”功能也依赖游戏内的“对局域网开放”界面。用 UI 自动化去点按钮不稳定，且每次窗口布局/版本更新都可能失效。因此本方案**不假设 PCL2 能自动点 GUI**，而是采用“独立服务端 + PCL2 客户端连接”的标准方案。

---

## A0. 当前可用方案（2026-10-25 修复，先看这里）

这台虚拟机已经实际验证：**Minecraft 26.1.2 和 Minecraft 26.3 客户端都能进入 Paper 26.3 服务端**，服务端日志记录到 `joined the game` / `logged in with entity id`。

- 服务端：Paper 26.3 build 218，协议 777，端口 25565，离线模式。
- 已安装兼容插件：
  - `plugins\ViaVersion-5.12.2-SNAPSHOT.jar`（支持 26.3 服务端）
  - `plugins\ViaBackwards-5.12.2-SNAPSHOT.jar`（让 26.1.2 等旧客户端连 26.3 服务端）
- 推荐客户端：**PCL2 中选择 Minecraft 26.1.2**（当前 `C:\.minecraft\PCL.ini` 已设为 26.1.2）。26.1.2 使用 VMware 硬件 OpenGL，帧率更好，是日常游玩的首选。
- **26.3 客户端现在也能用**：这台虚拟机的 VMware SVGA 驱动（Mesa 23.2）缺少 `GL_ARB_buffer_storage` 扩展，导致 26.3 的 GUI 渲染器不显示主菜单。已下载 Mesa 26.2.4 到 `C:\mesa`，双击 `C:\MC-LAN-Server\launch-client-26.3.bat` 会用 Mesa llvmpipe（软件 OpenGL 4.6）启动 26.3 并自动连接 `192.168.1.12:25565`。llvmpipe 是 CPU 渲染，能玩但帧率低于 26.1.2；日常仍建议用 PCL 启动 26.1.2。
- 已做过的系统级修复（换电脑/重装系统后需要重做）：
  1. `C:\Windows\System32\drivers\etc\hosts` 增加 `127.0.0.1 sessionserver.mojang.com`。原因是客户端连接服务器前会请求 Mojang 的 `blockedservers` 列表，这个网络下该请求会无限挂起，导致一直停在“正在连接至服务器...”。离线模式下屏蔽它没有副作用；如果以后改用微软正版账号 / `online-mode=true`，请删除这一行。
  2. 已运行 `firewall.bat`，放行入站 TCP 25565，并阻断外部 RCON 25575。
- 启动顺序（日常）：
  1. 双击 `C:\MC-LAN-Server\start.bat`（当前已经在运行，不要重复启动）。
  2. 打开 PCL2，确认版本为 **26.1.2**，点“启动”。
  3. 游戏主菜单 →「多人游戏」→「直接连接」→ 输入 `192.168.1.12:25565`。
- 想用原生 26.3：直接双击 `launch-client-26.3.bat`（不要从 PCL 选 26.3，PCL 不会带上 Mesa 环境变量，仍会只有全景图）。如果以后 VMware Tools 更新到支持 OpenGL 4.6 + `GL_ARB_buffer_storage` 的驱动，可以删掉 Mesa 相关设置，直接用 PCL 启动 26.3。
- 版本目录里还有一个 `26.4-snapshot-5`（PCL 下载的快照）。它同样受 VMware 驱动缺少 `GL_ARB_buffer_storage` 的影响，直接从 PCL 启动只会显示全景图；而且它的协议比服务端 26.3 新，不能连当前服务器。**PCL 的版本选择请保持 26.1.2**（已恢复），不要选 26.4-snapshot-5。

---

## B. 目录结构

```text
C:\MC-LAN-Server\
├─ start.bat                 # 双击启动（推荐入口）
├─ start.ps1                 # 主启动逻辑：检查 Java/端口/jar，生成配置，打印连接地址
├─ stop.bat                  # 双击安全停止
├─ stop.ps1                  # 通过 RCON 发送 save-all + stop，等待进程退出
├─ admin.bat                 # 双击打开管理员控制台；也支持 admin.bat list
├─ admin.ps1                 # RCON 管理命令
├─ backup.bat                # 双击一键备份（服务器运行中或已停止都可以）
├─ backup.ps1                # 备份逻辑：运行中先 save-off/刷盘，再打包，最后 save-on
├─ firewall.bat              # 双击自动请求管理员权限，放行 25565
├─ firewall.ps1              # 防火墙规则（放行 25565，阻断外部 RCON）
├─ download-server.bat       # 双击下载/更新 Paper 服务端
├─ download-server.ps1       # Paper API / Mojang 官方服务端下载
├─ server.env                # 常用配置（版本、端口、正版验证、内存、JVM 参数、MOTD）
├─ server.properties         # 由 start.ps1 自动补全/更新；其他自定义项会保留
├─ eula.txt                  # 自动写入 eula=true
├─ server.jar                # Paper 服务端（已下载并校验）
├─ server-info.txt           # 下载脚本写入的版本/构建/校验信息
├─ lib\
│  ├─ Common.ps1             # 公共函数（配置、属性文件、IP、端口、进程）
│  ├─ Java.ps1               # Java 检测、jar 版本/加载器识别
│  └─ Rcon.ps1               # RCON 客户端（安全停止/管理）
├─ run\
│  ├─ server.pid             # 运行中服务器的 PID（自动生成/清理）
│  ├─ rcon.txt               # 停止/管理脚本使用的本机 RCON 信息（勿外传）
│  └─ server.jar.download    # 下载临时文件（仅下载时存在）
├─ logs\                     # Minecraft 日志（latest.log 等）
├─ world\                    # 世界存档（主世界/下界/末地都在 world\dimensions 下）
├─ plugins\                  # Paper 插件（已放 ViaVersion / ViaBackwards）
├─ backups\                  # 一键备份生成的 ZIP（不会自动删除，需手动清理旧备份）
├─ config\ .paper\            # Paper 自身配置/缓存（自动生成，一般不用改）
├─ bukkit.yml spigot.yml commands.yml  # Paper 兼容配置（自动生成）
├─ cache\ versions\ libraries\  # Paper 首次启动生成的补丁缓存，勿手动改
└─ README.md
```

> `server.properties` 的托管项每次启动会按 `server.env` 刷新；不认识的项和注释会保留。以后加插件时，插件自己的配置文件在 `plugins\` 下，不受影响。

---

## C. 关键文件内容 / 配置说明

### start.bat（完整内容）

```bat
@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1"
set "EXITCODE=%ERRORLEVEL%"
echo.
pause
exit /b %EXITCODE%
```

### stop.bat（完整内容）

```bat
@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop.ps1" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
pause
exit /b %EXITCODE%
```

### server.properties 托管项（自动生成，不需要手改）

```properties
server-port=25565
server-ip=
online-mode=false
enforce-secure-profile=false
motd=\u00A7aPaper LAN Server \u00A77| \u00A7eMinecraft 26.3
max-players=10
view-distance=10
simulation-distance=10
spawn-protection=0
difficulty=normal
gamemode=survival
pvp=true
white-list=false
enable-rcon=true
rcon.port=25575
rcon.password=<自动生成的 24 位随机密码>
broadcast-rcon-to-ops=true
enable-status=true
```

说明：

- `online-mode=false`：离线模式，没有正版账号的朋友也能进。默认值可改。
- `online-mode=true`：正版模式，客户端必须用微软正版账号登录；脚本会自动把 `enforce-secure-profile` 设为 `true`。
- `server-ip=` 留空表示监听所有网卡；不要填 `127.0.0.1`，否则其他电脑连不上。
- `motd` 中的中文和 `§` 颜色符号会被脚本转成 Java Properties 的 Unicode 转义，避免乱码。
- `rcon.password` 首次启动自动生成；`stop.bat`/`admin.bat` 自动读取，不要外泄，也不要在路由器上放行 25575。
- 想改端口/人数/视距/正版验证/内存：改 `server.env`，不要直接改 `server.properties` 的托管项。

### eula.txt

首次启动自动生成：

```text
#By changing the setting below to TRUE you are indicating your agreement to the Minecraft EULA.
#https://aka.ms/MinecraftEULA
eula=true
```

继续启动即表示你同意 Minecraft EULA。**这是必须由你确认的法律协议**；脚本只是替你写入文件，不代替你同意。

### server.env（默认值可改）

```ini
MC_VERSION=26.3
SERVER_JAR=server.jar
SERVER_PORT=25565
ONLINE_MODE=false
MOTD=§aPaper LAN Server §7| §eMinecraft 26.3
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

### 自定义 JVM 参数（server.env，默认值可改）

`JVM_ARGS` 留空即可。需要追加参数时，写在等号后面，多个参数用空格分隔：

```ini
JVM_ARGS=-Dcustom.name="My LAN Server" -XX:+UseStringDeduplication
```

- 参数会追加到脚本内置的 Aikar G1 GC 参数之后、`-jar` 之前。
- 参数值含空格时用英文双引号包住；引号内的反斜杠按 Windows 命令行规则处理。
- 不要填写 `-jar`、`-cp`、`-classpath`：服务端主类和 classpath 由启动脚本管理；填写后脚本会直接报错并拒绝启动。
- 修改后下一次双击 `start.bat` 生效。启动窗口会在“额外 JVM”一行显示实际追加的参数。
- 内存优先改 `MIN_MEMORY` 和 `MAX_MEMORY`；再用 `JVM_ARGS` 调整其他 JVM 选项。

### firewall.ps1（可选，管理员）

双击 `firewall.bat` 会请求 UAC 管理员权限，然后：

- 放行入站 TCP **25565**（所有网络配置文件，确保局域网能连）。
- 增加入站 **阻断 TCP 25575** 的规则，防止别人远程连 RCON；本机 `127.0.0.1` 的 `stop.bat` 不受影响。
- 查看状态：`firewall.bat -Status`
- 撤销规则：`firewall.bat -Remove`

如果使用 360、火绒等自带防火墙，还需要在它们的界面里放行 TCP 25565。

### 管理命令（可选）

```bat
admin.bat                 :: 交互式控制台，可输入 list / say / op 玩家名 / whitelist add 玩家名
admin.bat list            :: 一次性执行
```

停止服务器请优先用 `stop.bat`，不要在服务器窗口点右上角关闭，也不要在窗口里按 Ctrl+C（可能来不及保存）。

### 一键备份（backup.bat，推荐）

双击 `backup.bat` 即可备份，**服务器运行中或已经停止都可以**：

- **服务器运行中**：脚本会通过本机 RCON 执行 `save-off`（暂停自动保存）→ `save-all flush`（强制刷盘）→ 打包 → `save-on`（恢复自动保存）。打包失败时也会尝试恢复 `save-on`；如果恢复失败，会提示你到服务器窗口手动输入 `save-on`。
- **服务器已停止**：直接读取磁盘文件打包，不需要 RCON。
- 备份文件保存在 `backups\mc-backup-年-月-日-时-分-秒.zip`，不会自动删除旧备份；磁盘占用变大时请手动删除不需要的旧 ZIP。
- 备份内容：`world\`、`plugins\`、`config\`、`server.properties`、`server.env`、`eula.txt`、`ops.json`、`whitelist.json`、`banned-players.json`、`banned-ips.json`、`bukkit.yml`、`spigot.yml`、`commands.yml`、`server-info.txt`。
- 不备份：`logs\`、`server.jar`、`cache\` 等缓存、`run\`（其中 `rcon.txt` 含管理密码），以及世界里的 `session.lock`（避免恢复时误触发会话锁）。
- 备份 ZIP 里的 `server.properties` 含 RCON 密码，**不要发给别人或上传到公开网盘**。

**恢复备份**（示例，恢复前一定先停止服务器）：

1. 双击 `stop.bat`，确认服务器已完全退出。
2. 先给当前世界留一份保险：把 `C:\MC-LAN-Server\world` 重命名为 `world.before-restore-时间`（不要直接删除）。
3. 用资源管理器打开 `backups\` 里的目标 ZIP，把里面的 `world` 文件夹解压到 `C:\MC-LAN-Server\`，覆盖当前 `world`。
4. 如果只想恢复世界，到此为止；不要解压 ZIP 里的 `server.env`，以免把当前的内存/端口设置改回旧值。
5. 双击 `start.bat`，进入游戏确认世界、背包和建筑正常；确认无误后再手动删除 `world.before-restore-时间`。

> 恢复时不要解压 `server.jar`、`run\`、`logs\` 等内容；备份里本来也不包含它们。

---

## D. 首次部署步骤（1、2、3）

本机已经完成 1 和 2，直接做 3 即可；换电脑时按下面顺序：

1. **准备服务端 jar**
   - 推荐：双击 `download-server.bat`，脚本会从 PaperMC 官方 API 下载与 `server.env` 中 `MC_VERSION` 匹配的最新 Paper，并校验 SHA256。
   - 也可手动下载 Paper 26.3 的 jar，重命名为 `server.jar` 放到 `C:\MC-LAN-Server\`。
   - 如果 Paper 暂时没有对应版本，可运行 `download-server.bat -Vanilla` 下载 Mojang 官方原版服务端（没有插件支持）。
2. **放行防火墙（需要管理员）**
   - 双击 `firewall.bat`，在 UAC 窗口点“是”。
   - 如果系统提示网络为“公用网络”，仍然建议运行本脚本；它会按所有配置文件放行 25565。
3. **双击 `start.bat`**
   - 脚本会自动检测 Java、检查 25565 是否被占用、检查 jar、写 `eula.txt`、补全 `server.properties`、打印本机 IPv4 和连接地址，然后启动服务器。
   - 首次启动要生成世界，可能需要 1–3 分钟；看到 `Done` 后即可让朋友连接。
   - 服务器窗口保持打开；停止请双击 `stop.bat`（不要直接关窗口）。

---

## E. 局域网连接步骤

**房主（运行服务端的电脑）**：

1. 双击 `start.bat`。
2. 看窗口里的两行：

   ```text
   本机局域网 IPv4 : 192.168.1.12（Ethernet0，/24）
   其他电脑填写    : 192.168.1.12:25565
   ```

3. 也可以按 `Win+R` 输入 `cmd`，执行 `ipconfig`，找“IPv4 地址”。IPv4 形如 `192.168.x.x`、`10.x.x.x`、`172.16.x.x`–`172.31.x.x`。
4. 把 `IP:25565` 发给朋友。**冒号必须是英文 `:`**。

**朋友（另一台电脑）**：

1. 打开 Minecraft Java 版（PCL2 启动的 26.1.2 原版客户端；服务端已装 Via 兼容插件）。
2. 进入「多人游戏」→「直接连接」。
3. 输入 `192.168.1.12:25565`，加入服务器。
4. 第一次进入会被服务器记录；如果要给朋友管理员权限，房主双击 `admin.bat`，输入 `op 朋友的游戏名`。

> 如果客户端显示 `Outdated client! Please use 26.3`，先确认服务端 `plugins\` 下的 ViaVersion / ViaBackwards 是否还在、是否成功加载；详见 H.5。

注意：

- 两台电脑必须在**同一个局域网/同一个路由器**下，且没有开启“访客网络/AP 隔离/客户端隔离”。
- 如果房主是 VMware 虚拟机：虚拟机网络必须设置为**桥接（Bridged）**；NAT 模式下宿主机以外的电脑无法直接访问虚拟机，host-only 模式更不行。
- 如果有多张网卡（VMware、VirtualBox、VPN），窗口会列出多个地址；请选择与朋友同一网段的那个。

---

## F. 用 PCL2 准备客户端

1. 打开 PCL2 →「下载」→ 搜索/选择 **Minecraft 26.1.2**（正式版）。当前这台机器已经装好 26.1.2，直接在版本列表选它即可。
2. 选择**原版（Vanilla）**安装，不要选 Forge/Fabric，除非你明确要开模组服。
3. 安装完成后，在版本设置里确认游戏版本就是 `26.1.2`，并且没有额外启用的模组。
4. 如果 PCL2 使用“版本隔离”，给这个 26.1.2 单独一个实例，避免其他整合包的模组混进来。
5. 登录方式：
   - 服务端 `ONLINE_MODE=false`：PCL2 可用离线登录，朋友不需要正版账号；正版账号也可以进。
   - 服务端 `ONLINE_MODE=true`：必须使用微软正版账号登录，离线账号会被拒绝。
6. 服务端已经安装 ViaVersion + ViaBackwards，26.1.2 客户端可以连 26.3 服务端。若想用 26.3，双击 `launch-client-26.3.bat`（带 Mesa llvmpipe 环境），不要直接从 PCL 选 26.3。

---

## G. 验收测试清单

### 已完成的本地实际联机验证（2026-10-24）

本机已用**官方 Minecraft 26.3 原版客户端实际进入世界**，不是只检查端口或状态 ping：

- 分别通过 `127.0.0.1:25565` 和 `192.168.1.12:25565` 成功加入，客户端未安装 Forge/Fabric。
- 服务端日志记录到 `UUID of player`、`joined the game`、`logged in with entity id`；`admin.bat list` 返回 `There are 1 of a max of 10 players online`。
- 已验证 `JVM_ARGS` 能正确传递含空格的参数值（用 `jcmd` 读取到对应系统属性），并能拦截 `-jar` 这类会破坏启动命令的参数。
- 当时为 `online-mode=false` 离线模式；客户端测试只用于验收，不改变玩家的正常使用方式。
- 由于测试客户端和服务器在同一台虚拟机内，**仍需用第二台物理电脑做一次跨机验收**，重点确认 VMware 为桥接、路由器未开启 AP 隔离。这最后一步无法在当前单机虚拟机里替你完成。

### 2026-10-25 修复验证（26.1.2 + Via）

- 服务端保持 Paper 26.3 build 218，安装 ViaVersion 5.12.2-SNAPSHOT + ViaBackwards 5.12.2-SNAPSHOT 后重启，日志显示 `ViaVersion detected server version: 26.3 (777)`、`[ViaBackwards] Enabling`。
- 用官方 Minecraft 26.1.2 客户端通过 `--quickPlayMultiplayer 192.168.1.12:25565` 实际进入世界，服务端日志记录 `UUID of player xxxx`、`joined the game`、`logged in with entity id`。
- 之前 26.1.2 卡在“正在连接至服务器...”的根因不是服务端：客户端在连接前请求 `https://sessionserver.mojang.com/blockedservers` 时无限等待。已在 hosts 中把该域名指向 `127.0.0.1`，连接在几秒内完成。
- 26.3 原版客户端之前会卡在模糊全景图、不显示主菜单；日志显示 OpenGL 4.3 / Mesa 23.2 / SVGA3D。根因是 VMware SVGA 驱动缺少 `GL_ARB_buffer_storage` 扩展。已用 Mesa 26.2.4 llvmpipe（软件 OpenGL 4.6，提供该扩展）解决：`launch-client-26.3.bat` 启动后主菜单正常显示，并实际进入服务器（`logged in with entity id 1402`）。llvmpipe 为 CPU 渲染，日常仍推荐帧率更高的 26.1.2。

### 一键备份实测（2026-10-25）

- 服务器停止时备份成功：`backups\mc-backup-20261025-220921.zip`，78 个文件，约 5.27 MB。
- 服务器运行中备份成功：`backups\mc-backup-20261025-221141.zip`；服务端日志依次出现 `Automatic saving is now disabled`、`Saved the game`、`Automatic saving is now enabled`，确认 `save-on` 已恢复。
- 两个 ZIP 均可用资源管理器正常打开；`world/level.dat`、`world/dimensions/minecraft/*/region/`、`config/`、`server.properties` 都在，`session.lock` 已排除。
- 对比 ZIP 内 `server.properties` 与源文件的 SHA256 一致，说明备份内容完整、没有截断。
- 备份过程中未停止服务器，备份结束后服务器继续监听 25565。

### 检查项

- [ ] 双击 `start.bat`，窗口打印本机 IPv4、`IP:25565`、服务端版本（Minecraft 26.3）、加载器（Paper build 218）、最大人数、正版验证状态。
- [ ] 同一局域网另一台电脑能 ping 通房主 IPv4（`ping 192.168.1.12`）。
- [ ] 朋友在 Minecraft「直接连接」输入 `IP:25565` 能进入世界。
- [ ] 服务器窗口出现朋友的加入日志；按 `Tab` 能看到玩家列表。
- [ ] 朋友放置/破坏方块后，房主能看到；重启后世界还在。
- [ ] 修改 `server.env` 的 `MOTD` 或 `MAX_PLAYERS`，重启后生效；其他 `server.properties` 自定义项没有被清掉。
- [ ] 在 `server.env` 的 `JVM_ARGS` 中追加一个自定义参数，重启后启动窗口的“额外 JVM”一行能看到它。
- [ ] 双击 `backup.bat`，窗口提示备份完成，`backups\` 下生成新的 ZIP；服务器运行中备份时会看到 `save-off` 和 `save-on` 的过程。
- [ ] 双击 `stop.bat`，窗口提示“已安全停止”，服务器窗口退出，`run\server.pid` 消失。
- [ ] 再次双击 `start.bat`，世界、玩家数据、插件配置都保留。
- [ ] `firewall.bat -Status` 能看到 25565 放行规则；外部无法访问 25575。
- [ ] 关掉服务器后，25565 不再监听（`netstat -ano | findstr :25565` 无结果）。

---

## H. 常见故障排查

### 1. Java 版本不对 / 找不到 Java

- 现象：`未找到 Java 25 或更高版本`、`Unsupported class file major version`、启动即退出。
- 本方案需要 **Java 25 或更高（64 位）**；Paper 26.3 官方要求 Java 25。
- 脚本会自动搜索 `JAVA_HOME`、PATH、`Program Files\Java`、Eclipse Adoptium、Microsoft JDK、Mojang/PCL 运行时。
- 如果自动检测不到：安装 Temurin/Microsoft Build of OpenJDK 25，然后在 `server.env` 写：

  ```ini
  JAVA_EXE=C:\Program Files\Eclipse Adoptium\jdk-25.x.x-hotspot\bin\java.exe
  ```

- 当前虚拟机里是 Java 27，已实测可启动 Paper 26.3；如果某个插件不兼容 Java 27，再装 Java 25 即可。

### 2. 端口 25565 被占用

- 现象：`端口 25565 已被占用：xxx（PID 1234）`。
- 查占用：

  ```bat
  netstat -ano | findstr :25565
  ```

- 用任务管理器按 PID 结束占用程序，或改 `server.env` 的 `SERVER_PORT`（同时防火墙要放行新端口）。
- 不要同时开两个本方案实例；脚本检测到自己的 PID 会提示“服务器已经在运行”。

### 3. 防火墙拦截

- 现象：本机能进，其他电脑一直“连接超时”。
- 解决：双击 `firewall.bat`，UAC 点“是”；再运行 `firewall.bat -Status` 确认规则存在。
- 第三方安全软件（360、火绒、卡巴斯基）有自己的防火墙，需要单独放行 `java.exe` 或 TCP 25565。
- 检查 Windows 网络类型：`设置 → 网络和 Internet → 状态 → 属性`，建议设为“专用网络”。

### 4. 正版验证失败

- `ONLINE_MODE=true` 时，客户端必须登录微软正版账号；离线登录会被踢。
- `ONLINE_MODE=false` 时，`enforce-secure-profile` 自动为 `false`，否则离线客户端可能因聊天签名失败被踢。
- 切换正版/离线模式会改变玩家 UUID，可能导致原来的背包/权限对不上；确定一种模式后尽量别频繁切换。
- 改完 `server.env` 后必须重启服务器（`stop.bat` → `start.bat`）。

### 5. 版本/模组不一致

- 现象：客户端显示 **`Outdated client! Please use 26.3`**（中文界面为“无法连接至服务器 / 客户端版本过旧”）。
- 原因：ViaVersion / ViaBackwards 没有加载，或者客户端协议比插件支持的范围还旧。正常情况下服务端已装这两个插件，26.1.2 客户端可以进。
- 先确认 `plugins\` 下两个 Via jar 还在，服务端启动日志出现 `ViaVersion detected server version: 26.3 (777)` 和 `[ViaBackwards] Enabling`。
- 解决：关闭游戏 → 在 PCL2 的版本选择里选 **26.1.2** → 启动 → 再连接 `192.168.1.12:25565`。如果仍报旧版，检查是否误删了 Via 插件或用了更老的客户端。
- 服务端 jar 必须是 26.3；启动脚本会检查 jar 内的 `version.json`，不一致会直接报错。
- Paper 服务端不需要客户端装任何模组；如果客户端装了 Forge/Fabric 且加了改变内容的模组，可能进不去或方块异常。
- 用 PCL2 的“版本隔离”给服务器客户端单独建一个干净的 26.3 实例。
- 如果以后改用 Fabric/Forge：服务端和所有客户端必须同加载器、同游戏版本、同模组列表。

### 6. AP 隔离 / 访客网络

- 现象：能 ping 通路由器，但 ping 不通房主电脑；或朋友连不上但房主自己能进。
- 路由器开启了“AP 隔离/客户端隔离/访客网络”，设备之间不能互访。关闭该功能，或把两台电脑接到同一个非访客网络。
- 公司/学校网络常默认隔离，建议用家用路由器。

### 7. VMware 网络模式

- 必须用**桥接（Bridged）**，让虚拟机和宿主机处于同一网段。
- NAT 模式下，局域网其他电脑无法直接访问虚拟机；除非在 VMware 里做端口转发（本方案不涉及公网，仍不推荐）。
- 如果窗口里同时出现 `192.168.x.x` 和 `192.168.56.1`（Host-Only），朋友应填前者，不是 Host-Only 地址。

### 8. 服务器 jar 缺失/损坏

- 双击 `download-server.bat` 重新下载；旧 jar 会备份为 `server.jar.bak-时间戳`。
- 手动下载时确认文件名与 `server.env` 的 `SERVER_JAR` 一致，默认 `server.jar`。
- 下载脚本会校验 SHA256/SHA1，校验失败会删除临时文件，不会覆盖正在用的 jar。

### 9. 关闭窗口导致坏档

- 不要点服务器窗口右上角关闭，也不要在窗口里按 Ctrl+C；请双击 `stop.bat`。
- `stop.bat` 通过 RCON 先 `save-all flush` 再 `stop`，并等待 Java 进程退出。
- 如果 RCON 实在不可用，窗口还开着：切到服务器窗口输入 `stop` 回车。
- 只有窗口完全卡死时才考虑 `stop.bat -Force`；这会强制杀进程，可能损坏世界，风险自负。

### 10. 以后加擂台/插件

- 把插件 jar 放进 `plugins\`，重启服务器即可；插件配置在 `plugins\插件名\`，重启不会丢。
- 常用：WorldGuard（区域保护）、Multiverse-Core（多世界）、EssentialsX（传送/经济）、LuckPerms（权限）、PvPManager（战斗管理）。
- 注意插件要支持 Minecraft 26.3 / Paper 26.3；不兼容的插件会导致启动失败，删掉对应 jar 再启动。
- 用 `admin.bat op 玩家名` 给管理员；不要直接把 `ops.json` 发给别人。

### 11. 日志出现 PaperVersionFetcher / SocketTimeoutException

- 现象：启动日志里出现 `[PaperVersionFetcher] Error while parsing version list`、`SocketTimeoutException` 或 `*** Currently you are N builds behind ***`。
- 这是 Paper 启动时联网检查更新失败或发现有新构建，不影响本地服务器；只要日志已经出现 `Done`、`admin.bat list` 能返回人数，客户端就可以正常连接。
- 本方案不在游戏时自动更新服务端。需要更新时：先 `stop.bat`，再运行 `download-server.bat`。
- 如果不想让它每次联网检查，可停止服务器后把 `config\paper-global.yml` 中的 `update-checker.enabled` 改为 `false`，再启动；这是可选操作。

---

## 安全与维护建议

- 离线模式只适合可信局域网；不要把 25565 映射到公网。
- 定期备份：双击 `backup.bat` 即可；服务器运行中也能备份，脚本会先暂停自动保存并刷盘。备份 ZIP 含 `server.properties`（内有 RCON 密码），不要外传。也可以停止服务器后手动复制 `world`、`plugins`、`config` 等目录到其他盘。
- 不要把 `server.properties` 里的 RCON 密码发给别人；外部 25575 已被防火墙阻断。
- 更新服务端：先 `stop.bat` → `download-server.bat`（会备份旧 jar）→ `start.bat`。
- 本方案不删除世界；会新增/更新本目录文件、`run\server.pid`、Windows 防火墙规则，以及 `hosts` 中的 `127.0.0.1 sessionserver.mojang.com` 一行（离线模式加速连接用，换正版账号时请删除）。
