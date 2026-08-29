' fix-github-quiet.vbs - hidden launcher for fix-github.ps1 -Quiet (scheduled task)
' ASCII only on purpose (wscript reads ANSI; Chinese comments can corrupt parsing).
' Runs powershell with window style 0 (invisible). Avoids the 0xC0000142
' (STATUS_DLL_INIT_FAILED) bug of powershell.exe -WindowStyle Hidden in tasks.
Set fso = CreateObject("Scripting.FileSystemObject")
Set ws  = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & dir & "\fix-github.ps1"" -Quiet"
ws.Run cmd, 0, False
