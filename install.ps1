# Cài Claude Usage Tray cho user hiện tại (không cần quyền Admin)
param([switch]$NoAutostart)
$ErrorActionPreference = 'Stop'

$src  = $PSScriptRoot
$dest = Join-Path $env:LOCALAPPDATA 'ClaudeUsageTray'
$lnk  = Join-Path ([Environment]::GetFolderPath('Startup')) 'ClaudeUsageTray.lnk'

$cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
if (-not (Test-Path (Join-Path $cfg '.credentials.json'))) {
    Write-Warning 'Chưa thấy thông tin đăng nhập Claude Code. Hãy cài Claude Code và đăng nhập bằng tài khoản Claude (Pro/Max/Team) - widget vẫn được cài, sẽ hiện "!" cho đến khi đăng nhập.'
}

# Dừng bản đang chạy (nếu có)
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*ClaudeUsageTray.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item (Join-Path $src 'ClaudeUsageTray.ps1'), (Join-Path $src 'start.vbs') $dest -Force
Get-ChildItem $dest | Unblock-File

if (-not $NoAutostart) {
    $sh = New-Object -ComObject WScript.Shell
    $sc = $sh.CreateShortcut($lnk)
    $sc.TargetPath       = Join-Path $env:WINDIR 'System32\wscript.exe'
    $sc.Arguments        = '"' + (Join-Path $dest 'start.vbs') + '"'
    $sc.WorkingDirectory = $dest
    $sc.Description      = 'Claude Usage Tray'
    $sc.Save()
    Write-Host 'Đã thêm vào Startup (tự chạy khi đăng nhập Windows).'
}

Start-Process (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList ('"' + (Join-Path $dest 'start.vbs') + '"')
Write-Host "Đã cài vào $dest và khởi động. Tìm icon ở khay hệ thống (có thể nằm trong mũi tên ^)."
