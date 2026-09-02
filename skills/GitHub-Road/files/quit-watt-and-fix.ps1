# quit-watt-and-fix.ps1 - one-shot: stop Watt Toolkit (Steam++), purge its hosts block, re-run the GitHub fix
$ErrorActionPreference = 'Continue'
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '[!] Requesting admin rights - click YES on the UAC prompt...'
    $p = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -Wait -PassThru
    exit $p.ExitCode
}

# 1. stop Watt Toolkit processes (their hosts writer must die first)
Write-Host '[1/4] stopping Watt Toolkit (Steam++) processes...'
foreach ($n in @('Steam++.Accelerator','Steam++','WattToolkit')) {
    Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2
$left = Get-Process -Name 'Steam++','Steam++.Accelerator' -ErrorAction SilentlyContinue
if ($left) { Write-Host "WARNING: still running: $($left.ProcessName -join ',')" } else { Write-Host 'all stopped.' }

# 2. purge the Steam++/Watt hosts section plus any dsh leftovers
$HOSTS = 'C:\Windows\System32\drivers\etc\hosts'
$bak = "$env:USERPROFILE\hosts.watt-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item $HOSTS $bak -Force
Write-Host "[2/4] hosts backed up: $bak"
$lines = [System.IO.File]::ReadAllLines($HOSTS)
$kept = New-Object System.Collections.Generic.List[string]
$inSection = $false
$removed = 0
foreach ($line in $lines) {
    $t = $line.Trim()
    if ($t -match '(?i)^#\s*Steam\+\+\s*Start') { $inSection = $true; $removed++; continue }
    if ($t -match '(?i)^#\s*Steam\+\+\s*End') { $inSection = $false; $removed++; continue }
    if ($inSection) { $removed++; continue }
    # dsh leftovers / ranking lines
    if ($t -match '(?i)^\s*#?\s*(\d{1,3}\.){3}\d{1,3}\s+(github\.com|api\.github\.com)') { $removed++; continue }
    if ($t -match '(?i)^#\s*dsh github') { $removed++; continue }
    if ($t -match '^#\d+\s+(\d{1,3}\.){3}\d{1,3}') { $removed++; continue }
    $kept.Add($line)
}
[System.IO.File]::WriteAllLines($HOSTS, $kept.ToArray(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "removed $removed lines; hosts now $($kept.Count) lines"

# 3. run the idempotent GitHub fix (real hosts-path verification included)
Write-Host '[3/4] running the GitHub fix...'
Remove-Item "$env:TEMP\dsh-github-fix.lock" -Force -ErrorAction SilentlyContinue
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'F:\Turbulence\fix-github.ps1' -Quiet
Write-Host "fix exit: $LASTEXITCODE"

# 4. real hosts-path verify
Write-Host '[4/4] verifying via hosts path...'
$code = & curl.exe -s -o NUL -w "%{http_code}" --noproxy "*" --connect-timeout 8 --max-time 20 https://github.com 2>$null
Write-Host "github.com via hosts -> HTTP $code"
