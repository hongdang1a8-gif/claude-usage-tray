# Claude Usage Tray - hiển thị hạn mức 5h / tuần của Claude trên khay hệ thống (taskbar)
# Đọc OAuth token mà Claude Code lưu ở ~/.claude/.credentials.json (chỉ đọc, không ghi).

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Chỉ chạy 1 instance
$script:mutex = New-Object System.Threading.Mutex($false, 'Local\ClaudeUsageTray')
if (-not $script:mutex.WaitOne(0)) { exit }

Add-Type -Namespace Win32 -Name Native -MemberDefinition '[DllImport("user32.dll")] public static extern bool DestroyIcon(System.IntPtr h);'

$ConfigDir  = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
$CredPath   = Join-Path $ConfigDir '.credentials.json'
$UsageUrl   = 'https://api.anthropic.com/api/oauth/usage'
$ScriptDir  = $PSScriptRoot
$StartupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'ClaudeUsageTray.lnk'
$RefreshMin = 3          # phút giữa 2 lần cập nhật
$WarnAt     = 80         # % thì bật thông báo cảnh báo (1 lần / chu kỳ)
$vi         = [Globalization.CultureInfo]::GetCultureInfo('vi-VN')

$script:lastHIcon   = [IntPtr]::Zero
$script:detailText  = 'Đang tải...'
$script:warnedFor   = ''

$tray = New-Object Windows.Forms.NotifyIcon
$tray.Text = 'Claude usage: đang tải...'
$tray.Visible = $true

# ---------- Vẽ icon: số % của hạn mức 5h trên nền màu ----------
function Set-TrayIcon([string]$text, [Drawing.Color]$bg) {
    $s   = [Windows.Forms.SystemInformation]::SmallIconSize.Width
    $bmp = New-Object Drawing.Bitmap $s, $s
    $g   = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([Drawing.Color]::Transparent)

    $brush = New-Object Drawing.SolidBrush $bg
    $r = [int][Math]::Max(2, $s / 5)
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $r*2, $r*2, 180, 90)
    $path.AddArc($s-1-$r*2, 0, $r*2, $r*2, 270, 90)
    $path.AddArc($s-1-$r*2, $s-1-$r*2, $r*2, $r*2, 0, 90)
    $path.AddArc(0, $s-1-$r*2, $r*2, $r*2, 90, 90)
    $path.CloseFigure()
    $g.FillPath($brush, $path)

    # Co cỡ chữ đến khi vừa khung (đo không padding)
    $sf = [Drawing.StringFormat]::GenericTypographic.Clone()
    $sf.FormatFlags = $sf.FormatFlags -bor [Drawing.StringFormatFlags]::NoWrap -bor [Drawing.StringFormatFlags]::NoClip
    $fam = if ($text.Length -ge 3) { 'Arial Narrow' } else { 'Segoe UI' }
    $em = [float]($s * 0.95)
    do {
        $font = New-Object Drawing.Font $fam, $em, ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
        $sz = $g.MeasureString($text, $font, 1000, $sf)
        if ($sz.Width -le $s - 1 -and $sz.Height -le $s + 2) { break }
        $font.Dispose(); $em -= 0.5
    } while ($em -gt 4)
    $x = ($s - $sz.Width) / 2
    $y = ($s - $sz.Height) / 2
    $g.DrawString($text, $font, [Drawing.Brushes]::White, [float]$x, [float]$y, $sf)

    $h = $bmp.GetHicon()
    $tray.Icon = [Drawing.Icon]::FromHandle($h)
    if ($script:lastHIcon -ne [IntPtr]::Zero) { [void][Win32.Native]::DestroyIcon($script:lastHIcon) }
    $script:lastHIcon = $h

    $font.Dispose(); $sf.Dispose(); $path.Dispose(); $brush.Dispose(); $g.Dispose(); $bmp.Dispose()
}

function Get-Color([double]$pct) {
    if ($pct -ge 80) { [Drawing.Color]::FromArgb(198, 40, 40) }      # đỏ
    elseif ($pct -ge 50) { [Drawing.Color]::FromArgb(230, 108, 0) }  # cam
    else { [Drawing.Color]::FromArgb(46, 125, 50) }                  # xanh
}

function Format-Left([DateTimeOffset]$at) {
    $t = $at - [DateTimeOffset]::Now
    if ($t.TotalSeconds -le 0) { return 'sắp reset' }
    if ($t.TotalDays -ge 1)  { return ('{0}d{1}h' -f [int][Math]::Floor($t.TotalDays), $t.Hours) }
    if ($t.TotalHours -ge 1) { return ('{0}h{1:00}m' -f [int][Math]::Floor($t.TotalHours), $t.Minutes) }
    return ('{0}m' -f [int][Math]::Ceiling($t.TotalMinutes))
}

function Set-Tooltip([string]$t) {
    if ($t.Length -gt 63) { $t = $t.Substring(0, 63) }   # giới hạn của NotifyIcon
    $tray.Text = $t
}

function Show-Error([string]$short, [string]$long) {
    Set-TrayIcon '!' ([Drawing.Color]::FromArgb(110, 110, 110))
    Set-Tooltip "Claude usage: $short"
    $script:detailText = $long
    $miDetail5h.Text = $long
    $miDetailWk.Text = ''
}

# ---------- Khởi động cùng Windows (shortcut trong thư mục Startup của user) ----------
function Test-Autostart { Test-Path $StartupLnk }

function Set-Autostart([bool]$on) {
    if ($on) {
        $sh = New-Object -ComObject WScript.Shell
        $sc = $sh.CreateShortcut($StartupLnk)
        $sc.TargetPath       = Join-Path $env:WINDIR 'System32\wscript.exe'
        $sc.Arguments        = '"' + (Join-Path $ScriptDir 'start.vbs') + '"'
        $sc.WorkingDirectory = $ScriptDir
        $sc.Description      = 'Claude Usage Tray'
        $sc.Save()
    } else {
        Remove-Item $StartupLnk -Force -ErrorAction SilentlyContinue
    }
}

# ---------- Lấy dữ liệu ----------
function Update-Usage {
    try {
        if (-not (Test-Path $CredPath)) { Show-Error 'chưa đăng nhập' 'Không thấy ~/.claude/.credentials.json - hãy đăng nhập Claude Code.'; return }
        $cred = (Get-Content $CredPath -Raw | ConvertFrom-Json).claudeAiOauth
        if ([DateTimeOffset]::FromUnixTimeMilliseconds([long]$cred.expiresAt) -lt [DateTimeOffset]::Now) {
            Show-Error 'token hết hạn' 'Token hết hạn - mở Claude Code (gõ 1 lệnh bất kỳ) để làm mới.'; return
        }
        $headers = @{ Authorization = "Bearer $($cred.accessToken)"; 'anthropic-beta' = 'oauth-2025-04-20'; 'User-Agent' = 'claude-usage-tray/1.0' }
        $u = Invoke-RestMethod -Uri $UsageUrl -Headers $headers -TimeoutSec 20
        if (-not $u.five_hour -or -not $u.seven_day) {
            Show-Error 'không có hạn mức' 'Tài khoản này không có hạn mức 5h/tuần (gói không hỗ trợ).'; return
        }

        $p5 = [double]$u.five_hour.utilization
        $pw = [double]$u.seven_day.utilization
        $r5 = [DateTimeOffset]::Parse($u.five_hour.resets_at).ToLocalTime()
        $rw = [DateTimeOffset]::Parse($u.seven_day.resets_at).ToLocalTime()

        Set-TrayIcon ([string][int][Math]::Round($p5)) (Get-Color ([Math]::Max($p5, $pw)))

        $tip = "Claude 5h: {0:0}% | còn {1}`nTuần: {2:0}% | còn {3}" -f $p5, (Format-Left $r5), $pw, (Format-Left $rw)
        Set-Tooltip $tip

        $l5 = '5 giờ:  {0:0}% đã dùng  -  reset {1} (còn {2})' -f $p5, $r5.ToString('HH:mm', $vi), (Format-Left $r5)
        $lw = 'Tuần:   {0:0}% đã dùng  -  reset {1} (còn {2})' -f $pw, $rw.ToString('ddd dd/MM HH:mm', $vi), (Format-Left $rw)
        $script:detailText = "$l5`n$lw"
        $miDetail5h.Text = $l5
        $miDetailWk.Text = $lw
        $miUpdated.Text  = 'Cập nhật lúc ' + (Get-Date).ToString('HH:mm:ss')

        # Cảnh báo 1 lần mỗi chu kỳ khi vượt ngưỡng
        $key = ''
        if ($p5 -ge $WarnAt) { $key = "5h|$($u.five_hour.resets_at)" }
        elseif ($pw -ge $WarnAt) { $key = "wk|$($u.seven_day.resets_at)" }
        if ($key -and $key -ne $script:warnedFor) {
            $script:warnedFor = $key
            $tray.ShowBalloonTip(8000, 'Claude sắp chạm hạn mức', $script:detailText, [Windows.Forms.ToolTipIcon]::Warning)
        }
    }
    catch {
        $code = $null
        try { $code = [int]$_.Exception.Response.StatusCode } catch {}
        switch ($code) {
            401     { Show-Error 'token hết hạn' 'Token không hợp lệ - mở Claude Code để làm mới đăng nhập.' }
            429     { Set-Tooltip 'Claude usage: bị giới hạn tần suất, thử lại sau' }
            default { Show-Error 'lỗi kết nối' ("Lỗi: " + $_.Exception.Message) }
        }
    }
}

# ---------- Menu chuột phải ----------
$menu = New-Object Windows.Forms.ContextMenuStrip
$miDetail5h = $menu.Items.Add('Đang tải...'); $miDetail5h.Enabled = $false
$miDetailWk = $menu.Items.Add('');            $miDetailWk.Enabled = $false
$miUpdated  = $menu.Items.Add('');            $miUpdated.Enabled  = $false
[void]$menu.Items.Add('-')
$miRefresh = $menu.Items.Add('Làm mới ngay')
$miRefresh.add_Click({ Update-Usage })
$miWeb = $menu.Items.Add('Mở trang Usage trên claude.ai')
$miWeb.add_Click({ Start-Process 'https://claude.ai/settings/usage' })
$miAuto = New-Object Windows.Forms.ToolStripMenuItem 'Khởi động cùng Windows'
$miAuto.add_Click({
    try { Set-Autostart (-not (Test-Autostart)) }
    catch { $tray.ShowBalloonTip(5000, 'Claude usage', 'Không đổi được cài đặt khởi động: ' + $_.Exception.Message, [Windows.Forms.ToolTipIcon]::Error) }
    $miAuto.Checked = Test-Autostart
})
[void]$menu.Items.Add($miAuto)
$menu.add_Opening({ $miAuto.Checked = Test-Autostart })
[void]$menu.Items.Add('-')
$miExit = $menu.Items.Add('Thoát')
$miExit.add_Click({
    $timer.Stop(); $tray.Visible = $false; $tray.Dispose()
    [Windows.Forms.Application]::Exit()
})
$tray.ContextMenuStrip = $menu

# Click trái: hiện thông báo chi tiết
$tray.add_MouseClick({
    param($s, $e)
    if ($e.Button -eq [Windows.Forms.MouseButtons]::Left) {
        Update-Usage
        $tray.ShowBalloonTip(6000, 'Claude usage', $script:detailText, [Windows.Forms.ToolTipIcon]::Info)
    }
})

$timer = New-Object Windows.Forms.Timer
$timer.Interval = $RefreshMin * 60 * 1000
$timer.add_Tick({ Update-Usage })

Set-TrayIcon '..' ([Drawing.Color]::FromArgb(110, 110, 110))
Update-Usage
$timer.Start()
[Windows.Forms.Application]::Run()
