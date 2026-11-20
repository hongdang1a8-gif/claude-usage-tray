# Claude Usage Tray

> [!IMPORTANT]
> **Dự án đang tạm dừng. Hiện khuyên dùng [Claude Code Usage Monitor](https://github.com/CodeZeno/Claude-Code-Usage-Monitor)** (CodeZeno, mã nguồn mở MIT).
> App đó đã ổn định qua nhiều bản phát hành, tự làm mới token khi hết hạn, xử lý tốt lỗi "giới hạn tần suất" (429) và tự cập nhật.
> Xem hướng dẫn ở mục [Dùng Claude Code Usage Monitor](#dùng-claude-code-usage-monitor-khuyên-dùng) bên dưới.

Icon nhỏ trên taskbar Windows cho biết bạn đã dùng bao nhiêu % hạn mức Claude (5 giờ và tuần), và khi nào thì reset.

![icon](docs/icons.png)

## Dùng Claude Code Usage Monitor (khuyên dùng)

### Cài đặt

Mở **Terminal** (hoặc PowerShell) và chạy:

```powershell
winget install CodeZeno.ClaudeCodeUsageMonitor
```

Hoặc tải `claude-code-usage-monitor.exe` ở [trang Releases của họ](https://github.com/CodeZeno/Claude-Code-Usage-Monitor/releases) rồi double-click.
Nếu Windows hiện *"Windows protected your PC"* (SmartScreen): bấm **More info → Run anyway**.
Nếu máy bật **Smart App Control** và nó chặn hẳn file exe, xem [issue #225 bên repo của họ](https://github.com/CodeZeno/Claude-Code-Usage-Monitor/issues/225).

Yêu cầu: Windows 10/11, đã đăng nhập Claude Code (CLI hoặc Claude desktop app) bằng tài khoản Pro / Max / Team.

### Sử dụng cơ bản

- Số liệu hiện ngay trên thanh taskbar: % đã dùng và thời gian còn lại đến khi reset, cho hạn mức 5 giờ và tuần.
- Click trái icon trên khay: ẩn/hiện widget. Click phải: menu.
- **Settings** (hoặc chạy `claude-code-usage-monitor --dashboard`): đổi chu kỳ cập nhật (mặc định 15 phút), bật khởi động cùng Windows,
  chọn ngôn ngữ, thêm nhiều tài khoản Claude Code.
- Hướng dẫn đầy đủ: [USER_GUIDE.md](https://github.com/CodeZeno/Claude-Code-Usage-Monitor/blob/main/USER_GUIDE.md).

### Đang dùng bản PowerShell cũ của dự án này (v1.x)?

Gỡ bản cũ trước để không chạy song song: mở thư mục đã giải nén zip và double-click **`uninstall.cmd`**
(hoặc xoá thư mục `%LOCALAPPDATA%\ClaudeUsageTray` và shortcut `ClaudeUsageTray` trong thư mục Startup: nhấn Win+R, gõ `shell:startup`).

### Hạn chế đã biết

- **Chưa hiển thị email của tài khoản đang được đo.** Khi có nhiều tài khoản, mỗi tài khoản chỉ mang cái tên bạn tự đặt trong Settings.
  Đã soạn góp ý gửi tác giả: [docs/upstream-feature-request.md](docs/upstream-feature-request.md).
  Trong lúc chờ, kiểm tra tài khoản đang đăng nhập bằng lệnh `/status` trong Claude Code.
- Giao diện chưa có tiếng Việt (có tiếng Anh và 14 ngôn ngữ khác).

---

## Bản exe của dự án này (v2.0, chưa phát hành)

Phần dưới đây mô tả bản viết lại thành một file `ClaudeUsageTray.exe`. Mã nguồn nằm trong [`src`](src), build được nhưng
**chưa phát hành và chưa được kiểm thử trên Windows thật**; giữ lại để tham khảo hoặc phát triển tiếp nếu cần
(ví dụ cần giao diện tiếng Việt hoặc hiển thị email tài khoản).

### Yêu cầu

- Windows 10/11 (không cần cài thêm gì, dùng .NET Framework có sẵn trong Windows)
- Đã cài **Claude Code** và đăng nhập bằng tài khoản Claude **Pro / Max / Team** (dùng API key thì không có hạn mức 5h/tuần)

### Cài đặt

1. Build exe (xem mục *Build từ mã nguồn*) hoặc tải từ tab **Actions** → lần chạy mới nhất → **Artifacts**.
2. Double-click để chạy. Xong.

Lần chạy đầu, app tự bật **Khởi động cùng Windows** (tắt được trong menu chuột phải). Không cần quyền Admin.
Nên để file exe ở một chỗ cố định (ví dụ `Documents`) trước khi chạy; nếu sau này chuyển chỗ thì chạy lại file ở chỗ mới là được.

Windows có thể hiện *"Windows protected your PC"* vì file chưa được ký số: bấm **More info → Run anyway**.

Nếu không thấy icon: bấm mũi tên **^** ở góc phải taskbar rồi kéo icon ra ngoài.

### Sử dụng

| Thao tác | Kết quả |
|---|---|
| Nhìn icon | Số = % đã dùng của hạn mức 5 giờ. Màu nền: xanh < 50%, cam 50–80%, đỏ ≥ 80% (theo hạn mức nào cao hơn trong 5 giờ và tuần) |
| Rê chuột | `5h: 28% · reset 14:30 (còn 1h23m)` / `Tuần: 25% · reset T2 02:59 (còn 1d23h)` |
| Click trái | Hiện thông báo chi tiết |
| Click phải | Menu: chi tiết, Làm mới ngay, Mở trang Usage trên claude.ai, Khởi động cùng Windows, Thoát |

Số liệu tự cập nhật mỗi 5 phút, và ngay sau giờ reset.

### Icon hiện "!" hoặc ".." màu xám

- **..** – đang tải, hoặc máy chủ đang giới hạn tần suất (xem bên dưới). App tự thử lại, không cần làm gì.
- **! token hết hạn** – mở Claude Code và gõ 1 lệnh bất kỳ để token được làm mới, rồi click phải icon → *Làm mới ngay*.
- **! chưa đăng nhập** – chạy `claude` rồi đăng nhập.

#### "Bị giới hạn tần suất" là gì?

Số liệu được lấy từ `api.anthropic.com/api/oauth/usage` (cũng là nguồn của lệnh `/usage` trong Claude Code).
Endpoint này giới hạn số lần hỏi; nếu hỏi quá dày nó trả lỗi **429** và bắt chờ. Bản cũ (v1.x) hỏi mỗi 3 phút và mỗi lần click,
nên dễ bị chặn và khi đó icon đứng ở "..".

Từ v2.0:
- Hỏi thưa hơn (5 phút), click trái không hỏi lại nếu vừa hỏi chưa tới 1 phút.
- Khi bị 429: chờ đúng thời gian máy chủ yêu cầu (tối đa 15 phút) rồi mới hỏi lại, trong lúc đó vẫn giữ số liệu cũ trên icon.
- Nếu vẫn chưa có số liệu (hoặc số liệu cũ hơn 15 phút), app lấy số liệu bằng đường dự phòng: gửi 1 yêu cầu siêu nhỏ
  (1 token, model Haiku) và đọc phần header hạn mức trong phản hồi. Mỗi lần như vậy tốn một lượng hạn mức không đáng kể,
  và chỉ xảy ra tối đa 1 lần / 10 phút khi endpoint chính đang bị chặn.

### Bảo mật

App chỉ **đọc** token đăng nhập mà Claude Code lưu trên chính máy bạn (`%USERPROFILE%\.claude\.credentials.json`), không ghi vào file đó.
Token chỉ được gửi tới `api.anthropic.com`. Toàn bộ mã nguồn nằm trong thư mục [`src`](src).

### Gỡ cài đặt

Click phải icon → bỏ tick **Khởi động cùng Windows** → **Thoát**, rồi xoá file exe.

### Đang dùng bản cũ (v1.x, chạy bằng PowerShell)?

- Bản v1.2.0 sẽ báo có bản mới: click phải icon → **Cập nhật lên v2.0.0** là xong.
- Hoặc tải `ClaudeUsageTray.exe` và chạy: exe tự tắt bản PowerShell cũ, xoá shortcut Startup cũ và giữ lựa chọn tự khởi động.

### Build từ mã nguồn (cho người bảo trì)

Cần .NET SDK 8 (build được trên Windows, Linux hoặc macOS):

```bash
dotnet build src/ClaudeUsageTray.csproj -c Release -o build
```

Kết quả: `build/ClaudeUsageTray.exe`. Mỗi lần push, GitHub Actions cũng build sẵn exe (tab **Actions** → chọn lần chạy → **Artifacts**).

Phát hành bản mới: tăng `<Version>` trong `src/ClaudeUsageTray.csproj`, commit rồi tạo tag:

```bash
git tag v2.0.1 -m "v2.0.1"
git push origin main v2.0.1
```

[Workflow](.github/workflows/release.yml) sẽ build và tạo bản release kèm `ClaudeUsageTray.exe`.

### Lưu ý

Endpoint `api/oauth/usage` không có tài liệu chính thức nên Anthropic có thể thay đổi bất cứ lúc nào; khi đó app cần được cập nhật.
Cách xử lý giới hạn tần suất tham khảo từ [Claude-Code-Usage-Monitor](https://github.com/CodeZeno/Claude-Code-Usage-Monitor).
