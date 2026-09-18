# HƯỚNG DẪN SỬ DỤNG HỆ THỐNG QUẢN LÝ TIẾN ĐỘ CÔNG VIỆC (PTPK)

Hệ thống **Quản lý tiến độ công việc** hỗ trợ theo dõi tiến độ thực hiện các dự án mở rộng cơ sở y tế, phòng khám, bệnh viện đa khoa trên toàn hệ thống TTH Group theo mô hình **Đa chi nhánh** và **Đa phòng ban**.

---

## MỤC LỤC
1. [Tổng quan giao diện chính](#1-tổng-quan-giao-diện-chính)
2. [Cơ chế phân quyền & Giám sát chi nhánh](#2-cơ-chế-phân-quyền--giám-sát-chi-nhánh)
3. [Quản lý danh mục dự án (Portfolio)](#3-quản-lý-danh-mục-dự-án-portfolio)
4. [Theo dõi tiến độ chi tiết & Biểu đồ Gantt](#4-theo-dõi-tiến-độ-chi-tiết--biểu-đồ-gantt)
5. [Cập nhật công việc & Gửi duyệt hoàn thành](#5-cập-nhật-công-việc--gửi-duyệt-hoàn-thành)
6. [Quản lý Mốc kiểm soát & Nhật ký diễn biến](#6-quản-lý-mốc-kiểm-soát--nhật-ký-diễn-biến)

---

## 1. Tổng quan giao diện chính

Giao diện làm việc được thiết kế tối giản, trực quan và tập trung đúng vào chuyên môn quản lý tiến độ:

```
+------------------------------------------------------------------------------------+
| TTH GROUP             [Bộ chọn Chi nhánh / Tag Chi nhánh]        [Chuông] [User]   |
+-------------------+----------------------------------------------------------------+
|                   |  QUẢN LÝ TIẾN ĐỘ CÔNG VIỆC                                     |
|  MENU ĐIỀU HƯỚNG  |  Tổng quan tiến độ công việc                                   |
|                   |  +----------------------------------------------------------+  |
|  * Quản lý tiến   |  | Thống kê: Cơ sở đang chạy | Trễ hạn | Chưa lập KH...     |  |
|    độ công việc   |  +----------------------------------------------------------+  |
|    - Tổng quan    |                                                                |
|      công việc    |  [BẢNG TỔNG QUAN CÔNG VIỆC CÁC CƠ SỞ & TIẾN ĐỘ THỰC HIỆN]      |
|    (Khi vào xem): |  - Phòng khám Khe Tre (132 việc, hoàn thành 11%)               |
|    - Tiến độ Gantt|  - Phòng khám Quảng Ngãi                                       |
|    - Tổng quan    |  - Phòng khám Nhà văn hoá...                                   |
|    - Mốc K.Soát   |                                                                |
|    - Nhật ký      |                                                                |
+-------------------+----------------------------------------------------------------+
```

### Các khu vực chính:
- **Thanh bên trái (Sidebar):** 
  - Hiển thị phân hệ **Quản lý tiến độ công việc**.
  - Bấm vào mục **Tổng quan công việc** để theo dõi bức tranh toàn cảnh các cơ sở và kế hoạch đang chạy. Khi đang xem một cơ sở cụ thể, menu sẽ hiển thị chi tiết các mục con của cơ sở đó.
- **Thanh đỉnh (Header):**
  - Cung cấp bộ lọc chi nhánh (dành cho Ban giám sát / Cán bộ Tổng công ty HQ).
  - Chuông thông báo tiến độ, phê duyệt và thông tin tài khoản đang làm việc.
- **Khu vực nội dung (Main View):**
  - Nơi hiển thị Dashboard thống kê, danh sách dự án, Gantt chart, form cập nhật công việc.

---

## 2. Cơ chế phân quyền & Giám sát chi nhánh

Hệ thống vận hành theo nguyên tắc độc lập giữa các chi nhánh kết hợp sự giám sát từ Tổng công ty:

1. **Tổng công ty (Headquarters - HQ) & Quản trị hệ thống:**
   - Trên thanh Header có thanh chọn: **"Giám sát chi nhánh"**.
   - Có thể chọn xem toàn bộ các dự án trên toàn hệ thống hoặc chuyển đổi linh hoạt qua lại giữa từng chi nhánh cụ thể (ví dụ: Chi nhánh Quảng Bình, Chi nhánh Hà Tĩnh...).
2. **Chi nhánh thành viên (Branch):**
   - Tài khoản thuộc chi nhánh nào sẽ hiển thị nhãn chi nhánh đó (ví dụ: `📍 Chi nhánh Hà Tĩnh`).
   - Nhân viên và quản trị chi nhánh chỉ quản lý các dự án, công việc và phòng ban thuộc phạm vi chi nhánh mình phụ trách.

---

## 3. Quản lý danh mục dự án (Portfolio)

Màn hình Danh mục dự án hiển thị toàn bộ các dự án đang triển khai:

- **Thống kê đầu trang:** Cho biết tổng số dự án đang theo dõi, số dự án có việc trễ hạn, số dự án chưa chốt hạn.
- **Bảng danh sách dự án:**
  - Cột **Dự án**: Mã dự án và tên dự án (VD: `PK-KHETRE`, `PK-QNGAI`).
  - Cột **Bắt đầu & Hạn hoàn thành**: Hiển thị thời gian bắt đầu và deadline cam kết.
  - Cột **Còn lại**: Cảnh báo số ngày còn lại hoặc số ngày đã quá hạn (tô đỏ nếu trễ).
  - Cột **Tiến độ**: Thanh đo % hoàn thành thực tế và số công việc đã xong trên tổng số việc.
- **Thao tác nhanh:**
  - **Click vào dòng dự án bất kỳ:** Mở thẳng vào giao diện Biểu đồ Gantt & tiến độ chi tiết của dự án đó.
  - **Nút "+ Thêm dự án":** Dành cho Quản trị viên khởi tạo dự án mới. Hỗ trợ **nhân bản bộ 25 hạng mục chuẩn** từ dự án mẫu có sẵn.
  - **Nút "Sửa":** Thay đổi thông tin địa điểm, đơn vị đầu mối, ngày bắt đầu thuê mặt bằng.
  - **Nút "Lưu trữ":** Đóng dự án đã hoàn thành đưa vào kho lưu trữ để bảo toàn dữ liệu lịch sử.

---

## 4. Theo dõi tiến độ chi tiết & Biểu đồ Gantt

Khi mở một dự án (ví dụ: *Phòng khám Khe Tre*), chọn menu **Tiến độ & Gantt**:

```
+---------------------------------------------------------------------------------+
| Mã: PK-KHETRE | Đơn vị: Phòng PTPK | Tiến độ: 11% (15/132 việc)                 |
+---------------------------------------------------------------------------------+
| WBS | Tên công việc             | Chủ trì      | Hạn       | Trạng thái | GANTT |
+-----+---------------------------+--------------+-----------+------------+-------+
| I   | CHUẨN BỊ – THIẾT KẾ       |              |           |            |       |
| 1   | Rà soát hiện trạng        | Phòng T.Kế   | 02/08     | [Hoàn thành] [====] |
| 2   | Phương án thiết kế        | Phòng T.Kế   | 05/08     | [Hoàn thành] [====] |
| ... |                           |              |           |            |       |
| IV  | PHẦN PHÁ DỠ NHÀ 4 TẦNG    | P.Kỹ thuật   |           |            |       |
| 1   | Phá dỡ tường xây          | P.Kỹ thuật   | 08/09     | [Đang làm] [==> ] |
+---------------------------------------------------------------------------------+
```

### Tính năng trên màn hình Gantt:
- **Cây phân cấp công việc chuẩn WBS:** Phân chia thành các nhóm lớn (chữ số La Mã `I`, `II`, `III`...) và các công việc con (`1`, `2`, `3`...).
- **Biểu đồ Gantt theo thời gian thực:**
  - Hiển thị thanh tiến độ theo các mốc ngày/tuần.
  - Vạch đỏ đánh dấu ngày hiện tại (**Hôm nay**) giúp nhận biết ngay công việc nào đang chậm so với kế hoạch.
- **Bộ lọc công việc thông minh:**
  - Lọc theo **Đơn vị chủ trì** (Phòng Kỹ thuật, Phòng Thiết kế, Phòng TBTN, Marketing...).
  - Lọc theo **Trạng thái**: Chưa làm, Đang làm, Chờ duyệt, Hoàn thành, Trễ hạn.
  - Tìm kiếm nhanh theo tên công việc hoặc mã hiệu.

---

## 5. Cập nhật công việc & Gửi duyệt hoàn thành

Khi nhấp chuột vào một công việc trên danh sách Gantt, ngăn chi tiết bên phải (Drawer) sẽ mở ra:

1. **Cập nhật tiến độ %:**
   - Kéo chọn tỷ lệ % khối lượng công việc đã đạt được (ví dụ: 50%, 80%).
2. **Đính kèm tài liệu & Bằng chứng:**
   - Đính kèm file biên bản nghiệm thu, ảnh chụp hiện trường thi công, hóa đơn hoặc dán đường link tài liệu dùng chung.
   - *Lưu ý nghiệp vụ:* Để đảm bảo chất lượng, công việc khi báo hoàn thành **bắt buộc phải có tài liệu bằng chứng**.
3. **Gửi duyệt hoàn thành:**
   - Nhân viên/Đơn vị thực hiện chọn ngày hoàn thành và bấm **"Gửi duyệt hoàn thành"**.
   - Trạng thái công việc chuyển sang **"Chờ duyệt" (Pending)**. Quản trị dự án sẽ nhận được thông báo để kiểm tra bằng chứng trước khi bấm duyệt nghiệm thu chính thức.

---

## 6. Quản lý Mốc kiểm soát & Nhật ký diễn biến

### Mốc kiểm soát (Milestones)
- Quản lý các sự kiện bàn giao mấu chốt: *Hoàn thành thiết kế, Hoàn thành dự toán, Lựa chọn xong nhà thầu, Đóng điện trạm biến áp, Nghiệm thu PCCC, Cấp giấy phép hoạt động*.
- Giúp Ban Lãnh đạo nắm bắt tiến độ cấp cao mà không cần đọc hết 132 đầu việc chi tiết.

---

## 7. Phân cấp Quản lý Người dùng & Chi nhánh con

Hệ thống hỗ trợ phân cấp quản trị rõ ràng giữa Trụ sở chính (HQ) và Chi nhánh trực thuộc:

```
+-------------------------------------------------------------------------------+
| PHÂN CẤP QUẢN TRỊ NGƯỜI DÙNG                                                  |
+-------------------------------------------------------------------------------+
| 1. Quản trị hệ thống (HQ Super Admin):                                        |
|    - Toàn quyền tạo và quản lý tài khoản ở tất cả các Chi nhánh & Phòng ban.  |
|    - Gán quyền Quản trị Chi nhánh (Giám đốc Chi nhánh) & Quản trị Hệ thống.   |
|                                                                               |
| 2. Quản trị Chi nhánh (Branch Admin):                                         |
|    - Xuất hiện menu "Quản lý người dùng" riêng cho phạm vi Chi nhánh.         |
|    - Tạo, chỉnh sửa, đặt lại mật khẩu và khóa/mở khóa tài khoản nhân sự       |
|      trực thuộc chính Chi nhánh của mình.                                     |
|    - Danh sách phòng ban và nhân sự được cô lập tuyệt đối theo chi nhánh.    |
|                                                                               |
| 3. Quản trị phòng/ban (Department Admin):                                     |
|    - Trưởng phòng phụ trách phân công nhân sự và duyệt công việc nội bộ.      |
+-------------------------------------------------------------------------------+
```

### Các thao tác quản lý nhân sự:
1. **Tạo tài khoản mới:**
   - Nhập Họ và tên, tên tài khoản (3–32 ký tự chữ thường, số, dấu chấm/gạch).
   - Đặt mật khẩu tạm (tối thiểu 8 ký tự).
   - Chọn Phòng/ban phụ trách và vai trò tương ứng (Nhân viên, Trưởng phòng/ban).
2. **Khóa / Mở lại tài khoản:**
   - Khi nhân sự nghỉ việc hoặc tạm dừng công tác, bấm nút **Khóa** để bảo toàn lịch sử dữ liệu và vô hiệu hóa đăng nhập. Bấm **Mở lại** khi nhân sự tiếp tục làm việc.
3. **Đặt lại mật khẩu:**
   - Hỗ trợ cấp lại mật khẩu mới cho nhân sự khi quên mật khẩu qua kênh nội bộ an toàn.
   - *Lưu ý:* Tài khoản `admin` gốc luôn được bảo vệ hoàn toàn, không thể bị khóa hoặc sửa đổi từ giao diện.

### Quản lý Danh mục Chi nhánh (Dành cho Quản trị viên hệ thống):
1. **Chuyển sang Tab "Danh mục Chi nhánh":**
   - Trên thanh tab của trang Quản trị, chọn mục **🏢 Danh mục Chi nhánh**.
2. **Tạo Chi nhánh mới:**
   - **Mã chi nhánh:** Nhập mã viết tắt phân biệt (VD: `CN-HT`, `CN-QB`, `PK-KT`...).
   - **Tên chi nhánh:** Nhập tên đầy đủ (VD: *Bệnh viện Đa khoa TTH Hà Tĩnh*).
   - **Địa chỉ:** Nhập địa chỉ hoặc địa bàn triển khai.
   - **Đánh dấu Trụ sở chính (HQ):** Tích chọn nếu đây là cơ quan đầu mối điều phối cấp Tập đoàn.
3. **Chỉnh sửa & Khóa chi nhánh:**
   - Bấm **Sửa** để thay đổi tên hoặc địa chỉ.
   - Bấm **Tạm khóa** đối với chi nhánh tạm dừng hoạt động. Các chi nhánh đang hoạt động sẽ xuất hiện ngay lập tức trong bộ lọc Header, form tạo Kế hoạch cơ sở và form tạo Tài khoản nhân sự.

---

*Tài liệu này được cập nhật định kỳ tương ứng với từng phiên bản nâng cấp chức năng của phần mềm.*



