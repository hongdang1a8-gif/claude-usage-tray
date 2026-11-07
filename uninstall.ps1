# Gỡ Claude Usage Tray
$dest = Join-Path $env:LOCALAPPDATA 'ClaudeUsageTray'
$lnk  = Join-Path ([Environment]::GetFolderPath('Startup')) 'ClaudeUsageTray.lnk'

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*ClaudeUsageTray.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 500

Remove-Item $lnk -Force -ErrorAction SilentlyContinue
Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'Đã gỡ Claude Usage Tray.'
