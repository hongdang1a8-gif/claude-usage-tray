using System;
using System.Net;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;

namespace ClaudeUsageTray
{
    static class Program
    {
        public const string Repo = "hongdang1a8-gif/claude-usage-tray";

        public static readonly string Version =
            typeof(Program).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion?.Split('+')[0]
            ?? typeof(Program).Assembly.GetName().Version.ToString(3);

        [STAThread]
        static void Main()
        {
            // Chỉ chạy 1 bản
            using (var mutex = new Mutex(true, @"Local\ClaudeUsageTray.exe", out bool created))
            {
                if (!created) return;

                ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
                // Dùng proxy hệ thống kèm thông tin đăng nhập Windows (mạng công ty)
                if (WebRequest.DefaultWebProxy != null)
                    WebRequest.DefaultWebProxy.Credentials = CredentialCache.DefaultCredentials;

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                SynchronizationContext.SetSynchronizationContext(new WindowsFormsSynchronizationContext());

                bool firstRun = false;
                try { firstRun = Startup.Initialize(); } catch { }

                Application.Run(new TrayApp(firstRun));
            }
        }
    }
}
