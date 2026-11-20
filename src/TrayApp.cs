using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Globalization;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace ClaudeUsageTray
{
    sealed class TrayApp : ApplicationContext
    {
        // ---- Cài đặt ----
        static readonly TimeSpan PollInterval  = TimeSpan.FromMinutes(5);   // chu kỳ cập nhật bình thường
        static readonly TimeSpan MaxBackoff    = TimeSpan.FromMinutes(15);  // chờ tối đa sau khi bị 429
        static readonly TimeSpan ProbeWhenOlder = TimeSpan.FromMinutes(15); // số liệu cũ hơn mức này mới dùng đường dự phòng
        static readonly TimeSpan ProbeMinGap   = TimeSpan.FromMinutes(10);  // khoảng cách tối thiểu giữa 2 lần dự phòng
        static readonly TimeSpan StaleAfter    = TimeSpan.FromMinutes(10);  // số liệu cũ hơn mức này thì ghi rõ giờ lấy

        static readonly CultureInfo Vi = CultureInfo.GetCultureInfo("vi-VN");
        static readonly Color Gray   = Color.FromArgb(110, 110, 110);
        static readonly Color Green  = Color.FromArgb(46, 125, 50);
        static readonly Color Orange = Color.FromArgb(230, 108, 0);
        static readonly Color Red    = Color.FromArgb(198, 40, 40);

        readonly NotifyIcon tray;
        readonly ContextMenuStrip menu;
        readonly ToolStripMenuItem miFive, miWeek, miStatus, miAuto;
        readonly Timer timer;

        UsageData data;                 // số liệu gần nhất lấy được
        DateTime dataAt;                // lúc lấy được số liệu đó
        FetchResult lastResult;         // kết quả lần cập nhật gần nhất
        DateTime lastAttempt = DateTime.MinValue;
        DateTime nextFetch = DateTime.MinValue;
        DateTime cooldownUntil = DateTime.MinValue;  // không gọi /api/oauth/usage trước thời điểm này
        DateTime lastProbe = DateTime.MinValue;
        int rateLimitStreak;
        bool busy;
        IntPtr lastHIcon = IntPtr.Zero;

        public TrayApp(bool firstRun)
        {
            menu = new ContextMenuStrip();
            miFive   = Disabled("Đang tải...");
            miWeek   = Disabled("");
            miStatus = Disabled("");
            menu.Items.AddRange(new ToolStripItem[] { miFive, miWeek, miStatus, new ToolStripSeparator() });
            menu.Items.Add("Làm mới ngay", null, async (s, e) => { await RefreshAsync(manual: true); });
            menu.Items.Add("Mở trang Usage trên claude.ai", null, (s, e) => Open("https://claude.ai/settings/usage"));
            miAuto = new ToolStripMenuItem("Khởi động cùng Windows");
            miAuto.Click += (s, e) =>
            {
                try { Startup.SetEnabled(!Startup.IsEnabled); }
                catch (Exception ex) { Balloon("Claude usage", "Không đổi được cài đặt: " + ex.Message, ToolTipIcon.Error); }
                miAuto.Checked = Startup.IsEnabled;
            };
            menu.Items.Add(miAuto);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Phiên bản " + Program.Version + " – trang tải về", null,
                (s, e) => Open("https://github.com/" + Program.Repo + "/releases/latest"));
            menu.Items.Add("Thoát", null, (s, e) => ExitThread());
            menu.Opening += (s, e) => { Render(); miAuto.Checked = Startup.IsEnabled; };

            tray = new NotifyIcon { ContextMenuStrip = menu, Visible = true, Text = "Claude usage: đang tải..." };
            tray.MouseClick += async (s, e) =>
            {
                if (e.Button != MouseButtons.Left) return;
                // Chỉ hỏi lại máy chủ nếu số liệu đã cũ hơn 1 phút, tránh bị giới hạn tần suất
                if (DateTime.Now - lastAttempt > TimeSpan.FromMinutes(1)) await RefreshAsync(manual: false);
                Balloon("Claude usage", DetailText(), ToolTipIcon.None);
            };
            SetIcon("..", Gray);

            // Timer 30 giây: cập nhật đếm ngược trên tooltip, và gọi máy chủ khi đến hạn
            timer = new Timer { Interval = 30000 };
            timer.Tick += async (s, e) =>
            {
                if (DateTime.Now >= nextFetch) await RefreshAsync(manual: false);
                else Render();
            };
            timer.Start();

            if (firstRun)
                Balloon("Claude Usage Tray đang chạy",
                    "Icon số % nằm ở góc phải taskbar (có thể trong mũi tên ^). Đã bật khởi động cùng Windows – tắt trong menu chuột phải.",
                    ToolTipIcon.Info);

            var _ = RefreshAsync(manual: false);
        }

        static ToolStripMenuItem Disabled(string text) => new ToolStripMenuItem(text) { Enabled = false };

        // ---------- Lấy số liệu ----------

        async Task RefreshAsync(bool manual)
        {
            if (busy) return;
            var now = DateTime.Now;
            bool inCooldown = now < cooldownUntil;
            bool allowProbe = (data == null || now - dataAt > ProbeWhenOlder) && now - lastProbe > ProbeMinGap;

            if (inCooldown && !allowProbe)
            {
                // Đang bị máy chủ giới hạn tần suất: không hỏi thêm, chỉ hiển thị lại
                if (nextFetch < cooldownUntil) nextFetch = cooldownUntil;
                Render();
                if (manual)
                    Balloon("Claude usage", "Máy chủ đang giới hạn tần suất, sẽ tự thử lại lúc " + cooldownUntil.ToString("HH:mm") + ".\n\n" + DetailText(), ToolTipIcon.None);
                return;
            }

            busy = true;
            FetchResult r;
            try { r = await Task.Run(() => UsageClient.Fetch(inCooldown, allowProbe)); }
            catch (Exception ex) { r = new FetchResult { Status = FetchStatus.Error, Message = ex.Message }; }
            finally { busy = false; }

            now = DateTime.Now;
            lastAttempt = now;
            lastResult = r;
            if (r.Probed) lastProbe = now;

            if (r.UsageEndpointRateLimited)
            {
                rateLimitStreak++;
                // Tôn trọng Retry-After; không có thì lùi dần 5 → 10 → 15 phút
                TimeSpan wait = r.RetryAfter ?? TimeSpan.FromTicks(PollInterval.Ticks * rateLimitStreak);
                if (wait < TimeSpan.FromMinutes(1)) wait = TimeSpan.FromMinutes(1);
                if (wait > MaxBackoff) wait = MaxBackoff;
                cooldownUntil = now + wait;
            }
            else if (!inCooldown && r.Status == FetchStatus.Ok)
            {
                rateLimitStreak = 0;
            }

            if (r.Status == FetchStatus.Ok)
            {
                data = r.Data;
                dataAt = now;
            }
            else if (r.Status == FetchStatus.NotLoggedIn || r.Status == FetchStatus.TokenExpired || r.Status == FetchStatus.NoQuota)
            {
                data = null;
            }

            nextFetch = now + PollInterval;
            if (cooldownUntil > nextFetch) nextFetch = cooldownUntil;
            // Cập nhật ngay sau giờ reset để số % về đúng giá trị mới
            foreach (var w in new[] { data?.FiveHour, data?.Week })
            {
                if (w?.ResetsAt == null) continue;
                var at = w.ResetsAt.Value.LocalDateTime.AddSeconds(30);
                if (at > now && at < nextFetch && at >= cooldownUntil) nextFetch = at;
            }

            Render();
            if (manual) Balloon("Claude usage", DetailText(), ToolTipIcon.None);
        }

        // ---------- Hiển thị ----------

        /// <summary>Nếu đã qua giờ reset thì coi như chu kỳ mới: 0%.</summary>
        static UsageWindow Effective(UsageWindow w)
        {
            if (w?.ResetsAt != null && w.ResetsAt.Value <= DateTimeOffset.Now)
                return new UsageWindow { Percent = 0, ResetsAt = null };
            return w ?? new UsageWindow();
        }

        string ErrorText()
        {
            switch (lastResult?.Status)
            {
                case FetchStatus.NotLoggedIn:  return "Chưa đăng nhập – hãy cài Claude Code và chạy lệnh claude để đăng nhập.";
                case FetchStatus.TokenExpired: return "Token hết hạn – mở Claude Code và gõ 1 lệnh bất kỳ để làm mới, rồi bấm Làm mới ngay.";
                case FetchStatus.NoQuota:      return "Tài khoản không có hạn mức 5 giờ/tuần (đang dùng API key hoặc gói không hỗ trợ).";
                case FetchStatus.RateLimited:  return "Máy chủ đang giới hạn tần suất, sẽ tự thử lại lúc " + nextFetch.ToString("HH:mm") + ".";
                case FetchStatus.Error:        return lastResult.Message ?? "Lỗi không xác định";
                default: return "Đang tải...";
            }
        }

        string StatusLine()
        {
            if (data == null) return null;
            var now = DateTime.Now;
            string note = null;
            if (lastResult != null && lastResult.Status != FetchStatus.Ok)
                note = lastResult.Status == FetchStatus.RateLimited ? "máy chủ giới hạn tần suất, thử lại lúc " + nextFetch.ToString("HH:mm") : lastResult.Message;
            if (note == null && now - dataAt <= StaleAfter) return "Cập nhật lúc " + dataAt.ToString("HH:mm");
            return "Số liệu lúc " + dataAt.ToString("HH:mm") + (note != null ? " · " + note : "");
        }

        string DetailText()
        {
            if (data == null) return ErrorText();
            var f = Effective(data.FiveHour);
            var w = Effective(data.Week);
            return LongLine("5 giờ", f, false) + "\n" + LongLine("Tuần", w, true) + "\n" + StatusLine();
        }

        static string ShortLine(string name, UsageWindow w)
        {
            if (w.ResetsAt == null) return string.Format("{0}: {1:0}%", name, w.Percent);
            return string.Format("{0}: {1:0}% · reset {2} (còn {3})", name, w.Percent, When(w.ResetsAt.Value, false), Left(w.ResetsAt.Value));
        }

        static string LongLine(string name, UsageWindow w, bool withDate)
        {
            if (w.ResetsAt == null) return string.Format("{0}: {1:0}% đã dùng", name, w.Percent);
            return string.Format("{0}: {1:0}% đã dùng – reset {2} (còn {3})", name, w.Percent, When(w.ResetsAt.Value, withDate), Left(w.ResetsAt.Value));
        }

        void Render()
        {
            if (data == null)
            {
                bool waiting = lastResult == null || lastResult.Status == FetchStatus.RateLimited;
                SetIcon(waiting ? ".." : "!", Gray);
                SetTooltip("Claude usage: " + ErrorText());
                miFive.Text = ErrorText();
                miWeek.Visible = false;
                miStatus.Visible = false;
                return;
            }

            var f = Effective(data.FiveHour);
            var w = Effective(data.Week);
            double worst = Math.Max(f.Percent, w.Percent);
            SetIcon(((int)Math.Round(f.Percent)).ToString(CultureInfo.InvariantCulture), worst >= 80 ? Red : worst >= 50 ? Orange : Green);

            string tip = ShortLine("5h", f) + "\n" + ShortLine("Tuần", w);
            if (DateTime.Now - dataAt > StaleAfter) tip += "\nSố liệu lúc " + dataAt.ToString("HH:mm");
            SetTooltip(tip);

            miFive.Text = LongLine("5 giờ", f, false);
            miWeek.Text = LongLine("Tuần", w, true);
            miWeek.Visible = true;
            miStatus.Text = StatusLine();
            miStatus.Visible = true;
        }

        static string Left(DateTimeOffset at)
        {
            var t = at - DateTimeOffset.Now;
            if (t <= TimeSpan.Zero) return "sắp reset";
            if (t.TotalDays >= 1) return string.Format("{0}d{1}h", (int)t.TotalDays, t.Hours);
            if (t.TotalHours >= 1) return string.Format("{0}h{1:00}m", (int)t.TotalHours, t.Minutes);
            return string.Format("{0}m", Math.Max(1, (int)Math.Ceiling(t.TotalMinutes)));
        }

        static string When(DateTimeOffset at, bool withDate)
        {
            var local = at.LocalDateTime;
            if (local.Date == DateTime.Today) return local.ToString("HH:mm", Vi);
            return local.ToString(withDate ? "ddd dd/MM HH:mm" : "ddd HH:mm", Vi);
        }

        // ---------- Icon trên khay: số % trên nền màu ----------

        [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr h);

        void SetIcon(string text, Color bg)
        {
            int s = SystemInformation.SmallIconSize.Width;
            using (var bmp = new Bitmap(s, s))
            using (var g = Graphics.FromImage(bmp))
            using (var brush = new SolidBrush(bg))
            using (var path = new GraphicsPath())
            using (var sf = (StringFormat)StringFormat.GenericTypographic.Clone())
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                g.Clear(Color.Transparent);

                int r = Math.Max(2, s / 5);
                path.AddArc(0, 0, r * 2, r * 2, 180, 90);
                path.AddArc(s - 1 - r * 2, 0, r * 2, r * 2, 270, 90);
                path.AddArc(s - 1 - r * 2, s - 1 - r * 2, r * 2, r * 2, 0, 90);
                path.AddArc(0, s - 1 - r * 2, r * 2, r * 2, 90, 90);
                path.CloseFigure();
                g.FillPath(brush, path);

                // Thu nhỏ cỡ chữ đến khi vừa khung
                sf.FormatFlags |= StringFormatFlags.NoWrap | StringFormatFlags.NoClip;
                string family = text.Length >= 3 ? "Arial Narrow" : "Segoe UI";
                float em = s * 0.95f;
                Font font = null;
                SizeF size;
                while (true)
                {
                    font?.Dispose();
                    font = new Font(family, em, FontStyle.Bold, GraphicsUnit.Pixel);
                    size = g.MeasureString(text, font, 1000, sf);
                    if ((size.Width <= s - 1 && size.Height <= s + 2) || em <= 4) break;
                    em -= 0.5f;
                }
                g.DrawString(text, font, Brushes.White, (s - size.Width) / 2, (s - size.Height) / 2, sf);
                font.Dispose();

                IntPtr h = bmp.GetHicon();
                var old = tray.Icon;
                tray.Icon = Icon.FromHandle(h);
                old?.Dispose();
                if (lastHIcon != IntPtr.Zero) DestroyIcon(lastHIcon);
                lastHIcon = h;
            }
        }

        // NotifyIcon.Text giới hạn 63 ký tự, Windows cho phép 127 → đặt qua reflection
        void SetTooltip(string t)
        {
            if (t.Length > 127) t = t.Substring(0, 127);
            if (t.Length <= 63) { tray.Text = t; return; }
            try
            {
                var type = typeof(NotifyIcon);
                const BindingFlags flags = BindingFlags.NonPublic | BindingFlags.Instance;
                type.GetField("text", flags).SetValue(tray, t);
                if ((bool)type.GetField("added", flags).GetValue(tray))
                    type.GetMethod("UpdateIcon", flags).Invoke(tray, new object[] { true });
            }
            catch { tray.Text = t.Substring(0, 63); }
        }

        void Balloon(string title, string text, ToolTipIcon icon)
        {
            if (string.IsNullOrEmpty(text)) return;
            if (text.Length > 250) text = text.Substring(0, 250);
            tray.ShowBalloonTip(8000, title, text, icon);
        }

        static void Open(string url)
        {
            try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { }
        }

        protected override void ExitThreadCore()
        {
            timer.Stop();
            tray.Visible = false;
            tray.Dispose();
            if (lastHIcon != IntPtr.Zero) DestroyIcon(lastHIcon);
            base.ExitThreadCore();
        }
    }
}
