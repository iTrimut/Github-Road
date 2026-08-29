# ============================================================
# install-github-fix.ps1 —— 一键安装「GitHub 官网自动修复」
# 用法：双击运行（会自动请求管理员授权，UAC 点「是」）
# 作用：
#   1. 立即运行 fix-github.ps1 -Quiet，把 github.com 指向当前最快可用 IP
#   2. 注册计划任务（默认 DSH-GitHubFix，每 30 分钟自动运行一次，隐藏窗口）
#      任务设置：允许电池供电时运行、错过时间自动补跑、并发新实例忽略、
#                运行时限 30 分钟、最高权限、仅当前用户登录时运行
# 要求：本文件必须与 fix-github.ps1 放在同一个文件夹；文件夹路径不能含空格。
# 注意：本文件必须保存为 UTF-8 带 BOM。
# ============================================================

param(
    [string]$TaskName = 'DSH-GitHubFix',
    [int]$Minutes = 30
)

# 自我提权（注册计划任务与改 hosts 都需要管理员）
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '[!] 需要管理员权限，正在请求提权 —— 请在弹窗（UAC）中点击「是」…'
    $p = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -Wait -PassThru
    exit $p.ExitCode
}

$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'fix-github.ps1'
$vbs = Join-Path $PSScriptRoot 'fix-github-quiet.vbs'
if (-not (Test-Path $script)) { throw "找不到 fix-github.ps1（应与此安装脚本同目录）: $script" }
if (-not (Test-Path $vbs)) { throw "找不到 fix-github-quiet.vbs（应与此安装脚本同目录）: $vbs" }
if ($PSScriptRoot -match ' ') { throw "安装目录路径不能含空格（当前: $PSScriptRoot）。请把脚本移到无空格路径（如 D:\GitHubRoad\）后重试。" }

# 1. 立即修复
Write-Host '[1/2] 立即运行修复脚本…'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Quiet
Write-Host "fix run exit code: $LASTEXITCODE"

# 2. 注册计划任务（优先用 Register-ScheduledTask，可设置电池/补跑等选项；失败则退回 schtasks）
#    注意：任务动作用 wscript.exe 跑 fix-github-quiet.vbs（无窗口静默启动 powershell）。
#    powershell.exe -WindowStyle Hidden 在计划任务环境下会报 0xC0000142 启动失败，不能用。
Write-Host "[2/2] 注册计划任务 $TaskName （每 $Minutes 分钟）…"
$taskOk = $false
try {
    Import-Module ScheduledTasks -ErrorAction Stop
    $act = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$vbs`""
    # 注意：RepetitionDuration 不能用 [TimeSpan]::MaxValue（序列化为 P99999999DT23H59M59S 被拒）
    #       也不能用 PT0S（被拒）。用 365 天：每 30 分钟重复一年，到期重跑本脚本续期即可。
    $trg = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $Minutes) -RepetitionDuration ([TimeSpan]::FromDays(365))
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
    $prc = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName $TaskName -Action $act -Trigger $trg -Settings $set -Principal $prc -Force -ErrorAction Stop | Out-Null
    $taskOk = $true
    Write-Host '任务注册成功（Register-ScheduledTask）'
} catch {
    Write-Host "Register-ScheduledTask 失败（$($_.Exception.Message)），回退 schtasks…"
    $taskCmd = "wscript.exe `"$vbs`""
    & schtasks /create /tn $TaskName /tr "$taskCmd" /sc minute /mo $Minutes /rl highest /f
    if ($LASTEXITCODE -eq 0) { $taskOk = $true }
}
if (-not $taskOk) { throw '注册计划任务失败（可能需要以管理员身份重试）' }

Write-Host ''
Write-Host "DONE：GitHub 官网自动修复已安装。任务 $TaskName 每 $Minutes 分钟自动运行一次。"
Write-Host '说明：浏览器若打不开，按 Ctrl+F5 强制刷新或重启浏览器；运行记录见同目录 github-fix.log。'
