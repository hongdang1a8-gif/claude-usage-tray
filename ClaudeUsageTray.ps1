# Claude Usage Tray - hiển thị hạn mức 5h / tuần của Claude trên khay hệ thống (taskbar)
# Đọc OAuth token mà Claude Code lưu ở ~/.claude/.credentials.json (chỉ đọc, không ghi).

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Version = '1.2.0'
$Repo    = 'hongdang1a8-gif/claude-usage-tray'

# Chỉ chạy 1 instance
$script:mutex = New-Object System.Threading.Mutex($false, 'Local\ClaudeUsageTray')
try { $owned = $script:mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
if (-not $owned) { exit }

Add-Type -Namespace Win32 -Name Native -MemberDefinition '[DllImport("user32.dll")] public static extern bool DestroyIcon(System.IntPtr h);'

$ConfigDir     = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
$CredPath      = Join-Path $ConfigDir '.credentials.json'
$UsageUrl      = 'https://api.anthropic.com/api/oauth/usage'
$ScriptDir     = $PSScriptRoot
$StartupLnk    = Join-Path ([Environment]::GetFolderPath('Startup')) 'ClaudeUsageTray.lnk'
$RefreshMin    = 3      # phút giữa 2 lần cập nhật
$WarnAt        = 80     # % thì bật thông báo cảnh báo (1 lần / chu kỳ)
$ResetNotifyAt = 50     # chỉ báo "đã reset" nếu chu kỳ trước đã dùng >= mức này
$UpdateEveryH  = 12     # giờ giữa 2 lần kiểm tra bản mới trên GitHub
$vi            = [Globalization.CultureInfo]::GetCultureInfo('vi-VN')

$script:lastHIcon       = [IntPtr]::Zero
$script:detailText      = 'Đang tải...'
$script:warnedFor       = ''
$script:windows         = @{}        # '5h' / 'week' -> @{ Id; Reset; Pct; Done }
$script:update          = $null      # release mới hơn (nếu có)
$script:notifiedVersion = ''
$script:lastUpdateCheck = [DateTime]::MinValue

$tray = New-Object Windows.Forms.NotifyIcon
$tray.Text = 'Claude usage: đang tải...'
$tray.Visible = $true

function Show-Balloon([string]$title, [string]$text, [string]$kind = 'Info') {
    if ($text.Length -gt 250) { $text = $text.Substring(0, 250) }
    $tray.ShowBalloonTip(8000, $title, $text, [Windows.Forms.ToolTipIcon]::$kind)
}

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

# ---------- Định dạng thời gian ----------
function Format-Span([TimeSpan]$t) {
    if ($t.TotalDays -ge 1)  { return ('{0}d{1}h' -f [int][Math]::Floor($t.TotalDays), $t.Hours) }
    if ($t.TotalHours -ge 1) { return ('{0}h{1:00}m' -f [int][Math]::Floor($t.TotalHours), $t.Minutes) }
    return ('{0}m' -f [int][Math]::Max(1, [Math]::Ceiling($t.TotalMinutes)))
}

function Format-Left([DateTimeOffset]$at) {
    $t = $at - [DateTimeOffset]::Now
    if ($t.TotalSeconds -le 0) { return 'sắp reset' }
    return (Format-Span $t)
}

function Format-When([DateTimeOffset]$at) {
    if ($at.LocalDateTime.Date -eq [DateTime]::Today) { return $at.ToString('HH:mm', $vi) }
    return $at.ToString('ddd HH:mm', $vi)
}

# NotifyIcon.Text giới hạn 63 ký tự; Windows cho phép 127 -> đặt qua reflection
function Set-Tooltip([string]$t) {
    if ($t.Length -gt 127) { $t = $t.Substring(0, 127) }
    if ($t.Length -le 63) { $tray.Text = $t; return }
    try {
        $type  = [Windows.Forms.NotifyIcon]
        $flags = [Reflection.BindingFlags]'NonPublic,Instance'
        $type.GetField('text', $flags).SetValue($tray, $t)
        if ($type.GetField('added', $flags).GetValue($tray)) {
            [void]$type.GetMethod('UpdateIcon', $flags).Invoke($tray, @($true))
        }
    } catch { $tray.Text = $t.Substring(0, 63) }
}

# ---------- Phân tích 1 chu kỳ hạn mức + dự báo tốc độ ----------
function Get-Window($o, [double]$hours) {
    $w = [ordered]@{ Pct = 0.0; Reset = $null; Eta = $null; Pace = '' }
    if ($o) {
        $w.Pct = [double]$o.utilization
        if ($o.resets_at) { $w.Reset = [DateTimeOffset]::Parse($o.resets_at).ToLocalTime() }
    }
    if ($w.Reset -and $w.Pct -ge 1 -and $w.Pct -lt 100) {
        $len     = [TimeSpan]::FromHours($hours)
        $elapsed = ([DateTimeOffset]::Now - ($w.Reset - $len)).TotalSeconds
        # Cần đủ dữ liệu mới dự báo: >= 15 phút và >= 5% độ dài chu kỳ
        if ($elapsed -ge [Math]::Max(900, $len.TotalSeconds * 0.05)) {
            $eta = [DateTimeOffset]::Now.AddSeconds((100 - $w.Pct) * $elapsed / $w.Pct)
            if ($eta -lt $w.Reset) { $w.Eta = $eta; $w.Pace = 'out' } else { $w.Pace = 'ok' }
        }
    }
    [pscustomobject]$w
}

function Get-Lines([string]$short, [string]$long, $w, [bool]$longDate) {
    if ($w.Reset) {
        $resetTxt = if ($longDate) { $w.Reset.ToString('ddd dd/MM HH:mm', $vi) } else { Format-When $w.Reset }
        $tip  = '{0} {1:0}% · reset {2} · còn {3}' -f $short, $w.Pct, (Format-When $w.Reset), (Format-Left $w.Reset)
        $menu = '{0}{1:0}% đã dùng  –  reset {2} (còn {3})' -f $long, $w.Pct, $resetTxt, (Format-Left $w.Reset)
    } else {
        $tip  = '{0} {1:0}% · chưa bắt đầu chu kỳ' -f $short, $w.Pct
        $menu = '{0}{1:0}% đã dùng  –  chưa bắt đầu chu kỳ' -f $long, $w.Pct
    }
    $paceTip = ''; $paceMenu = ''
    if ($w.Pct -ge 100) {
        $paceTip  = '  ⚠ đã hết hạn mức'
        $paceMenu = '        ⚠ Đã hết hạn mức, chờ reset'
    } elseif ($w.Pace -eq 'out') {
        $paceTip  = '  ⚠ hết lúc ' + (Format-When $w.Eta)
        $paceMenu = '        ⚠ Theo tốc độ hiện tại sẽ hết lúc {0} (sớm hơn reset {1})' -f (Format-When $w.Eta), (Format-Span ($w.Reset - $w.Eta))
    } elseif ($w.Pace -eq 'ok') {
        $paceMenu = '        ✓ Theo tốc độ hiện tại đủ dùng đến khi reset'
    }
    [pscustomobject]@{ Tip = $tip; Menu = $menu; PaceTip = $paceTip; PaceMenu = $paceMenu }
}

function Set-MenuLine($item, [string]$text) {
    $item.Text = $text
    $item.Visible = [bool]$text
}

function Show-Error([string]$short, [string]$long) {
    Set-TrayIcon '!' ([Drawing.Color]::FromArgb(110, 110, 110))
    Set-Tooltip "Claude usage: $short"
    $script:detailText = $long
    Set-MenuLine $miDetail5h $long
    Set-MenuLine $miPace5h ''
    Set-MenuLine $miDetailWk ''
    Set-MenuLine $miPaceWk ''
}

# ---------- Báo khi hạn mức đã reset (dựa vào thời gian, chạy được cả khi token hết hạn) ----------
function Register-Window([string]$key, $w) {
    if (-not $w.Reset) { return }
    $id  = [long][Math]::Round($w.Reset.ToUnixTimeSeconds() / 60)   # so theo phút, bỏ qua phần lẻ giây
    $cur = $script:windows[$key]
    if ($cur -and $cur.Id -eq $id) { $cur.Pct = [Math]::Max($cur.Pct, $w.Pct) }
    else { $script:windows[$key] = @{ Id = $id; Reset = $w.Reset; Pct = $w.Pct; Done = $false } }
}

function Invoke-ResetCheck {
    foreach ($key in @($script:windows.Keys)) {
        $c = $script:windows[$key]
        if (-not $c.Done -and [DateTimeOffset]::Now -ge $c.Reset) {
            $c.Done = $true
            if ($c.Pct -ge $ResetNotifyAt) {
                $name = if ($key -eq '5h') { 'Hạn mức 5 giờ' } else { 'Hạn mức tuần' }
                Show-Balloon "$name đã reset" ('Chu kỳ trước bạn đã dùng {0:0}%. Giờ có thể dùng Claude tiếp rồi.' -f $c.Pct)
            }
        }
    }
}

# Hẹn lần chạy kế tiếp: mặc định $RefreshMin phút, nhưng sớm hơn nếu sắp đến giờ reset
function Set-NextTick {
    $ms = $RefreshMin * 60000.0
    foreach ($c in $script:windows.Values) {
        if (-not $c.Done) {
            $until = ($c.Reset - [DateTimeOffset]::Now).TotalMilliseconds + 20000
            if ($until -gt 0 -and $until -lt $ms) { $ms = $until }
        }
    }
    $timer.Interval = [int][Math]::Max(15000, $ms)
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

# ---------- Cập nhật phiên bản từ GitHub Releases ----------
function Invoke-UpdateCheck([switch]$Manual) {
    $script:lastUpdateCheck = [DateTime]::Now
    try {
        $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -TimeoutSec 15 `
            -Headers @{ 'User-Agent' = "claude-usage-tray/$Version"; Accept = 'application/vnd.github+json' }
        $latest = [version]($rel.tag_name.TrimStart('v'))
        if ($latest -gt [version]$Version) {
            $script:update = $rel
            $miUpdate.Text = "Cập nhật lên $($rel.tag_name) (đang dùng v$Version)"
            $miUpdate.Font = New-Object Drawing.Font($miUpdate.Font, [Drawing.FontStyle]::Bold)
            if ($script:notifiedVersion -ne $rel.tag_name -or $Manual) {
                $script:notifiedVersion = $rel.tag_name
                Show-Balloon "Có bản mới $($rel.tag_name)" 'Click phải vào icon → "Cập nhật lên ..." để cài.'
            }
        } elseif ($Manual) {
            Show-Balloon 'Claude Usage Tray' "Bạn đang dùng bản mới nhất (v$Version)."
        }
    } catch {
        if ($Manual) { Show-Balloon 'Không kiểm tra được bản mới' $_.Exception.Message 'Error' }
    }
}

function Install-Update {
    $rel   = $script:update
    $asset = $rel.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
    if (-not $asset) { throw "Bản $($rel.tag_name) không có file zip." }
    Show-Balloon 'Đang cập nhật...' "Đang tải $($asset.name), widget sẽ tự khởi động lại."

    $dir = Join-Path $env:TEMP ('cut-update-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $dir | Out-Null
    $zip = Join-Path $dir 'update.zip'
    Invoke-WebRequest -UseBasicParsing $asset.browser_download_url -OutFile $zip -TimeoutSec 120
    Expand-Archive $zip (Join-Path $dir 'x')
    $installer = Join-Path $dir 'x\install.ps1'
    if (-not (Test-Path $installer)) { throw 'Gói cập nhật không có install.ps1.' }

    # Bộ cài sẽ dừng tiến trình này, chép bản mới và khởi động lại; giữ nguyên lựa chọn tự khởi động
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$installer`"")
    if (-not (Test-Autostart)) { $argList += '-NoAutostart' }
    Start-Process powershell.exe -ArgumentList $argList -WindowStyle Hidden
}

# ---------- Lấy dữ liệu ----------
function Update-Usage {
    try {
        if (-not (Test-Path $CredPath)) { Show-Error 'chưa đăng nhập' 'Không thấy ~/.claude/.credentials.json - hãy đăng nhập Claude Code.'; return }
        $cred = (Get-Content $CredPath -Raw | ConvertFrom-Json).claudeAiOauth
        if ([DateTimeOffset]::FromUnixTimeMilliseconds([long]$cred.expiresAt) -lt [DateTimeOffset]::Now) {
            Show-Error 'token hết hạn' 'Token hết hạn - mở Claude Code (gõ 1 lệnh bất kỳ) để làm mới.'; return
        }
        $headers = @{ Authorization = "Bearer $($cred.accessToken)"; 'anthropic-beta' = 'oauth-2025-04-20'; 'User-Agent' = "claude-usage-tray/$Version" }
        $u = Invoke-RestMethod -Uri $UsageUrl -Headers $headers -TimeoutSec 20
        if (-not $u.five_hour -and -not $u.seven_day) {
            Show-Error 'không có hạn mức' 'Tài khoản này không có hạn mức 5h/tuần (gói không hỗ trợ).'; return
        }

        $w5 = Get-Window $u.five_hour 5
        $ww = Get-Window $u.seven_day 168
        Register-Window '5h' $w5
        Register-Window 'week' $ww

        # Màu: theo % cao nhất; nếu dự báo sẽ hết trước giờ reset thì tối thiểu là cam
        $sev   = [Math]::Max($w5.Pct, $ww.Pct)
        $color = Get-Color $sev
        if (($w5.Pace -eq 'out' -or $ww.Pace -eq 'out') -and $sev -lt 50) { $color = Get-Color 50 }
        Set-TrayIcon ([string][int][Math]::Round($w5.Pct)) $color

        $a = Get-Lines '5h' '5 giờ:  ' $w5 $false
        $b = Get-Lines 'Tuần' 'Tuần:   ' $ww $true
        $short = (@($a.Tip, $a.PaceTip, $b.Tip, $b.PaceTip) | Where-Object { $_ }) -join "`n"
        Set-Tooltip $short
        $script:detailText = $short

        Set-MenuLine $miDetail5h $a.Menu
        Set-MenuLine $miPace5h   $a.PaceMenu
        Set-MenuLine $miDetailWk $b.Menu
        Set-MenuLine $miPaceWk   $b.PaceMenu
        $miUpdated.Text = 'Cập nhật lúc ' + (Get-Date).ToString('HH:mm:ss')

        # Cảnh báo 1 lần mỗi chu kỳ khi vượt ngưỡng
        $key = ''
        if ($w5.Pct -ge $WarnAt -and $script:windows['5h']) { $key = '5h|' + $script:windows['5h'].Id }
        elseif ($ww.Pct -ge $WarnAt -and $script:windows['week']) { $key = 'wk|' + $script:windows['week'].Id }
        if ($key -and $key -ne $script:warnedFor) {
            $script:warnedFor = $key
            Show-Balloon 'Claude sắp chạm hạn mức' $script:detailText 'Warning'
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

function Invoke-Tick {
    Invoke-ResetCheck
    Update-Usage
    Invoke-ResetCheck
    if (([DateTime]::Now - $script:lastUpdateCheck).TotalHours -ge $UpdateEveryH) { Invoke-UpdateCheck }
    Set-NextTick
}

# ---------- Menu chuột phải ----------
$menu = New-Object Windows.Forms.ContextMenuStrip
$miDetail5h = $menu.Items.Add('Đang tải...'); $miDetail5h.Enabled = $false
$miPace5h   = $menu.Items.Add('');            $miPace5h.Enabled   = $false; $miPace5h.Visible = $false
$miDetailWk = $menu.Items.Add('');            $miDetailWk.Enabled = $false; $miDetailWk.Visible = $false
$miPaceWk   = $menu.Items.Add('');            $miPaceWk.Enabled   = $false; $miPaceWk.Visible = $false
$miUpdated  = $menu.Items.Add('');            $miUpdated.Enabled  = $false
[void]$menu.Items.Add('-')
$miRefresh = $menu.Items.Add('Làm mới ngay')
$miRefresh.add_Click({ Update-Usage; Set-NextTick })
$miWeb = $menu.Items.Add('Mở trang Usage trên claude.ai')
$miWeb.add_Click({ Start-Process 'https://claude.ai/settings/usage' })
$miAuto = New-Object Windows.Forms.ToolStripMenuItem 'Khởi động cùng Windows'
$miAuto.add_Click({
    try { Set-Autostart (-not (Test-Autostart)) }
    catch { Show-Balloon 'Claude usage' ('Không đổi được cài đặt khởi động: ' + $_.Exception.Message) 'Error' }
    $miAuto.Checked = Test-Autostart
})
[void]$menu.Items.Add($miAuto)
$miUpdate = New-Object Windows.Forms.ToolStripMenuItem "Phiên bản v$Version – kiểm tra cập nhật"
$miUpdate.add_Click({
    if ($script:update) {
        try { Install-Update } catch { Show-Balloon 'Cập nhật thất bại' $_.Exception.Message 'Error' }
    } else {
        Invoke-UpdateCheck -Manual
    }
})
[void]$menu.Items.Add($miUpdate)
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
        Set-NextTick
        Show-Balloon 'Claude usage' $script:detailText
    }
})

$timer = New-Object Windows.Forms.Timer
$timer.Interval = $RefreshMin * 60 * 1000
$timer.add_Tick({ Invoke-Tick })

Set-TrayIcon '..' ([Drawing.Color]::FromArgb(110, 110, 110))
Invoke-Tick
$timer.Start()
[Windows.Forms.Application]::Run()
