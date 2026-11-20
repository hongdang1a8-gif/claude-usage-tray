using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Net;
using System.Text;
using System.Web.Script.Serialization;

namespace ClaudeUsageTray
{
    /// <summary>Một chu kỳ hạn mức (5 giờ hoặc tuần).</summary>
    sealed class UsageWindow
    {
        public double Percent;            // 0..100
        public DateTimeOffset? ResetsAt;  // null = chưa bắt đầu chu kỳ
    }

    sealed class UsageData
    {
        public UsageWindow FiveHour = new UsageWindow();
        public UsageWindow Week = new UsageWindow();
    }

    enum FetchStatus
    {
        Ok,
        NotLoggedIn,   // không có file đăng nhập Claude Code
        TokenExpired,  // token trong file đã hết hạn / bị từ chối
        RateLimited,   // 429 và không lấy được số liệu bằng cách khác
        NoQuota,       // tài khoản không có hạn mức 5h/tuần (API key, gói không hỗ trợ)
        Error,         // lỗi mạng / lỗi khác
    }

    sealed class FetchResult
    {
        public FetchStatus Status;
        public UsageData Data;
        public string Message;
        /// <summary>Endpoint /api/oauth/usage trả về 429 (kể cả khi đã lấy được số liệu qua đường dự phòng).</summary>
        public bool UsageEndpointRateLimited;
        /// <summary>Giá trị header Retry-After của lần 429, nếu có.</summary>
        public TimeSpan? RetryAfter;
        public bool Probed;
    }

    /// <summary>
    /// Đọc token mà Claude Code lưu ở ~/.claude/.credentials.json (chỉ đọc, không ghi)
    /// và hỏi api.anthropic.com xem đã dùng bao nhiêu % hạn mức.
    /// </summary>
    static class UsageClient
    {
        const string UsageUrl = "https://api.anthropic.com/api/oauth/usage";
        const string MessagesUrl = "https://api.anthropic.com/v1/messages";
        // Model rẻ nhất, chỉ dùng cho yêu cầu dự phòng 1 token để đọc header hạn mức.
        const string ProbeModel = "claude-haiku-4-5";

        static readonly JavaScriptSerializer Json = new JavaScriptSerializer();

        public static string CredentialsPath
        {
            get
            {
                string dir = Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR");
                if (string.IsNullOrEmpty(dir))
                    dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude");
                return Path.Combine(dir, ".credentials.json");
            }
        }

        static string UserAgent => "ClaudeUsageTray/" + Program.Version;

        /// <param name="skipUsageEndpoint">Đang trong thời gian chờ sau 429: không gọi /api/oauth/usage.</param>
        /// <param name="allowProbe">Cho phép dùng đường dự phòng (gửi 1 yêu cầu 1 token tới Haiku để đọc header hạn mức).</param>
        public static FetchResult Fetch(bool skipUsageEndpoint, bool allowProbe)
        {
            string token;
            var credError = ReadToken(out token);
            if (credError != null) return credError;

            var result = new FetchResult { Status = FetchStatus.RateLimited, Message = "Máy chủ đang giới hạn tần suất" };

            if (!skipUsageEndpoint)
            {
                var r = Send("GET", UsageUrl, token, null);
                if (r.Status == 200)
                {
                    try
                    {
                        var data = ParseUsageJson(r.Body);
                        if (data == null)
                            return new FetchResult { Status = FetchStatus.NoQuota, Message = "Tài khoản này không có hạn mức 5 giờ/tuần" };
                        return new FetchResult { Status = FetchStatus.Ok, Data = data };
                    }
                    catch (Exception ex)
                    {
                        return new FetchResult { Status = FetchStatus.Error, Message = "Dữ liệu trả về không đọc được: " + ex.Message };
                    }
                }
                if (r.Status == 401)
                    return new FetchResult { Status = FetchStatus.TokenExpired, Message = "Token không còn hợp lệ" };
                if (r.Status == 429)
                {
                    result.UsageEndpointRateLimited = true;
                    result.RetryAfter = ParseRetryAfter(r.Headers?["Retry-After"]);
                }
                else if (r.Status == 0)
                {
                    return new FetchResult { Status = FetchStatus.Error, Message = "Lỗi kết nối: " + r.Error };
                }
                else
                {
                    // 403/404/5xx...: thử đường dự phòng nếu được phép, không thì báo lỗi
                    result.Status = FetchStatus.Error;
                    result.Message = "Máy chủ trả về lỗi HTTP " + r.Status;
                    if (!allowProbe) return result;
                }
            }

            if (allowProbe)
            {
                result.Probed = true;
                var p = Probe(token);
                if (p.Data != null)
                {
                    result.Status = FetchStatus.Ok;
                    result.Data = p.Data;
                    result.Message = null;
                }
                else if (p.Status == 401 && !result.UsageEndpointRateLimited)
                {
                    // (Nếu /api/oauth/usage vừa trả 429 thì token vẫn hợp lệ, không báo hết hạn)
                    return new FetchResult { Status = FetchStatus.TokenExpired, Message = "Token không còn hợp lệ" };
                }
            }
            return result;
        }

        static FetchResult ReadToken(out string token)
        {
            token = null;
            string path = CredentialsPath;
            if (!File.Exists(path))
                return new FetchResult { Status = FetchStatus.NotLoggedIn, Message = "Chưa đăng nhập Claude Code trên máy này" };
            try
            {
                string text;
                // Mở cho phép chia sẻ để không chặn Claude Code khi nó đang ghi file
                using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (var sr = new StreamReader(fs, Encoding.UTF8))
                    text = sr.ReadToEnd();

                var root = Json.DeserializeObject(text) as Dictionary<string, object>;
                var oauth = Get(root, "claudeAiOauth") as Dictionary<string, object>;
                token = Get(oauth, "accessToken") as string;
                if (string.IsNullOrEmpty(token))
                    return new FetchResult { Status = FetchStatus.NotLoggedIn, Message = "Chưa đăng nhập Claude Code bằng tài khoản Claude (Pro/Max/Team)" };

                object exp = Get(oauth, "expiresAt");
                if (exp != null)
                {
                    long ms = Convert.ToInt64(exp, CultureInfo.InvariantCulture);
                    if (DateTimeOffset.FromUnixTimeMilliseconds(ms) < DateTimeOffset.UtcNow)
                        return new FetchResult { Status = FetchStatus.TokenExpired, Message = "Token đăng nhập đã hết hạn" };
                }
                return null;
            }
            catch (Exception ex)
            {
                return new FetchResult { Status = FetchStatus.Error, Message = "Không đọc được file đăng nhập: " + ex.Message };
            }
        }

        // ---------- /api/oauth/usage ----------

        static UsageData ParseUsageJson(string body)
        {
            var root = Json.DeserializeObject(body) as Dictionary<string, object>;
            if (root == null) throw new FormatException("không phải JSON object");
            var five = Get(root, "five_hour") as Dictionary<string, object>;
            var week = Get(root, "seven_day") as Dictionary<string, object>;
            if (five == null && week == null && !root.ContainsKey("five_hour") && !root.ContainsKey("seven_day"))
                return null;
            return new UsageData { FiveHour = ParseWindow(five), Week = ParseWindow(week) };
        }

        static UsageWindow ParseWindow(Dictionary<string, object> o)
        {
            var w = new UsageWindow();
            if (o == null) return w;
            object u = Get(o, "utilization");
            if (u != null) w.Percent = Convert.ToDouble(u, CultureInfo.InvariantCulture);
            if (Get(o, "resets_at") is string s && DateTimeOffset.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var t))
                w.ResetsAt = t;
            return w;
        }

        // ---------- Đường dự phòng: đọc header anthropic-ratelimit-unified-* ----------
        // Endpoint /api/oauth/usage hay trả 429 nếu bị hỏi nhiều. Khi đó gửi 1 yêu cầu
        // 1 token tới model rẻ nhất; mọi phản hồi (kể cả 429) đều kèm header hạn mức.

        sealed class ProbeResult { public int Status; public UsageData Data; }

        static ProbeResult Probe(string token)
        {
            string body = "{\"model\":\"" + ProbeModel + "\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\".\"}]}";
            var r = Send("POST", MessagesUrl, token, body);
            var res = new ProbeResult { Status = r.Status };
            var h = r.Headers;
            if (h == null) return res;

            string h5 = h["anthropic-ratelimit-unified-5h-utilization"];
            string h7 = h["anthropic-ratelimit-unified-7d-utilization"];
            string status = h["anthropic-ratelimit-unified-status"];
            if (h5 == null && h7 == null && status == null) return res;

            var d = new UsageData();
            d.FiveHour.Percent = ParseDouble(h5) * 100;
            d.FiveHour.ResetsAt = ParseUnix(h["anthropic-ratelimit-unified-5h-reset"]);
            d.Week.Percent = ParseDouble(h7) * 100;
            d.Week.ResetsAt = ParseUnix(h["anthropic-ratelimit-unified-7d-reset"]);

            if (status == "rejected" && d.FiveHour.Percent == 0 && d.Week.Percent == 0)
            {
                string claim = h["anthropic-ratelimit-unified-representative-claim"];
                if (claim == "five_hour") d.FiveHour.Percent = 100;
                else if (claim == "seven_day") d.Week.Percent = 100;
            }
            if (d.FiveHour.ResetsAt == null && d.Week.ResetsAt == null)
                d.FiveHour.ResetsAt = ParseUnix(h["anthropic-ratelimit-unified-reset"]);
            res.Data = d;
            return res;
        }

        // ---------- HTTP ----------

        sealed class HttpResult
        {
            public int Status;               // 0 = không kết nối được
            public string Body;
            public WebHeaderCollection Headers;
            public string Error;
        }

        static HttpResult Send(string method, string url, string token, string jsonBody)
        {
            var res = new HttpResult();
            try
            {
                var req = (HttpWebRequest)WebRequest.Create(url);
                req.Method = method;
                req.Timeout = 20000;
                req.ReadWriteTimeout = 20000;
                req.UserAgent = UserAgent;
                req.Accept = "application/json";
                req.AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate;
                req.Headers["Authorization"] = "Bearer " + token;
                req.Headers["anthropic-beta"] = "oauth-2025-04-20";
                if (jsonBody != null)
                {
                    req.Headers["anthropic-version"] = "2023-06-01";
                    req.ContentType = "application/json";
                    byte[] bytes = Encoding.UTF8.GetBytes(jsonBody);
                    req.ContentLength = bytes.Length;
                    using (var s = req.GetRequestStream()) s.Write(bytes, 0, bytes.Length);
                }
                using (var resp = (HttpWebResponse)req.GetResponse())
                    Fill(res, resp);
            }
            catch (WebException ex) when (ex.Response is HttpWebResponse resp)
            {
                using (resp) Fill(res, resp);
            }
            catch (Exception ex)
            {
                res.Status = 0;
                res.Error = (ex.InnerException ?? ex).Message;
            }
            return res;
        }

        static void Fill(HttpResult res, HttpWebResponse resp)
        {
            res.Status = (int)resp.StatusCode;
            res.Headers = resp.Headers;
            using (var sr = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
                res.Body = sr.ReadToEnd();
        }

        // ---------- Tiện ích ----------

        static object Get(Dictionary<string, object> d, string key)
        {
            if (d == null) return null;
            return d.TryGetValue(key, out var v) ? v : null;
        }

        static double ParseDouble(string s)
        {
            return double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var v) ? v : 0;
        }

        static DateTimeOffset? ParseUnix(string s)
        {
            if (long.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out var v) && v > 0)
                return DateTimeOffset.FromUnixTimeSeconds(v);
            return null;
        }

        static TimeSpan? ParseRetryAfter(string s)
        {
            if (string.IsNullOrWhiteSpace(s)) return null;
            if (double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var sec) && sec >= 0)
                return TimeSpan.FromSeconds(sec);
            if (DateTimeOffset.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var at))
            {
                var d = at - DateTimeOffset.UtcNow;
                return d > TimeSpan.Zero ? d : TimeSpan.Zero;
            }
            return null;
        }
    }
}
