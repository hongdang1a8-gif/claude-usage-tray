using System;
using System.Diagnostics;
using System.IO;
using System.Management;
using Microsoft.Win32;

namespace ClaudeUsageTray
{
    /// <summary>Khởi động cùng Windows (HKCU\...\Run, không cần quyền Admin) và dọn bản PowerShell cũ (v1.x).</summary>
    static class Startup
    {
        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        const string AppKey = @"Software\ClaudeUsageTray";
        const string ValueName = "ClaudeUsageTray";

        static string ExePath => Process.GetCurrentProcess().MainModule.FileName;
        static string Command => "\"" + ExePath + "\"";

        public static bool IsEnabled
        {
            get
            {
                using (var k = Registry.CurrentUser.OpenSubKey(RunKey))
                    return k?.GetValue(ValueName) is string;
            }
        }

        public static void SetEnabled(bool on)
        {
            using (var k = Registry.CurrentUser.CreateSubKey(RunKey))
            {
                if (on) k.SetValue(ValueName, Command);
                else k.DeleteValue(ValueName, false);
            }
        }

        /// <summary>
        /// Chạy lúc mở app. Trả về true nếu đây là lần chạy đầu tiên (để hiện lời chào).
        /// - Lần đầu: bật khởi động cùng Windows.
        /// - Nếu file exe đã bị chuyển chỗ: cập nhật lại đường dẫn khởi động.
        /// - Nếu còn bản PowerShell cũ: tắt nó và chuyển sang exe.
        /// </summary>
        public static bool Initialize()
        {
            bool firstRun;
            using (var k = Registry.CurrentUser.CreateSubKey(AppKey))
            {
                firstRun = k.GetValue("Initialized") == null;
                k.SetValue("Initialized", 1, RegistryValueKind.DWord);
            }

            bool hadLegacyAutostart = RemoveLegacy();

            if (firstRun || hadLegacyAutostart) SetEnabled(true);
            else if (IsEnabled)
            {
                using (var k = Registry.CurrentUser.OpenSubKey(RunKey))
                    if (!string.Equals(k?.GetValue(ValueName) as string, Command, StringComparison.OrdinalIgnoreCase))
                        SetEnabled(true);
            }
            return firstRun;
        }

        /// <summary>Gỡ bản v1.x (PowerShell + start.vbs). Trả về true nếu bản cũ đang được bật tự khởi động.</summary>
        static bool RemoveLegacy()
        {
            bool hadAutostart = false;
            try
            {
                string lnk = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup), "ClaudeUsageTray.lnk");
                if (File.Exists(lnk)) { File.Delete(lnk); hadAutostart = true; }
            }
            catch { }

            try
            {
                using (var searcher = new ManagementObjectSearcher(
                    "SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name='powershell.exe' OR Name='pwsh.exe'"))
                {
                    foreach (ManagementObject p in searcher.Get())
                    {
                        string cmd = p["CommandLine"] as string;
                        if (cmd != null && cmd.IndexOf("ClaudeUsageTray.ps1", StringComparison.OrdinalIgnoreCase) >= 0)
                        {
                            try { Process.GetProcessById(Convert.ToInt32(p["ProcessId"])).Kill(); } catch { }
                        }
                    }
                }
            }
            catch { }

            try
            {
                string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ClaudeUsageTray");
                foreach (var f in new[] { "ClaudeUsageTray.ps1", "start.vbs" })
                {
                    string path = Path.Combine(dir, f);
                    if (File.Exists(path)) File.Delete(path);
                }
            }
            catch { }

            return hadAutostart;
        }
    }
}
