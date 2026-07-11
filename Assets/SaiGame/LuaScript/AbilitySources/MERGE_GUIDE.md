# Hướng Dẫn Gộp Các Ability Thành `ability_all.lua`

Trong thư mục `AbilitySources`, việc gộp (merge) các file script kỹ năng (ability) riêng lẻ thành một file duy nhất `ability_all.lua` cần được thực hiện dựa trên thứ tự được định nghĩa trong file `ability_order.txt`. 

## 1. Nguyên Tắc Hoạt Động
- File `ability_order.txt` chứa danh sách tên các file script được xếp theo thứ tự ưu tiên hoặc thứ tự khởi tạo.
- (Ví dụ: `config.lua` thường phải đứng đầu tiên để khởi tạo các thiết lập và hàm dùng chung trước khi các kỹ năng khác được nạp).
- Nội dung của `ability_all.lua` chính là tổng hợp tất cả mã nguồn (source code) từ các file con, được nối lại với nhau theo đúng trình tự từ trên xuống dưới của `ability_order.txt`.

## 2. Cách Thực Hiện Thủ Công
1. Mở file `ability_order.txt` để xem danh sách và thứ tự các file.
2. Tạo (hoặc làm rỗng) file `ability_all.lua`.
3. Lần lượt mở các file có trong danh sách (từ trên xuống dưới).
4. Copy toàn bộ nội dung của từng file và paste tiếp nối vào trong file `ability_all.lua`.
5. Lưu file `ability_all.lua`.

## 3. Cách Thực Hiện Tự Động Bằng Command/Script

Thay vì copy-paste thủ công, bạn có thể tự động hóa việc gộp file này bằng dòng lệnh. 

### Dành cho Windows (PowerShell)
Mở **PowerShell** tại thư mục `AbilitySources` và chạy lệnh sau:
## 3. Cách Thực Hiện Tự Động

### Cách thực hiện (Cho mọi hệ điều hành Windows)
Bạn chỉ cần click đúp vào file `merge_abilities.bat` (hoặc chạy lệnh `.\merge_abilities.bat` từ Terminal).

Script này đã được nâng cấp để sử dụng lõi PowerShell, giúp đảm bảo việc đọc file cực kỳ an toàn (chuẩn UTF-8, không bị lỗi dính text tên file, không bỏ sót dòng).

---
**Lưu Ý Quan Trọng:** 
- Nếu bạn thêm một file kỹ năng mới (ví dụ `new_skill.lua`), bạn **bắt buộc phải khai báo tên file đó** vào trong `ability_order.txt` trước khi chạy script gộp.
- Hạn chế tự ý thay đổi thứ tự của các file có sẵn trong `ability_order.txt` nếu bạn không nắm rõ về luồng khởi tạo (đặc biệt là đối với các file gốc như `config.lua`).
