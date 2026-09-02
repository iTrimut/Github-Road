# 🛣️ GitHub-Road

让普通用户在中国大陆**稳定访问 GitHub 官网**：**hosts 直连 + 动态 IP 择优 + 计划任务自动自愈**，免代理、零费用。

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![GitHub](https://img.shields.io/badge/github-GitHub--Road-blue)](https://github.com/iTrimut/GitHub-Road)

---

## 它是做什么的 / What it does

浏览器打不开 `github.com`（转圈/超时/连接被重置）？运营商对 GitHub 按 IP 做 TLS/SNI 层封锁，且**封锁的 IP 集合会随时间轮换**——所以"写死一个 IP 到 hosts"注定过段时间失效。本方案：

1. **双重验证选 IP**：候选 IP 先过 TLS 握手（8 秒硬超时 + TLS 1.2 + 证书域名校验），再发真实 HTTPS 请求，**必须返回 HTTP 200** 才算可用（避免选到握手正常但返回 400/404 的错误前端）。
2. **写入 hosts 并刷新 DNS**：自动备份、原子写入、保留 Tailscale/公司 VPN 等其它条目。
3. **计划任务自愈**：每 30 分钟自动重跑，当前 IP 被封锁后**最多 30 分钟自动切换**。
4. **全挂回退 DNS**：所有候选都不可用时临时注释 hosts 条目，不钉死坏 IP。

方案经**两轮独立第三方审查**修正，全部步骤在真实环境（Windows 11 中文版、国内网络）验证。

---

## 仓库结构 / Structure

```
GitHub-Road/
├── skills/GitHub-Road/  # Agent Skill（标准格式）：SKILL.md + files/（PowerShell 脚本）
├── install.sh               # 多智能体一键安装脚本
├── package.json             # DeepSeek Harness 插件包元数据（npm）
├── index.js                 # 插件入口（skills-only，无运行时代码）
├── cordis.patch.yml         # 插件注册补丁
├── README.md
└── LICENSE
```

---

## 安装 / Install

### 方式一：DeepSeek Harness (DSH) 插件安装

```bash
dsh plugin --profile web add github:iTrimut/GitHub-Road
```

重启 dsh web，确认技能已生成：

```bash
ls "%USERPROFILE%\.dsh\skills\GitHub-Road\SKILL.md"
```

之后让 dsh 代理执行技能即可。

### 方式二：任意智能体一键安装

```bash
git clone https://github.com/iTrimut/GitHub-Road.git
cd GitHub-Road
bash install.sh                  # 自动检测当前智能体并安装
bash install.sh --user           # 用户级安装（所有项目可用）
bash install.sh --agent claude   # 或指定智能体
```

或手动把 `skills/GitHub-Road/` 复制到所用智能体的 skills 目录：

| 智能体 | 安装路径 |
|--------|----------|
| Claude Code | `.claude/skills/GitHub-Road/` |
| DeepSeek Harness (DSH) | `~/.dsh/skills/GitHub-Road/` |
| Cursor | `.cursor/skills/GitHub-Road/` |
| Windsurf | `.windsurf/skills/GitHub-Road/` |
| GitHub Copilot | `.github/skills/GitHub-Road/` |
| OpenCode / Codex | `.opencode/skills/GitHub-Road/` / `.codex/skills/GitHub-Road/` |

### 方式三：纯手动运行（不依赖任何智能体）

1. 从本仓库 `skills/GitHub-Road/files/` 下载 `fix-github.ps1`、`install-github-fix.ps1`、`fix-github-quiet.vbs` 到同一个文件夹（**路径不要含空格**，如 `D:\GitHubRoad\`）。
2. 双击 `install-github-fix.ps1` → UAC 弹窗点「是」。
3. 黑色窗口自动完成：立即修复 + 注册每 30 分钟的计划任务（隐藏窗口，允许电池、错过补跑）。
4. 重启浏览器（或 Ctrl+F5）访问 https://github.com。

### 卸载 / Uninstall

双击 `uninstall-github-fix.ps1`（删除计划任务，保留当前 hosts 条目）。

---

## 验证 / Verify

```powershell
curl.exe -s -o NUL -w "%{http_code}" https://github.com   # 期望 200
schtasks /query /tn DSH-GitHubFix                           # 期望 Ready，Next Run 在未来
```

---

## 已知限制 / Limitations（如实说明）

- **gist.github.com**：SNI 被运营商层阻断，**所有 IP 都连不上**，hosts 无法修复，需要代理。
- **codeload.github.com**（下载源码压缩包）、**ssh github.com:22**（Git 推送）、**GitHub Desktop 安装包**：不在本方案覆盖范围。Git 推送被墙请用 SSH over 443（见 dsh-GitRoad）。
- **候选 IP 列表**是手工维护的；GitHub 的 Azure 段偶尔变化，全部失效时脚本自动回退 DNS 并提示。可更新脚本中 `$githubCandidates`（用 `nslookup github.com` + 逐 IP 实测 HTTP 200）。
- **与 hosts 管理类工具互斥**：若机器装有 Watt Toolkit / Steam++（本地代理加速把 github 指到 127.0.0.1 并持续重写 hosts），会与本方案互相覆盖。需先停用其加速或退出（一键处理：`files/quit-watt-and-fix.ps1`），详见 SKILL.md 排查表 #16。
- 若运营商升级为"对 github.com 全量封锁"，本方案会如实报告失败并建议代理——**不承诺万无一失**。

---

## 安全说明 / Security

- 脚本以**管理员权限**运行并每 30 分钟自动执行：**不要修改脚本内容**（被篡改 = 定时执行任意管理员命令）；只从本仓库获取脚本。
- 建议把脚本所在文件夹设为仅管理员可写：
  `icacls "D:\GitHubRoad" /inheritance:r /grant:r "Administrators:(OI)(CI)F" "Users:(OI)(CI)RX"`
- hosts 每次修改前自动备份到 `%USERPROFILE%\hosts.backup-*`（保留最近 20 份）。
- 所有脚本 **UTF-8 带 BOM**、纯 ASCII 引号（Windows PowerShell 5.1 直接可跑）。

---

## 免责声明 / Disclaimer

本工具仅用于个人学习与开发环境的网络配置（等价于常见的 hosts 加速工具）。请在遵守当地法律法规的前提下使用；**不建议用于公司/受管设备**，大规模分发可能面临法律风险。本项目与 GitHub 官方无关。

---

## 文档 / Docs

完整操作手册、排查表与审查记录见 `skills/GitHub-Road/SKILL.md`（安装技能后随技能加载）。
