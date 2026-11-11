# Tắt gạch đỏ trong ChatGPT và Claude Desktop

Script dành cho Windows 10, chạy bằng Windows PowerShell 5.1. Script tìm tệp `Preferences` của ChatGPT Desktop và Claude Desktop ở các vị trí được hỗ trợ cho tài khoản Windows hiện tại. Mỗi lần sửa, script đặt `spellcheck.dictionaries` thành `["xx-XX"]` và tạo bản sao lưu nguyên gốc cạnh tệp. Khóa `use_spelling_service` được giữ nguyên nếu đã có.

## Cách dùng

1. Mở [Disable-DesktopSpellcheck.ps1](./Disable-DesktopSpellcheck.ps1) và chọn **Download raw file**. Mở Windows PowerShell trong thư mục chứa tệp đã tải.
2. Xem trước các tệp sẽ được sửa. `-WhatIf` chỉ hiển thị kết quả kiểm tra.

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\Disable-DesktopSpellcheck.ps1 -WhatIf
   ```

3. Lưu bản nháp và thoát hẳn hai ứng dụng, kể cả từ khay hệ thống nếu có. Chạy lệnh sau rồi mở lại ứng dụng.

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\Disable-DesktopSpellcheck.ps1
   ```

Mặc định script xử lý cả hai ứng dụng. Thêm `-App Claude` hoặc `-App ChatGPT` vào cuối lệnh để chọn một ứng dụng. Khi tạo shortcut trên Desktop, dùng lệnh tương ứng với đường dẫn đầy đủ đến tệp `.ps1` trong dấu ngoặc kép. Thêm `-NoExit` trước `-File` để giữ cửa sổ mở sau khi chạy.

Nếu PowerShell báo tệp tải về chưa được ký, hãy xem lại nội dung script rồi chạy `Unblock-File -LiteralPath .\Disable-DesktopSpellcheck.ps1` trước khi thử lại.

## Đọc kết quả

| Trạng thái | Ý nghĩa |
| --- | --- |
| `WOULD UPDATE` | Tệp đã qua kiểm tra và sẽ được sửa khi chạy thật. |
| `UPDATED` | Đã sửa. Dòng `Backup` bên dưới ghi đường dẫn bản sao lưu. |
| `ALREADY SET` | Tệp đã có giá trị `["xx-XX"]`. |
| `RUNNING` | Hãy thoát hẳn ứng dụng rồi chạy lại. |
| `NOT FOUND` | Không tìm thấy tệp `Preferences` tại các vị trí được hỗ trợ. |
| `FAILED` | Xem chi tiết dưới đường dẫn tệp. Nếu báo `Invalid JSON token`, hãy kiểm tra cú pháp JSON gần vị trí được báo. Giá trị đúng có dấu ngoặc kép, `"dictionaries":["xx-XX"]`. |

## Khôi phục

Thoát hẳn ứng dụng. Chép tệp `.bak` được ghi ở dòng `Backup` đè lên tệp `Preferences` tương ứng, rồi mở lại ứng dụng. Bản sao lưu khôi phục toàn bộ nội dung tệp tại thời điểm chạy script.
