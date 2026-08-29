# ============================================================
# uninstall-github-fix.ps1 —— 卸载「GitHub 官网自动修复」
# 用法：双击运行（会自动请求管理员授权，UAC 点「是」）
# 作用：删除计划任务 DSH-GitHubFix，停止自动修复。
#       不会动 hosts 里已写好的 github.com 条目（保持当前可用状态）。
# 注意：本文件必须保存为 UTF-8 带 BOM。
# ============================================================

param(
    [string]$TaskName = 'DSH-GitHubFix'
)

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '[!] 需要管理员权限，正在请求提权 —— 请在弹窗（UAC）中点击「是」…'
    $p = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -Wait -PassThru
    exit $p.ExitCode
}

$ErrorActionPreference = 'Continue'
try {
    Import-Module ScheduledTasks -ErrorAction Stop
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
    Write-Host "计划任务 $TaskName 已删除。"
} catch {
    & schtasks /delete /tn $TaskName /f
    Write-Host "计划任务 $TaskName 已删除（schtasks，exit $LASTEXITCODE）。"
}

Write-Host ''
Write-Host '提示：hosts 文件中的 github.com 条目被保留（当前可用）。如需彻底还原，'
Write-Host '请手动编辑 C:\Windows\System32\drivers\etc\hosts，删除以下两行：'
Write-Host '  20.27.177.113 github.com'
Write-Host '  140.82.112.6  api.github.com'
Write-Host '（或用同目录 hosts 备份还原：%USERPROFILE%\hosts.backup-*）'
