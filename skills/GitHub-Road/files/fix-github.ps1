# ============================================================
# fix-github.ps1 —— 一键修复 GitHub 官网访问（hosts 直连 + 动态择优 + 自动自愈）
# 用法：双击运行，或 powershell -ExecutionPolicy Bypass -File fix-github.ps1
# 原理：
#   1. 检测当前 github.com / api.github.com 指向的 IP 是否可用
#   2. 对候选 IP 双重验证：TLS 握手（硬超时 + 证书域名校验）→ 真实 HTTPS 请求必须 HTTP 200
#   3. 挑最快可用 IP 写入 hosts（自动备份 + 自动提权），刷新 DNS 缓存并实测
#   4. 全部失败时临时注释 hosts 条目、回退 DNS，避免钉死一个坏 IP
# 注意：
#   - 本文件必须保存为 UTF-8 带 BOM（否则中文 Windows 的 PowerShell 5.1 会解析失败）
#   - 正文不要使用弯引号字符（U+201C/201D/2018/2019），它们会被 PowerShell 当作引号破坏解析
#   - gist.github.com 的 SNI 被运营商层阻断，hosts 无法修复，需要代理
# ============================================================

param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
# 全局兜底：任何未捕获的终止性错误都记录下来（否则脚本会静默退出、无法排查）
trap {
    try { "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] FATAL: $($_.Exception.Message) @line $($_.InvocationInfo.ScriptLineNumber)" | Out-File -FilePath (Join-Path $PSScriptRoot 'github-fix.log') -Append -Encoding utf8 } catch {}
    Remove-Item (Join-Path $env:TEMP 'dsh-github-fix.lock') -Force -ErrorAction SilentlyContinue
    exit 1
}
$HOSTS  = 'C:\Windows\System32\drivers\etc\hosts'
$sni    = 'github.com'
$LOG    = Join-Path $PSScriptRoot 'github-fix.log'
$lockFile = Join-Path $env:TEMP 'dsh-github-fix.lock'

function Write-Step($m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "[OK] $m" -ForegroundColor Green }
function Write-Fail($m) { Write-Host "[!!] $m" -ForegroundColor Red }
function Wait-Exit { if (-not $Quiet) { Read-Host '按回车退出' } }
function Log($m) {
    if (-not $Quiet) { return }
    try { if ((Test-Path $LOG) -and (Get-Item $LOG).Length -gt 1MB) { Move-Item $LOG "$LOG.old" -Force -ErrorAction SilentlyContinue } } catch {}
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" | Out-File -FilePath $LOG -Append -Encoding utf8
}
function Remove-Lock { Remove-Item $lockFile -Force -ErrorAction SilentlyContinue }
# 原子写 hosts：先写临时文件再 Move-Item 覆盖，避免并发读取到半截文件
function Write-HostsFile([string[]]$lines) {
    $tmp = "$HOSTS.dsh-tmp"
    [System.IO.File]::WriteAllLines($tmp, $lines, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -Path $tmp -Destination $HOSTS -Force
}

# ---------- 0. 并发防重入（计划任务每 30 分钟一次，防止上次还没跑完又开一次） ----------
if (Test-Path $lockFile) {
    $oldPid = 0
    try { $oldPid = [int](Get-Content $lockFile -Raw) } catch { $oldPid = 0 }
    if ($oldPid -gt 0 -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) {
        Write-Step "已有实例在运行（PID $oldPid），本次跳过。"
        exit 0
    }
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
}
[System.IO.File]::WriteAllText($lockFile, [string]$PID)

# ---------- 1. 自我提权（改 hosts 需要管理员） ----------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Step '需要管理员权限，正在请求提权 —— 请在弹窗（UAC）中点击「是」…'
    $qArg = ''; if ($Quiet) { $qArg = ' -Quiet' }
    $p = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"$qArg" -Verb RunAs -Wait -PassThru
    Remove-Lock
    exit $p.ExitCode
}

# ---------- 2. TLS 握手测试（连接 5 秒硬超时 + 握手后证书域名校验） ----------
# 注意：不要用 BeginAuthenticateAsClient 异步版 —— PS 5.1 的脚本块回调在 .NET 线程池线程
#       上没有运行空间，会报 "No runspace available" 直接失败。用同步握手 + 流超时即可。
function Test-GitHubTls([string]$ip, [string]$hostName) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        # 连接阶段：8 秒硬超时（黑洞 IP 会静默丢包，同步 Connect 可能挂 21 秒；太紧会误伤抖动网络）
        if (-not $tcp.ConnectAsync($ip, 443).Wait(8000)) {
            return [pscustomobject]@{ Ip = $ip; Ok = $false; Ms = -1 }
        }
        # TLS 阶段：流超时 10 秒（太紧会误伤抖动中的正常连接，实测正常握手 <1s）
        $tcp.ReceiveTimeout = 10000
        $tcp.SendTimeout = 10000
        $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, { $true })
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        # 强制 TLS 1.2：避免旧 .NET 协商到 1.0/1.1 被 GitHub 拒绝导致误判"全部不可用"
        $ssl.AuthenticateAsClient($hostName, $null, [System.Security.Authentication.SslProtocols]::Tls12, $false)
        $sw.Stop()
        # 握手后校验：证书必须由 GitHub 签发（*.github.com / *.github.io），防误连错误前端
        $cert = $ssl.RemoteCertificate
        if ($null -eq $cert -or $cert.Subject -notmatch 'github') {
            return [pscustomobject]@{ Ip = $ip; Ok = $false; Ms = -1 }
        }
        return [pscustomobject]@{ Ip = $ip; Ok = $true; Ms = $sw.ElapsedMilliseconds }
    } catch {
        return [pscustomobject]@{ Ip = $ip; Ok = $false; Ms = -1 }
    } finally {
        $tcp.Close()
    }
}

# 候选 IP（GitHub 常用段：Azure 亚太 20.205/20.27 较快，美国段 140.82 兜底；封锁会轮换，多备几个）
$githubCandidates = @(
    '20.27.177.113','20.27.177.114','20.27.177.115','20.27.177.116',
    '20.205.243.166','20.205.243.168','20.205.243.169','20.205.243.170',
    '140.82.112.4','140.82.113.3','140.82.113.4','140.82.114.3','140.82.114.4',
    '140.82.116.3','140.82.121.3','140.82.121.4','140.82.112.3'
)
$apiCandidates = @(
    '140.82.112.6','140.82.113.6','140.82.114.6','140.82.116.6','140.82.121.6','20.205.243.166'
)

# ---------- 3. hosts 读写（整文件读改写，保留 Tailscale/公司 VPN 等其它条目） ----------
# 读取 hosts 中实际固定的 IP（不依赖 DNS 解析器行为，避免"固定了死 IP 却拿 DNS 结果比较"的失明）
function Get-HostsPin([string]$hostName) {
    if (-not (Test-Path $HOSTS)) { return $null }
    foreach ($line in [System.IO.File]::ReadAllLines($HOSTS)) {
        if ($line -match "(?i)^\s*(\d{1,3}\.){3}\d{1,3}\s+$hostName\s*$") {
            return (($line -split '\s+')[0])
        }
    }
    return $null
}

# 幂等管理：先移除该主机名下所有旧条目（含历史注释残留与 127.0.0.1 屏蔽行），再写一条干净的受管行。
# 修复：旧版只追加不清理，在封锁轮换时会累积几十条重复注释行污染 hosts。
function Set-HostsManagedEntry([string]$hostName, [string]$newIp) {
    if (-not (Test-Path $HOSTS)) { throw "找不到 hosts 文件: $HOSTS" }
    $bak = "$env:USERPROFILE\hosts.backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item $HOSTS $bak -Force
    Write-Ok "已备份旧 hosts 到 $bak"
    Get-ChildItem "$env:USERPROFILE\hosts.backup-*" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -Skip 20 |
        Remove-Item -Force -ErrorAction SilentlyContinue

    $kept = New-Object System.Collections.Generic.List[string]
    foreach ($line in [System.IO.File]::ReadAllLines($HOSTS)) {
        # 移除该主机名下任何旧条目：`[#] IP hostname [# 注释]`（含 127.0.0.1 屏蔽行、历史注释残留）
        if ($line -match "(?i)^\s*#?\s*(\d{1,3}\.){3}\d{1,3}\s+$hostName(\s|#|$)") { continue }
        # 移除 dsh 管理标记行（防重复累积）
        if ($line -match '(?i)^\s*#\s*dsh github') { continue }
        $kept.Add($line)
    }
    if ($newIp) {
        $kept.Add("# dsh github direct fix")
        $kept.Add("$newIp $hostName")
    }
    Write-HostsFile ($kept.ToArray())
    if ($newIp) { Write-Ok "hosts 已更新: $hostName -> $newIp（旧条目已清理）" }
    else { Write-Fail "hosts 已移除 $hostName 条目，回退到 DNS 解析" }
}

function Update-HostsEntry([string]$hostName, [string]$newIp) { Set-HostsManagedEntry $hostName $newIp }
function Disable-HostsEntry([string]$hostName) { Set-HostsManagedEntry $hostName $null }

# ---------- 4. 主流程 ----------
Log "fix-github start (pid $PID, quiet=$Quiet)"
Write-Step '开始检测 GitHub 访问…'

# 4.1 github.com：以 hosts 实际固定 IP 为当前值（无固定则回退 DNS），双重验证后挑最快写入
$cur = Get-HostsPin 'github.com'
if (-not $cur) {
    $cur = (Resolve-DnsName github.com -Type A -ErrorAction SilentlyContinue | Where-Object Type -eq 'A' | Select-Object -First 1 -ExpandProperty IPAddress)
}
$results = @()
if ($cur) {
    Write-Step "当前 github.com 指向: $cur"
    $results += Test-GitHubTls $cur $sni
}
Write-Step '逐个测试候选 IP…'
$results += @($githubCandidates | ForEach-Object { Test-GitHubTls $_ $sni })
$ok = @($results | Where-Object Ok | Sort-Object Ms)
if ($ok.Count -eq 0) {
    Write-Fail '所有候选 IP 的 TLS 握手均失败 —— 可能是网络环境整体封锁，请改用代理/VPN。'
    Log 'fix-github: ALL TLS FAILED - network may be fully blocked'
    Wait-Exit
    Remove-Lock
    exit 1
}
# TLS 通过还不够（有的节点握手正常但返回 400/404），用真实 HTTPS 请求挑真正能打开网页的
Write-Step '对 TLS 通过的 IP 做真实 HTTPS 验证…'
$verified = @()
foreach ($ip in ($ok | Select-Object -ExpandProperty Ip)) {
    $code = & curl.exe -s -o NUL -w "%{http_code}" --noproxy "*" --connect-timeout 8 --max-time 10 --resolve "github.com:443:$ip" https://github.com 2>$null
    Write-Step "  $ip -> HTTP $code"
    if ($code -eq '200') { $verified += ($ok | Where-Object Ip -eq $ip) }
}
if ($verified.Count -eq 0) {
    Write-Fail '所有候选 IP 都打不开 github.com —— 临时回退 DNS，稍后自动重试。'
    Log 'fix-github: NO IP returned HTTP 200 - disabled hosts pin, fallback to DNS'
    Disable-HostsEntry 'github.com'
    Wait-Exit
    Remove-Lock
    exit 1
}
$best = $verified | Sort-Object Ms | Select-Object -First 1
if ($best.Ip -ne $cur) {
    Write-Ok "最快可用 IP: $($best.Ip)（HTTP 200，TLS $($best.Ms)ms），当前是 $cur，正在更新 hosts…"
    Update-HostsEntry 'github.com' $best.Ip
} else {
    Write-Ok "当前 IP $cur 已验证可用（HTTP 200），无需修改"
}

# 4.2 api.github.com（同样双重验证 + 择优，避免登录/API 接口被钉死）
$curApi = Get-HostsPin 'api.github.com'
if (-not $curApi) {
    $curApi = (Resolve-DnsName api.github.com -Type A -ErrorAction SilentlyContinue | Where-Object Type -eq 'A' | Select-Object -First 1 -ExpandProperty IPAddress)
}
$resultsApi = @()
if ($curApi) {
    Write-Step "当前 api.github.com 指向: $curApi"
    $resultsApi += Test-GitHubTls $curApi 'api.github.com'
}
$resultsApi += @($apiCandidates | ForEach-Object { Test-GitHubTls $_ 'api.github.com' })
$okApi = @($resultsApi | Where-Object Ok | Sort-Object Ms)
$verifiedApi = @()
foreach ($ip in ($okApi | Select-Object -ExpandProperty Ip)) {
    $codeApi = & curl.exe -s -o NUL -w "%{http_code}" --noproxy "*" --connect-timeout 8 --max-time 10 --resolve "api.github.com:443:$ip" https://api.github.com 2>$null
    Write-Step "  api $ip -> HTTP $codeApi"
    if ($codeApi -eq '200') { $verifiedApi += ($okApi | Where-Object Ip -eq $ip) }
}
if ($verifiedApi.Count -gt 0) {
    $bestApi = $verifiedApi | Sort-Object Ms | Select-Object -First 1
    if ($bestApi.Ip -ne $curApi) {
        Write-Ok "api.github.com 最快可用 IP: $($bestApi.Ip)，正在更新 hosts…"
        Update-HostsEntry 'api.github.com' $bestApi.Ip
    } else {
        Write-Ok "api.github.com 当前 IP $curApi 已验证可用（HTTP 200），无需修改"
    }
} else {
    Write-Fail 'api.github.com 没有可用 IP（一般不影响网页浏览，稍后自动重试）'
    Disable-HostsEntry 'api.github.com'
}

# 4.3 写入 pin 后做【真实 hosts 路径】最终验证。
# 修复：旧版用 --resolve 绕过 hosts 直连 IP，即使 hosts 被 Steam++/Watt 等写成 127.0.0.1 也会误报 200。
$finalOk = $false
$code = '000'
ipconfig /flushdns | Out-Null
Start-Sleep -Milliseconds 500
# 4.3.1 选一个可用 IP 写入 hosts（幂等：清理该域名旧条目后写一条 pin）
foreach ($ip in ($verified | Sort-Object Ms | Select-Object -ExpandProperty Ip)) {
    $probe = & curl.exe -s -o NUL -w "%{http_code}" --noproxy "*" --connect-timeout 8 --max-time 15 --resolve "github.com:443:$ip" https://github.com 2>$null
    Write-Step "  候选直连 $ip -> HTTP $probe"
    if ($probe -eq '200') {
        Update-HostsEntry 'github.com' $ip
        break
    }
}
# 4.3.2 真实走 hosts 验证（不带 --resolve；若 hosts 有更早的 127.0.0.1 屏蔽行会在此失败）
ipconfig /flushdns | Out-Null
Start-Sleep -Milliseconds 800
$code = & curl.exe -s -o NUL -w "%{http_code}" --noproxy "*" --connect-timeout 8 --max-time 20 https://github.com 2>$null
if ($code -eq '200') {
    Write-Ok "验证通过：github.com 经 hosts 真实返回 HTTP 200 —— 可以正常访问了！"
    $finalOk = $true
} else {
    Write-Fail "真实 hosts 路径验证失败（HTTP $code）—— hosts 中可能有其它工具（如 Steam++/Watt Toolkit）写的 127.0.0.1 屏蔽行抢先生效，或当前网络不通。"
    Log "fix-github: real-hosts verification failed http=$code"
    Disable-HostsEntry 'github.com'
    Wait-Exit
    Remove-Lock
    exit 1
}
# api.github.com 最终确认（真实 hosts 路径；失败不阻塞网页浏览，仅提示）
$codeApiFinal = & curl.exe -s -o NUL -w "%{http_code}" --noproxy "*" --connect-timeout 8 --max-time 12 https://api.github.com 2>$null
if ($codeApiFinal -eq '200') { Write-Ok "api.github.com 验证通过（HTTP 200）" }
else { Write-Fail "api.github.com 验证失败（HTTP $codeApiFinal，一般不影响网页浏览，下次自动重试）" }

Write-Host ''
Write-Host '提示：浏览器若仍打不开，按 Ctrl+F5 强制刷新，或重启浏览器；'
Write-Host '      gist.github.com 的 SNI 被运营商阻断，hosts 修复不了，需要代理。' -ForegroundColor Yellow
Wait-Exit

Log "fix-github run finished: finalOk=$finalOk http=$code api=$codeApiFinal"
Remove-Lock
