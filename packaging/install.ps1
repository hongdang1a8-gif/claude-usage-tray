# Dùng cho tính năng "Cập nhật lên ..." của bản PowerShell cũ (v1.2.x):
# bản cũ tải file zip của release, giải nén rồi chạy file này.
# Nó chép ClaudeUsageTray.exe vào %LOCALAPPDATA%\ClaudeUsageTray và khởi động exe;
# exe sẽ tự tắt bản PowerShell cũ, xoá shortcut Startup cũ và giữ lựa chọn tự khởi động.
param([switch]$NoAutostart)
$ErrorActionPreference = 'Stop'

$dest = Join-Path $env:LOCALAPPDATA 'ClaudeUsageTray'
$exe  = Join-Path $dest 'ClaudeUsageTray.exe'

Get-Process -Name ClaudeUsageTray -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'ClaudeUsageTray.exe') $exe -Force
Unblock-File $exe -ErrorAction SilentlyContinue

if ($NoAutostart) {
    # Người dùng đã tắt tự khởi động ở bản cũ: đánh dấu đã cài để exe không tự bật lại
    $k = 'HKCU:\Software\ClaudeUsageTray'
    New-Item -Path $k -Force | Out-Null
    New-ItemProperty -Path $k -Name Initialized -Value 1 -PropertyType DWord -Force | Out-Null
}

Start-Process $exe
