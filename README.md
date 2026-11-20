# Claude Usage Tray

Icon nhỏ trên taskbar Windows cho biết bạn đã dùng bao nhiêu % hạn mức Claude (5 giờ và tuần), và khi nào thì reset.

![icon](docs/icons.png)

## Yêu cầu

- Windows 10/11 (không cần cài thêm gì, dùng .NET Framework có sẵn trong Windows)
- Đã cài **Claude Code** và đăng nhập bằng tài khoản Claude **Pro / Max / Team** (dùng API key thì không có hạn mức 5h/tuần)

## Cài đặt

1. Tải **`ClaudeUsageTray.exe`** ở trang [Releases](../../releases/latest).
2. Double-click để chạy. Xong.

Lần chạy đầu, app tự bật **Khởi động cùng Windows** (tắt được trong menu chuột phải). Không cần quyền Admin.
Nên để file exe ở một chỗ cố định (ví dụ `Documents`) trước khi chạy; nếu sau này chuyển chỗ thì chạy lại file ở chỗ mới là được.

Windows có thể hiện *"Windows protected your PC"* vì file chưa được ký số: bấm **More info → Run anyway**.

Nếu không thấy icon: bấm mũi tên **^** ở góc phải taskbar rồi kéo icon ra ngoài.

## Sử dụng

| Thao tác | Kết quả |
|---|---|
| Nhìn icon | Số = % đã dùng của hạn mức 5 giờ. Màu nền: xanh < 50%, cam 50–80%, đỏ ≥ 80% (theo hạn mức nào cao hơn trong 5 giờ và tuần) |
| Rê chuột | `5h: 28% · reset 14:30 (còn 1h23m)` / `Tuần: 25% · reset T2 02:59 (còn 1d23h)` |
| Click trái | Hiện thông báo chi tiết |
| Click phải | Menu: chi tiết, Làm mới ngay, Mở trang Usage trên claude.ai, Khởi động cùng Windows, Thoát |

Số liệu tự cập nhật mỗi 5 phút, và ngay sau giờ reset.

## Icon hiện "!" hoặc ".." màu xám

- **..** – đang tải, hoặc máy chủ đang giới hạn tần suất (xem bên dưới). App tự thử lại, không cần làm gì.
- **! token hết hạn** – mở Claude Code và gõ 1 lệnh bất kỳ để token được làm mới, rồi click phải icon → *Làm mới ngay*.
- **! chưa đăng nhập** – chạy `claude` rồi đăng nhập.

### "Bị giới hạn tần suất" là gì?

Số liệu được lấy từ `api.anthropic.com/api/oauth/usage` (cũng là nguồn của lệnh `/usage` trong Claude Code).
Endpoint này giới hạn số lần hỏi; nếu hỏi quá dày nó trả lỗi **429** và bắt chờ. Bản cũ (v1.x) hỏi mỗi 3 phút và mỗi lần click,
nên dễ bị chặn và khi đó icon đứng ở "..".

Từ v2.0:
- Hỏi thưa hơn (5 phút), click trái không hỏi lại nếu vừa hỏi chưa tới 1 phút.
- Khi bị 429: chờ đúng thời gian máy chủ yêu cầu (tối đa 15 phút) rồi mới hỏi lại, trong lúc đó vẫn giữ số liệu cũ trên icon.
- Nếu vẫn chưa có số liệu (hoặc số liệu cũ hơn 15 phút), app lấy số liệu bằng đường dự phòng: gửi 1 yêu cầu siêu nhỏ
  (1 token, model Haiku) và đọc phần header hạn mức trong phản hồi. Mỗi lần như vậy tốn một lượng hạn mức không đáng kể,
  và chỉ xảy ra tối đa 1 lần / 10 phút khi endpoint chính đang bị chặn.

## Bảo mật

App chỉ **đọc** token đăng nhập mà Claude Code lưu trên chính máy bạn (`%USERPROFILE%\.claude\.credentials.json`), không ghi vào file đó.
Token chỉ được gửi tới `api.anthropic.com`. Toàn bộ mã nguồn nằm trong thư mục [`src`](src).

## Gỡ cài đặt

Click phải icon → bỏ tick **Khởi động cùng Windows** → **Thoát**, rồi xoá file exe.

## Đang dùng bản cũ (v1.x, chạy bằng PowerShell)?

- Bản v1.2.0 sẽ báo có bản mới: click phải icon → **Cập nhật lên v2.0.0** là xong.
- Hoặc tải `ClaudeUsageTray.exe` và chạy: exe tự tắt bản PowerShell cũ, xoá shortcut Startup cũ và giữ lựa chọn tự khởi động.

## Build từ mã nguồn (cho người bảo trì)

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

## Lưu ý

Endpoint `api/oauth/usage` không có tài liệu chính thức nên Anthropic có thể thay đổi bất cứ lúc nào; khi đó app cần được cập nhật.
Cách xử lý giới hạn tần suất tham khảo từ [Claude-Code-Usage-Monitor](https://github.com/CodeZeno/Claude-Code-Usage-Monitor).
