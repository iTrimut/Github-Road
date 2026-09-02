---
name: GitHub-Road
description: 让普通用户在中国大陆稳定访问 GitHub 官网（hosts 直连 + 动态 IP 择优 + 计划任务自动自愈，免代理、零费用）。当用户说"GitHub 打不开/进不去/连不上/被墙了/超时/连接被重置"、浏览器无法打开 github.com、或之前配过 hosts 但最近又失效、或想一劳永逸随时访问 GitHub 官网时使用。方案经两轮独立第三方审查修正（含黑洞 IP 硬超时、全挂回退 DNS、api 轮换、电池/补跑任务设置、UTF-8 BOM 与弯引号陷阱等）。关键脚本置于 files/，需与 files/ 一起使用。
---

# 🛣️ GitHub-Road：大陆访问 GitHub 官网 · 一键修复 + 自动自愈

> 一句话：照着做 **5 分钟**，GitHub 官网从此稳定可访问，IP 被封锁后**最多 30 分钟自动切换**，不用代理、不花钱。
> 本技能全部步骤在真实环境（Windows 11 中文版、国内网络）验证过，并经过**两轮独立第三方审查**修正（见文末）。

## 何时使用

- 浏览器打不开 `github.com`（一直转圈 / 超时 / 连接被重置 / ERR_CONNECTION_*）
- 之前按某个教程配过 hosts，最近又失效了
- 不想装代理/VPN，希望"随时能打开 GitHub 官网"且长期有效

## 最终效果

| 环节 | 结果 |
|---|---|
| 打开浏览器访问 github.com | 正常打开、可登录、可浏览代码 |
| 当前 IP 被运营商封锁 | 每 30 分钟自动检测并切换，最多 30 分钟内恢复 |
| 需要人工操作 | 仅安装时点一次 UAC「是」 |
| 费用 | 0 元，无代理、无第三方软件 |

---

## 方案原理（为什么这样能"固定住"）

**问题本质**：运营商对 `github.com` 按 **IP 做 TLS/SNI 层封锁**——TCP 443 能连上，但 TLS 握手被掐断；而且**封锁的 IP 集合会随时间轮换**（实测：某个 IP 可能几十分钟~几天后被封锁，过一阵又恢复）。所以"写死一个 IP 到 hosts"注定过段时间失效——这正是用户"之前设置过、最近又打不开"的原因。

**对策 = hosts 直连 + 双重验证择优 + 定时自愈**：

1. **双重验证选 IP**：对候选 IP 先做 TLS 握手（**连接 8 秒硬超时**防黑洞 IP 挂死，握手后**校验证书由 GitHub 签发**），再对通过的 IP 发真实 HTTPS 请求，**必须返回 HTTP 200**——因为有些节点握手正常但返回 400/404（错误前端），只测 TLS 会选错。
2. **写入 hosts 并刷新 DNS**：整文件读改写（保留 Tailscale/公司 VPN 等其它条目）→ 自动备份 → `ipconfig /flushdns` → curl 实测。
3. **计划任务自愈**：每 30 分钟重跑（**允许电池运行、错过补跑、并发新实例忽略**），封锁轮换后自动跟上。
4. **全部失败时回退 DNS**：不钉死坏 IP——临时注释 hosts 条目，下次运行自动恢复（避免"钉住一个坏 IP"的失明问题）。

**为什么不直接用代理/加速器**：本方案零安装、零费用、不改系统代理设置、不影响其它网站；缺点是解决不了被"重点盯防"的少数域名（见"局限性"）。

---

## 前置条件

- Windows 10/11，当前账号是管理员（家庭版默认即是；非管理员需要能提供管理员账号）
- `curl.exe` 存在（Win10 1803+ 自带，`C:\Windows\system32\curl.exe`；可 `curl.exe --version` 验证）
- 网络本身正常（能打开百度等国内网站）。若整体断网，本方案无效，先查网络

---

## 安装（普通用户 5 分钟）

1. 把本技能 `files/` 里的 **`fix-github.ps1`** 和 **`install-github-fix.ps1`** 复制到同一个文件夹，**路径不要含空格**（如 `D:\GitHubRoad\`）
2. **双击 `install-github-fix.ps1`** → 出现 UAC 弹窗 → 点**「是」**
3. 黑色窗口自动完成两步（立即修复 + 注册计划任务），约 1~3 分钟，**跑完自动关闭，无需按键**
4. 打开浏览器访问 `https://github.com`；若打不开，**重启浏览器**或按 `Ctrl+F5` 强制刷新（浏览器会缓存旧 DNS）

验证任务已注册：

```cmd
schtasks /query /tn DSH-GitHubFix
```

显示 `Ready`、`Next Run Time` 在未来即成功。（任务设置：每 30 分钟、最高权限、隐藏窗口、允许电池、错过补跑、仅当前用户登录时运行。）

## 手动单次修复（不装自动任务时）

- 双击 `fix-github.ps1` → UAC 点「是」→ 看结果 → 按回车退出
- 或命令行：`powershell -ExecutionPolicy Bypass -File fix-github.ps1`

## 卸载

- 双击 `files/uninstall-github-fix.ps1` → UAC 点「是」→ 删除计划任务（hosts 条目保留，保持当前可用；想彻底还原就按提示手动删两行或还原 `%USERPROFILE%\hosts.backup-*`）

---

## ✅ 验证清单（做完逐项打勾）

- [ ] `curl.exe -s -o NUL -w "%{http_code}" https://github.com` 返回 `200`
- [ ] `schtasks /query /tn DSH-GitHubFix` 显示 `Ready`，Next Run Time 在未来
- [ ] 浏览器（重启后）能打开 github.com 并登录
- [ ] 运行记录在脚本同目录 `github-fix.log`（每次自动运行追加一行）

## ⚠️ 常见问题排查表（全部实战验证 / 审查确认）

| # | 现象 | 原因 | 解法 |
|---|---|---|---|
| 1 | 双击脚本报解析错误 / 没反应 | 中文 Windows 的 PowerShell 5.1 把**无 BOM 的 UTF-8** 脚本按 GBK 解析，报"缺少右括号"类错误 | 脚本必须 **UTF-8 带 BOM**（本技能 files/ 里的已是；用记事本改过就另存为"UTF-8 with BOM"） |
| 2 | 脚本报 MissingEndCurlyBrace | 脚本正文里有**弯引号** `"` `"` `'` `'`（U+201C/201D/2018/2019），PowerShell 把它们当引号处理破坏解析 | 中文引号一律用「」或【】，不要用弯引号 |
| 3 | UAC 弹窗被取消/没看到 | 弹窗出现但没及时点 | 重新运行脚本，留意屏幕弹窗点「是」 |
| 4 | 验证时 TLS 通过但网页 400/404 | 该 IP 是错误前端（握手正常但不服务 github.com） | 脚本已做真实 HTTP 200 验证自动跳过；手动测：`curl --resolve github.com:443:<IP> https://github.com` |
| 5 | 今天能用，过几天又打不开 | IP 封锁轮换，当前 hosts IP 被封锁 | 正常现象：等计划任务自动切换（最多 30 分钟），或双击 fix-github.ps1 立即修复 |
| 6 | 改了 hosts 浏览器还是打不开 | 浏览器/系统 DNS 缓存 | `ipconfig /flushdns`；**重启浏览器**或 Ctrl+F5。Windows 上 hosts 优先级高于浏览器安全 DNS（DoH），DoH 不是原因 |
| 7 | 计划任务显示"Interactive only" | 任务只在用户登录时运行（设计如此） | 正常：用户在用电脑时才能浏览，登录后任务自动恢复 30 分钟节奏；笔记本记得插电（已设允许电池，但系统休眠时不运行） |
| 8 | 计划任务运行失败，Last Result 显示 -1073741502（0xC0000142） | `powershell.exe -WindowStyle Hidden` 在计划任务环境启动崩溃（STATUS_DLL_INIT_FAILED，PS 5.1 已知问题） | 本技能已改用 `wscript.exe + fix-github-quiet.vbs` 静默启动（files/ 已含）；重跑 install-github-fix.ps1 即修复 |
| 8 | 所有候选 IP 全挂（罕见） | 网络环境整体封锁 / 候选 IP 列表过时 | 脚本会**自动注释 hosts 条目回退 DNS** 并提示改用代理；可更新脚本中的 `$githubCandidates`（见"局限性"） |
| 9 | gist.github.com 打不开 | gist 的 SNI 被运营商层阻断，**所有 IP 都连不上** | hosts 方案无法修复；需要用代理。不影响官网主站 |
| 10 | 下载 GitHub Desktop / 部分下载链接失败 | 部分域名（如 github.global.ssl.fastly.net）DNS 被污染指向 Facebook IP | 官网浏览不受影响；下载类需求需代理 |
| 11 | 脚本文件夹路径含空格 | 任务命令引号嵌套易出错 | 把文件夹移到无空格路径后重装 |
| 12 | 装了杀毒软件/安全软件后失效 | 部分 AV 有"hosts 文件保护"，拦截修改 | 在 AV 里放行 hosts 修改（或把 fix-github.ps1 加入信任） |
| 13 | 开着代理/TUN 模式（Clash 等）仍打不开 | TUN/系统代理接管了流量，hosts 直连被绕过或冲突 | 用代理时不需要本方案；关掉代理后 hosts 生效。公司 VPN（如 aTrustAgent）会在 hosts 加自己的条目，不影响本方案的两行。若系统设置了 HTTPS_PROXY 环境变量，脚本的 curl 测试已用 `--noproxy "*"` 忽略代理，不会测到假结果 |
| 14 | 手动改过 hosts 想还原 | — | 用 `%USERPROFILE%\hosts.backup-*`（脚本每次改前自动备份，时间戳命名，保留多份） |
| 15 | 公司 VPN 带 TLS 检查（如 Sangfor aTrust） | 检查型代理可能改写 TLS 证书，脚本的证书校验会看到"假 github 证书" | 这种情况通常说明公司网关已接管流量，hosts 方案意义不大；与网管确认后再用本方案 |
| 16 | GitHub 突然打不开，hosts 里出现 `# Steam++ Start`…`127.0.0.1 github.com`…`# Steam++ End` 整段 | **Watt Toolkit (Steam++)** 的本地代理加速把 github/steam/youtube 等指到 127.0.0.1（它监听 80/444，但不服务 HTTPS 的 443），并持续重写 hosts，与本技能自愈任务冲突（修了又被改回） | 一键处理：双击 `files/quit-watt-and-fix.ps1`（退出 Watt + 清理 hosts + 重跑修复，需一次 UAC）；或手动退出 Watt Toolkit（任务管理器结束 `Steam++.Accelerator`/`Steam++`）后重跑修复；本脚本最终验证已改用**真实 hosts 路径**（不用 `--resolve` 绕过），冲突时会明确报"127.0.0.1 屏蔽行抢先生效" |

## 🔒 安全说明

- `fix-github.ps1` 以**管理员权限**运行并每 30 分钟自动执行：**不要修改 files/ 里的脚本内容**（被篡改=定时执行任意管理员命令）；只从本技能目录获取脚本
- **脚本所在文件夹建议设为仅管理员可写**（30 分钟定时以管理员身份运行 = 常驻管理员执行入口，普通用户可写目录有被植入风险）：`icacls "D:\GitHubRoad" /inheritance:r /grant:r "Administrators:(OI)(CI)F" "Users:(OI)(CI)RX"`
- 脚本只改动 hosts 中 `github.com`/`api.github.com` 两行，整文件读改写（**先写临时文件再原子替换**），**保留** Tailscale MagicDNS、公司 VPN 等其它条目
- hosts 每次修改前自动备份到 `%USERPROFILE%\hosts.backup-时间戳`（保留多份）
- 日志 `github-fix.log` 仅记录时间与结果，不含敏感信息；超过 1MB 自动轮转为 `github-fix.log.old`

## ⚠️ 局限性（如实说明，别对用户过度承诺）

- **gist.github.com**：SNI 被运营商层阻断，hosts 修复不了，需要代理
- **候选 IP 列表**（脚本中 `$githubCandidates`）是手工维护的；GitHub 的 Azure 段偶尔变化。刷新方法：`nslookup github.com` 拿到新 IP 后，用 `curl --resolve github.com:443:<IP> https://github.com` 逐个实测 HTTP 200，把能用的加进列表。全部失效时脚本会回退 DNS（第 8 行排查表），不会钉死坏 IP
- 本方案只保证**官网访问**（网页、登录、浏览、release 下载走 objects.githubusercontent.com 一般可用）；`codeload.github.com`（下载源码压缩包）和 `ssh github.com:22`（Git 推送）**不在本方案覆盖范围**——SSH 推送被墙请用 `dsh-GitRoad` 技能的 SSH over 443 方案；GitHub Desktop 安装包、部分直链仍需代理
- 若运营商升级为"对 github.com 全量封锁"（所有 IP 的 TLS 全挂），本方案会如实报告失败并建议代理——不承诺万无一失

## 🔎 第三方审查记录（两轮独立审查）

> 结论：**可行**（两轮均为 "feasible with fixes" / "works with caveats"），已按审查意见修正，无阻断性问题。

| 审查发现 | 处理 |
|---|---|
| 全挂时留着坏 IP + 备份被坏条目覆盖 | ✅ 全挂时注释 hosts 条目回退 DNS；备份改为时间戳多份 |
| 黑洞 IP（静默丢包）让同步 Connect 挂 21 秒 | ✅ 连接阶段 8 秒硬超时（ConnectAsync.Wait）+ TLS 流超时 10 秒 |
| 计划任务默认"仅交流电运行"（笔记本电池时不跑） | ✅ 安装脚本改用 Register-ScheduledTask：允许电池、错过补跑、并发忽略、30 分钟运行时限 |
| api.github.com 只修不轮换 | ✅ api 也做双重验证 + 择优轮换 |
| 异步 TLS 回调在 PS 5.1 无运行空间（实测报错） | ✅ 改用同步握手 + 握手后证书域名校验 |
| TLS 通过但 HTTP 400/404（错误前端） | ✅ 双重验证：真实 HTTPS 必须 200 |
| 浏览器安全 DNS（DoH）绕过 hosts 的疑虑 | ✅ Windows 上 hosts 优先于 DoH；已写入排查表 |
| 脚本以管理员身份每 30 分钟运行的安全性 | ✅ 安全说明：禁止改动脚本内容；建议 icacls 收紧脚本目录权限 |
| 代理环境变量（HTTPS_PROXY）污染 curl 测试 | ✅ curl 全部加 `--noproxy "*"` + `--connect-timeout 8` |
| hosts 并发读写可能读到半截文件 | ✅ 原子写入（临时文件 + Move-Item 替换） |
| 日志无限增长 | ✅ 超过 1MB 自动轮转为 .old |
| 覆盖范围模糊（codeload / ssh 22） | ✅ 局限性中明确标注，SSH 推送指引到 dsh-GitRoad |
| **陈旧固定 IP 失明**（比较 DNS 解析结果而非 hosts 实际固定值；最终验证失败只提示不修复、退出码 0） | ✅ 新增 `Get-HostsPin` 直接读取 hosts 实际固定 IP；最终验证失败自动轮换次优 IP 重写，全败回退 DNS 并退出非 0 |
| 自我提权时丢失 `-Quiet`（提权重启后卡在等待回车） | ✅ 提权重启参数透传 `-Quiet` |
| 旧 .NET 协商 TLS 1.0/1.1 被 GitHub 拒绝 → 误判"全部不可用" | ✅ 强制 TLS 1.2（SslProtocols.Tls12） |
| hosts 备份无限堆积（每天 ~48 份） | ✅ 仅保留最近 20 份 |
| api.github.com 最终未验证（只在中间环节测） | ✅ 4.3 增加 api 最终确认（失败仅提示不阻塞） |
| **原生命令 stderr + ErrorActionPreference=Stop 导致 curl 超时时脚本静默崩溃**（实测 FATAL: curl timed out @line 190，网络差时每次自动运行都会死） | ✅ curl 全部改 `-s`（全静默，错误只体现在退出码/HTTP 码）；新增全局 `trap` 兜底，任何未捕获错误都写入日志（否则静默退出无法排查） |
| **RepetitionDuration 用 `[TimeSpan]::MaxValue` / `PT0S` 被 Task Scheduler 拒绝**（P99999999DT23H59M59S out of range → Register-ScheduledTask 静默失败、回退 schtasks 丢失电池设置） | ✅ 改用 365 天（P365D，实测通过）；到期重跑安装脚本续期 |
| **计划任务用 `powershell -WindowStyle Hidden` 偶发 0xC0000142 崩溃**（实测 Last Result -1073741502） | ✅ 任务动作改为 `wscript.exe` + `fix-github-quiet.vbs`（无控制台，实测 Last Result 0） |

## 📁 参考实现（files/ 自带脚本）

| 文件 | 用途 | 说明 |
|---|---|---|
| `fix-github.ps1` | 单次修复/自愈核心 | 双重验证选 IP（TLS 硬超时+TLS1.2+证书校验 → HTTP 200）→ 写 hosts → 刷新 DNS → 最终实测（失败自动轮换次优 IP，全败回退 DNS）；以 hosts 实际固定值为比较基准（Get-HostsPin）；curl 全静默（-s）防 EAP=Stop 崩溃 + 全局 trap 兜底记录；支持 `-Quiet`（自动记日志、日志轮转）；并发防重入锁；备份仅留 20 份 |
| `install-github-fix.ps1` | 一键安装 | 立即修复 + 注册计划任务（Register-ScheduledTask：允许电池、错过补跑、忽略并发、30 分钟运行时限；失败自动回退 schtasks）；可参数 `-TaskName`/`-Minutes` |
| `fix-github-quiet.vbs` | 静默启动器 | 计划任务通过 wscript.exe 调用它（窗口样式 0），再启动 fix-github.ps1 -Quiet；**纯 ASCII**（wscript 按 ANSI 解析，别加中文注释） |
| `uninstall-github-fix.ps1` | 卸载 | 删除计划任务（优先 Unregister-ScheduledTask），保留当前 hosts 条目 |
| `quit-watt-and-fix.ps1` | Watt 冲突一键处理 | 退出 Watt Toolkit/Steam++ 进程 → 清理其 hosts 段 → 重跑修复（真实 hosts 路径验证）；需一次 UAC |

所有脚本均为 **UTF-8 带 BOM**、纯 ASCII 引号、无弯引号，Windows PowerShell 5.1 直接可跑。
