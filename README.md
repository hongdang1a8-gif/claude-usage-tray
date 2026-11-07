# Claude Usage Tray

Icon nhỏ trên taskbar Windows cho biết bạn đã dùng bao nhiêu % hạn mức Claude (5 giờ và tuần), và khi nào thì reset.

![icon](docs/icons.png)

## Yêu cầu

- Windows 10/11 (dùng PowerShell 5.1 có sẵn, không cần cài thêm gì)
- Đã cài **Claude Code** và đăng nhập bằng tài khoản Claude **Pro / Max / Team** (dùng API key thì không có hạn mức 5h/tuần)

## Cài đặt

1. Tải file `ClaudeUsageTray-vX.Y.Z.zip` ở trang [Releases](../../releases/latest) rồi giải nén ra một thư mục bất kỳ.
2. Double-click **`install.cmd`**.

Widget được cài vào `%LOCALAPPDATA%\ClaudeUsageTray`, tự chạy mỗi khi đăng nhập Windows, không cần quyền Admin.
Bật/tắt tự chạy cùng Windows bất cứ lúc nào: click phải icon → **Khởi động cùng Windows** (có dấu tick là đang bật).
Muốn cài mà không bật tự chạy: mở cmd tại thư mục đó và chạy `install.cmd -NoAutostart`.

Nếu không thấy icon: bấm mũi tên **^** ở góc phải taskbar rồi kéo icon ra ngoài, hoặc vào
*Settings → Personalization → Taskbar → Other system tray icons* và bật **Windows PowerShell**.

## Sử dụng

| Thao tác | Kết quả |
|---|---|
| Nhìn icon | Số = % đã dùng của hạn mức 5h. Màu nền: xanh < 50%, cam 50–80%, đỏ ≥ 80% (tính theo hạn mức nào cao hơn trong 5h và tuần) |
| Rê chuột | `Claude 5h: 28% \| còn 1h23m` / `Tuần: 25% \| còn 1d23h` |
| Click trái | Cập nhật ngay và hiện giờ reset chính xác |
| Click phải | Menu: chi tiết, Làm mới, Mở trang Usage trên claude.ai, **Khởi động cùng Windows** (bật/tắt), Thoát |

Số liệu tự cập nhật mỗi 3 phút. Khi vượt 80% sẽ có một thông báo cảnh báo (mỗi chu kỳ một lần).
Muốn đổi các giá trị này: sửa `$RefreshMin` và `$WarnAt` ở đầu file `%LOCALAPPDATA%\ClaudeUsageTray\ClaudeUsageTray.ps1`.

## Icon hiện "!" màu xám

- **token hết hạn**: mở Claude Code và chạy một lệnh bất kỳ để token được làm mới, rồi click phải icon → *Làm mới ngay*.
- **chưa đăng nhập**: chạy `claude` rồi đăng nhập.
- **lỗi kết nối**: kiểm tra mạng/proxy.

## Bảo mật

Widget chỉ **đọc** token đăng nhập mà Claude Code lưu trên chính máy bạn (`~/.claude/.credentials.json`), không ghi vào file đó.
Token chỉ được gửi tới `api.anthropic.com`, không gửi đi đâu khác. Toàn bộ mã nguồn nằm trong `ClaudeUsageTray.ps1`, bạn có thể đọc trước khi cài.

## Gỡ cài đặt

Double-click **`uninstall.cmd`**.

## Cập nhật

Tải bản zip mới nhất ở [Releases](../../releases/latest) và chạy lại `install.cmd`; bản cũ sẽ được dừng và ghi đè.

## Phát hành bản mới (cho người bảo trì)

```bash
git tag v1.0.1 -m "v1.0.1"
git push origin v1.0.1
```

GitHub Actions ([release.yml](.github/workflows/release.yml)) sẽ tự đóng gói zip và tạo bản release kèm ghi chú thay đổi.

## Lưu ý

Dữ liệu lấy từ endpoint `api.anthropic.com/api/oauth/usage`, cũng là nguồn mà lệnh `/usage` của Claude Code dùng.
Endpoint này không có tài liệu chính thức nên Anthropic có thể thay đổi bất cứ lúc nào; khi đó widget cần được cập nhật.
