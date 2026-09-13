# Project Brief — Tiến độ dự án PTPK

## 1. Business Problem

Phòng Phát triển phòng khám (PTPK) đang theo dõi tiến độ dự án bằng Excel. Dữ liệu khó dùng chung, không xác định chắc chắn ai cập nhật, không có quy trình duyệt hoàn thành và khó tổng hợp trạng thái giữa nhiều dự án.

## 2. Mục tiêu

- Số hóa dữ liệu tiến độ Excel thành dữ liệu dùng chung trên web.
- Theo dõi hạng mục, công việc, người tham gia, mốc kiểm soát và diễn biến.
- Quản trị phòng/ban được theo dõi toàn bộ dự án; nhân viên chỉ thấy dự án có công việc liên quan đến phòng mình; người tham gia cập nhật công việc được giao.
- Công việc chỉ hoàn thành sau khi quản trị viên duyệt.
- Giữ được lịch sử thay đổi và tài liệu bằng chứng.

## 3. Stakeholders và người dùng

| Nhóm/Vai trò | Nhu cầu | Quyền dự kiến |
|---|---|---|
| Quản trị hệ thống | Quản lý và cứu hộ toàn bộ hệ thống | Quản lý tài khoản và mọi dự án; có toàn bộ quyền Quản trị dự án |
| Quản trị dự án | Điều hành các dự án được giao | Toàn quyền nghiệp vụ; tự xác nhận hoàn thành phần việc của mình và được duyệt/từ chối mọi yêu cầu khác trong dự án |
| Quản trị phòng/ban | Theo dõi toàn bộ tiến độ và kiểm soát phần việc của đơn vị | Đồng thời là nhân viên; xem tiến độ mọi dự án, xem chi tiết nghiệp vụ khi đơn vị chủ trì/phối hợp; cập nhật tiến độ theo phân công nhưng không thay đổi cấu trúc kế hoạch đã chốt; tự xác nhận phần việc được giao khi phòng mình chủ trì |
| Nhân viên | Theo dõi phần việc liên quan đến đơn vị và cập nhật việc được giao | Xem việc đơn vị chủ trì/phối hợp; cập nhật, thêm bằng chứng và gửi duyệt khi là người tham gia |

## 4. Current State

- Quy trình hiện tại: lập và cập nhật tiến độ theo từng dự án trong Excel.
- Dữ liệu mẫu đã khảo sát: `TIEN DO KHE TRE 25.8.xlsx`; sheet đầu có 25 hạng mục và 132 công việc.
- Prototype gốc là một file `index.html`, dùng dữ liệu hard-code và `localStorage` riêng trên từng trình duyệt.
- MVP mới đã tách giao diện theo module React và đưa dữ liệu mẫu lên Supabase; file `main/index.html` mới nhất tiếp tục là chuẩn đối chiếu giao diện và luồng nghiệp vụ.
- Điểm còn phải hoàn thiện trước vận hành chính thức: kiểm thử nghiệm thu đủ hai vai trò và chốt phương án backup định kỳ.

## 5. Desired State

Ứng dụng web có đăng nhập, dữ liệu tập trung, phân quyền theo cả cấp quyền và phạm vi phòng ban/dự án, hỗ trợ import kế hoạch từ sheet đầu của Excel và quản lý tiến độ hằng ngày trên hệ thống. Kiến trúc phân quyền về sau phải cho phép Quản trị hệ thống tạo các vai trò nghiệp vụ như TGĐ, Thư ký, Trưởng phòng và gắn bộ quyền tương ứng; Quản trị dự án tiếp tục là vai trò theo từng dự án, không phải vai trò cố định của tài khoản.

## 6. Phạm vi MVP

### Trong phạm vi

- Đăng nhập bằng tên tài khoản và mật khẩu do quản trị viên tạo; không có màn hình hoặc API tự đăng ký công khai.
- Danh mục 21 phòng ban/đơn vị.
- Danh mục phòng/ban là dữ liệu cấu hình cố định trong giai đoạn này, chưa làm màn hình quản lý riêng.
- Mỗi tài khoản được gắn một phòng/ban; một tài khoản có thể đồng thời là Quản trị phòng và Quản trị dự án tại phạm vi được giao.
- Danh mục dự án, hạng mục và công việc.
- Import có preview từ sheet đầu của Excel và có file mẫu tải trực tiếp tại màn hình nạp dữ liệu.
- Gán nhiều người tham gia một công việc, không chia người chính/phối hợp.
- Gantt được tính từ ngày bắt đầu/kết thúc.
- Nhật ký diễn biến và tài liệu bằng chứng.
- Gửi duyệt, duyệt và từ chối hoàn thành.
- Mốc kiểm soát được quản lý riêng trên web, không import từ Excel.
- Dashboard, lọc và export dữ liệu Excel cơ bản.

### Ngoài phạm vi

- Chat/Chat AI.
- Thông báo đa kênh.
- Ứng dụng mobile native.
- Quy trình duyệt nhiều cấp.
- Tích hợp với hệ thống khác của TTH.

## 7. Yêu cầu chức năng

1. Đăng nhập/đăng xuất.
2. Quản trị hệ thống quản lý tài khoản: tạo người dùng với họ tên, phòng/ban và cấp quyền, đặt lại mật khẩu và bật/tắt hoạt động.
3. Tạo, sửa, xóa mềm và khôi phục dự án; chỉ quản trị viên xem được danh sách đã xóa.
4. Tải file Excel mẫu; import sheet đầu của file kế hoạch đã được TGĐ phê duyệt, xem trước và xác nhận.
5. Quản trị hệ thống và Quản trị dự án quản lý cấu trúc hạng mục/công việc. Quản trị phòng/ban được phân công người tham gia theo phạm vi đơn vị chủ trì hoặc phối hợp nhưng không được thay đổi cấu trúc kế hoạch đã chốt.
6. Xem Gantt, tổng quan và công việc cần xử lý.
7. Cập nhật diễn biến, nguyên nhân chậm và bằng chứng. Trang Nhật ký và panel công việc dùng cùng quyền ghi diễn biến: Quản trị hệ thống, Quản trị dự án trong phạm vi được giao hoặc người tham gia; diễn biến vẫn được bổ sung khi công việc chờ duyệt/hoàn thành.
8. Nhân viên và Quản trị phòng/ban thuộc đơn vị phối hợp gửi hoàn thành để Quản trị phòng của đơn vị chủ trì hoặc Quản trị dự án duyệt/từ chối; Quản trị phòng được giao việc do chính phòng mình chủ trì và Quản trị dự án vẫn phải tải bằng chứng, bấm nộp nhưng công việc chuyển thẳng sang Hoàn thành.
9. Quản lý mốc kiểm soát theo dự án.
10. Lưu audit log và export dữ liệu.
11. Mỗi người dùng đã đăng nhập được tự đổi mật khẩu sau khi nhập đúng mật khẩu hiện tại.
12. Các màn hình dữ liệu tự làm mới định kỳ khi tab đang hiển thị và làm mới ngay khi người dùng quay lại tab; tạm dừng khi đang có bản nháp hoặc thao tác ghi dữ liệu.
13. Từ Tổng quan và Nhật ký, bấm một đầu việc phải mở đúng panel công việc trên Gantt; URL chứa định danh công việc để có thể tải lại hoặc chia sẻ.
14. Danh sách người dùng có tìm kiếm và phân trang 10 tài khoản mỗi trang.
15. Quản trị viên có thể duyệt hoặc từ chối ngay trong panel của công việc đang chờ duyệt; màn Chờ duyệt tổng hợp vẫn được giữ nguyên.
16. Tổng quan dự án có biểu đồ cơ cấu trạng thái tính theo công việc cuối nhánh; Gantt phân biệt trực quan trạng thái tổng hợp của mục cha với trạng thái trực tiếp của công việc cuối nhánh.
17. Quản trị hệ thống chỉ định Quản trị dự án theo từng dự án và Quản trị phòng/ban theo từng đơn vị; quyền hiệu lực của một tài khoản là tổng hợp các phạm vi được giao.
18. Người dùng thường chỉ thấy các nhánh công việc mà phòng/ban của mình là đơn vị chủ trì hoặc phối hợp; hệ thống vẫn hiển thị các mục cha cần thiết để giữ ngữ cảnh cây công việc.
19. Gantt có bộ lọc phạm vi **Việc của tôi** và **Tất cả công việc liên quan**; số liệu trạng thái thay đổi theo phạm vi đang chọn.
20. Header có chuông thông báo riêng theo từng tài khoản; hiển thị diễn biến, lượt gửi hoàn thành và kết quả duyệt chưa đọc trong phạm vi người dùng được phép xem. Bấm thông báo mở đúng dự án/công việc và đánh dấu đã đọc; người dùng có thể đánh dấu tất cả đã đọc.
21. Nhật ký dự án cho phép lọc **Tất cả**, **Diễn biến**, **Gửi & xét duyệt**; Quản trị dự án và Quản trị hệ thống có thêm bộ lọc **Đã xóa** để truy vết việc xóa hạng mục/công việc trong phạm vi quản lý. Mỗi bộ lọc phân trang 10 hoạt động một trang và trở về trang đầu khi đổi loại nhật ký.

### Quy tắc nhập liệu hạng mục/công việc

- Bấm thêm hạng mục hoặc công việc chỉ mở panel và tạo bản nháp trên trình duyệt, chưa ghi vào database.
- Chỉ thao tác **Lưu hạng mục/Lưu công việc** mới tạo dữ liệu thật.
- Đóng bằng nút `X`, lớp nền hoặc **Hủy bỏ** phải bỏ bản nháp; nếu đã nhập liệu thì cần cảnh báo trước khi bỏ.

## 8. Business Rules và ngoại lệ

- Quản trị hệ thống xem và quản lý toàn bộ hệ thống; Quản trị dự án xem và quản lý toàn bộ dữ liệu trong dự án được giao.
- Quản trị phòng/ban thấy toàn bộ dự án và toàn bộ các dòng tiến độ/Gantt. Với nhánh không có phòng mình chủ trì hoặc phối hợp, họ chỉ xem thông tin tiến độ cơ bản và không được đọc bằng chứng, diễn biến hoặc dữ liệu xét duyệt.
- Nhân viên thấy công việc khi phòng của mình là đơn vị chủ trì hoặc đơn vị phối hợp. Các mục cha của nhánh liên quan vẫn được hiển thị, nhưng các nhánh không liên quan bị ẩn.
- Quyền nhìn thấy do phòng/ban liên quan không tự động cấp quyền cập nhật; Nhân viên chỉ cập nhật, tải bằng chứng và gửi duyệt khi được chọn trong danh sách người tham gia.
- File Excel được nạp vào hệ thống là kế hoạch đã được TGĐ phê duyệt. Sau khi nạp, chỉ Quản trị hệ thống và Quản trị dự án của dự án đó được thêm, sửa hoặc xóa hạng mục/công việc; Quản trị phòng/ban không được thay đổi cấu trúc kế hoạch, kể cả tại nhánh do phòng mình chủ trì.
- Chỉ quản trị viên được tạo tài khoản; Supabase Auth tắt self-signup và frontend không giữ `service_role` key.
- Tài khoản `admin` gốc được bảo vệ tuyệt đối: không ai được chỉnh sửa hồ sơ/vai trò, đặt lại hoặc tự đổi mật khẩu, khóa hay mở trạng thái tài khoản này. Quản trị viên không thể tự khóa hoặc tự hạ quyền tài khoản đang đăng nhập.
- Khóa tài khoản không xóa hồ sơ hoặc lịch sử thao tác; khi được mở lại, tài khoản tiếp tục sử dụng dữ liệu cũ.
- Nhân viên chỉ cập nhật công việc mình tham gia.
- Một công việc có thể có nhiều người tham gia; tất cả người tham gia có quyền cập nhật và gửi duyệt.
- Người tham gia được chọn bằng dropdown nhiều lựa chọn có tìm kiếm theo họ tên hoặc tài khoản và hiển thị thành thẻ; danh sách chỉ gồm tài khoản đang hoạt động thuộc đơn vị chủ trì hoặc một trong các đơn vị phối hợp của công việc, không bày toàn bộ người dùng bằng checkbox trên form.
- Quản trị phòng/ban của đơn vị chủ trì được thêm hoặc bỏ người tham gia thuộc tất cả đơn vị chủ trì/phối hợp của công việc. Quản trị phòng/ban của một đơn vị phối hợp chỉ được thêm hoặc bỏ nhân sự thuộc chính phòng/ban mình; phân công của các đơn vị khác phải được giữ nguyên. Phân công người tham gia là thao tác độc lập, không cấp quyền sửa tên, ngày, đơn vị hoặc cấu trúc kế hoạch.
- Khi đã gửi duyệt, tệp bằng chứng bị khóa cho đến khi quản trị viên từ chối; thông tin, phân công, diễn biến và cấu trúc công việc vẫn được cập nhật.
- Khi quản trị viên mở một công việc đang chờ duyệt, panel ưu tiên mở phần Xét duyệt với thông tin người gửi, ghi chú, bằng chứng và nút duyệt/từ chối.
- Chỉ quản trị viên được thay đổi công việc thành hoàn thành.
- Từ chối duyệt đưa công việc về trạng thái đang thực hiện và bắt buộc lưu lý do.
- Mỗi vòng gửi/duyệt phải được lưu riêng để truy vết.
- Chỉ import sheet đầu của Excel; các sheet khác không thuộc luồng import.
- Chuỗi phòng ban từ Excel không tự động trở thành người tham gia.
- Mỗi tài khoản được gắn một phòng/ban chính. Phòng/ban của tài khoản dùng để xác định phạm vi nhìn thấy và quyền theo đơn vị; danh sách người tham gia vẫn được quản lý độc lập để xác định người được cập nhật công việc.
- Đơn vị chủ trì là một trường chọn riêng; đơn vị phối hợp dùng dropdown chọn nhiều có tìm kiếm và hiển thị thành thẻ, không nhập chuỗi phân cách bằng dấu `/` và không bày toàn bộ checkbox trên form.
- Quản trị dự án không phải chờ người khác duyệt trong dự án mình quản trị, nhưng vẫn phải tải đúng một tệp bằng chứng và bấm nộp. Khi nộp đủ hồ sơ, công việc chuyển thẳng sang Hoàn thành và hệ thống ghi nhận phạm vi quyền đã sử dụng.
- Quản trị phòng/ban được giao làm công việc do chính phòng mình chủ trì cũng hoàn thành trực tiếp sau khi tải đúng một tệp bằng chứng và bấm nộp. Nếu phòng của Quản trị phòng/ban chỉ là đơn vị phối hợp, công việc vẫn phải gửi Quản trị phòng của đơn vị chủ trì, Quản trị dự án hoặc Quản trị hệ thống duyệt.
- Người được xử lý yêu cầu gồm Quản trị hệ thống, Quản trị phòng/ban của đơn vị chủ trì công việc và Quản trị dự án. Người gửi bị loại khỏi danh sách người duyệt của chính yêu cầu đó; trường hợp đủ điều kiện hoàn thành trực tiếp không tạo yêu cầu chờ duyệt.
- Quy trình duyệt chỉ có một cấp. Một người đủ quyền duyệt hoặc từ chối là yêu cầu kết thúc ngay, không chuyển tiếp sang cấp thứ hai; hệ thống lưu người xử lý, thời điểm và phạm vi quyền đã sử dụng.
- Khi công việc có diễn biến hoặc vòng duyệt mới mà người dùng chưa xem, Gantt hiển thị nhãn Mới tại dòng công việc, dấu sáng trên thanh tiến độ, dải thông báo và số lượng tại menu Nhật ký diễn biến. Trạng thái đã xem được lưu riêng theo từng tài khoản và thông báo tự cập nhật khi người dùng đang mở hệ thống.
- File Excel mẫu có sẵn hạng mục, công việc, cột đơn vị và ngày minh họa; có sheet hướng dẫn nhưng hệ thống vẫn chỉ nhập dữ liệu từ sheet đầu tiên.
- Khi tạo công việc con hoặc nạp một dòng công việc không ghi đơn vị chủ trì, hệ thống tự lấy đơn vị chủ trì của hạng mục cha gần nhất. Đơn vị phối hợp không tự kế thừa; Quản trị hệ thống hoặc Quản trị dự án vẫn có thể đổi đơn vị chủ trì trước khi lưu.
- Thao tác tải lên hoặc xóa bằng chứng phải giữ người dùng ở tab Bằng chứng; tải lại dữ liệu không được tự đưa panel về tab Thông tin.
- Công việc ở trạng thái Chờ duyệt hoặc Hoàn thành vẫn được sửa thông tin, phân công, ghi diễn biến và thêm công việc con. Trạng thái hiển thị của mục cha tự tổng hợp lại từ các công việc cuối nhánh.
- Màu trạng thái giữ nhất quán giữa mọi cấp. Trên Gantt, trạng thái tổng hợp của hạng mục/công việc cha dùng nhãn viền vuông; trạng thái trực tiếp của công việc cuối nhánh dùng nhãn nền màu bo tròn và có chú thích ngay trên bảng.
- Biểu đồ Tổng quan chỉ đếm công việc cuối nhánh, chia thành năm nhóm loại trừ lẫn nhau: Hoàn thành, Đang thực hiện, Chờ duyệt, Chưa thực hiện và Quá hạn; công việc quá hạn không được đếm lặp vào trạng thái gốc.
- Bằng chứng bị khóa khi công việc Chờ duyệt hoặc Hoàn thành: chỉ được xem, không được tải thay thế hoặc xóa. Không được xóa cả công việc/hạng mục nếu thao tác đó làm mất bằng chứng đã khóa. Khi yêu cầu bị từ chối và công việc trở lại Đang thực hiện, bằng chứng được phép cập nhật để gửi lại.
- Khi hạng mục hoặc công việc bị xóa, audit log vẫn giữ mã WBS, tên đầu mục, loại đầu mục, dự án, người xóa và thời gian xóa. Nhân viên và Quản trị phòng/ban không được đọc log xóa; Quản trị dự án chỉ đọc trong dự án được giao, Quản trị hệ thống đọc toàn bộ.
- Nhật ký diễn biến cho phép quản trị viên ghi vào mọi công việc; nhân viên chỉ ghi vào công việc chi tiết mình tham gia, không phụ thuộc trạng thái công việc.
- Cột Chủ trì trên bảng tiến độ hiển thị tên đầy đủ của đơn vị. Mọi thanh trên Gantt phải hiển thị tên hạng mục/công việc, kể cả thanh ngắn.
- Cột Mã trên Gantt giữ số La Mã cho hạng mục cấp cao nhất và hiển thị số thứ tự phân cấp cho các cấp dưới mà không lặp lại mã hạng mục, ví dụ `III` → `1` → `1.1` → `1.1.1`.
- Tại màn Quản lý người dùng, trường gắn Phòng/ban và cột Phòng/ban chỉ hiển thị tên đầy đủ; mã phòng/ban vẫn được giữ trong dữ liệu và ở các vị trí cần nhận diện ngắn gọn như thẻ tài khoản.
- Thẻ màu xanh tại khu vực tài khoản hiển thị mã phòng/ban của người dùng; riêng Quản trị hệ thống hiển thị `ADMIN` thay cho chữ viết tắt họ tên.
- Khi vào Gantt, Nhân viên mặc định xem **Việc của tôi**; Quản trị phòng/ban mặc định xem **Công việc phòng tôi**; Quản trị dự án và Quản trị hệ thống mặc định xem toàn bộ tiến độ. Quản trị phòng/ban có đủ ba phạm vi **Việc của tôi**, **Công việc phòng tôi** và **Tất cả tiến độ**. Các chế độ lọc vẫn giữ mục cha cần thiết và tính trạng thái mục cha từ các công việc đang được hiển thị.
- Mỗi màn hình có URL riêng để mở trực tiếp và chia sẻ; URL dự án chứa mã dự án và tên màn hình, ví dụ `#/projects/PK-KHETRE/gantt`.
- URL công việc có dạng `#/projects/{mã-dự-án}/gantt/work/{id-công-việc}`. Hệ thống tự mở các cấp cha đang thu gọn và mở panel của đúng công việc; nếu công việc không còn tồn tại phải báo rõ và trở về URL Gantt.
- Dữ liệu đang xem được tự làm mới sau tối đa khoảng 15 giây (30 giây với danh mục lớn), đồng thời làm mới khi cửa sổ/tab được mở lại. Không tự làm mới lúc người dùng đang sửa bản nháp để tránh mất dữ liệu nhập.
- Trạng thái đã đọc của chuông được lưu theo cặp tài khoản–công việc. Một tài khoản đọc thông báo không làm mất thông báo chưa đọc của tài khoản khác; chuông không báo lại hành động do chính tài khoản đó thực hiện và dữ liệu hiển thị vẫn tuân theo quyền xem chi tiết công việc tại database.
- Di chuột hoặc dùng bàn phím focus vào hình thoi mốc kiểm soát trên Gantt phải hiển thị tên mốc, ngày phải đạt, đơn vị chủ trì, điều kiện kiểm soát và trạng thái.
- Xóa dự án là xóa mềm: người dùng thường không còn xem được dự án và dữ liệu con; quản trị viên có thể xem danh sách đã xóa và khôi phục. MVP không xóa vĩnh viễn dự án từ giao diện.

## 9. Dữ liệu và tích hợp

- Dữ liệu đầu vào: Excel tiến độ theo mẫu Khe Tre và dữ liệu cập nhật trên web.
- Dữ liệu đầu ra: danh sách dự án, Gantt, công việc trễ/chờ duyệt, mốc kiểm soát và Excel export.
- Tích hợp MVP: Supabase Auth, PostgreSQL và Storage.
- Lưu trữ: dữ liệu nghiệp vụ trong PostgreSQL, tệp trong private Storage, lịch sử gửi duyệt và audit log riêng.

## 10. Yêu cầu phi chức năng

- Bảo mật: không tự đăng ký, RLS ở database, tệp bằng chứng không public, không lưu secret trong Git.
- Hiệu năng: đáp ứng dữ liệu nhiều dự án ở quy mô nội bộ PTPK; bảng dài cần lọc và phân trang/ảo hóa khi cần.
- Thiết bị/trình duyệt: ưu tiên máy tính trên Chrome/Edge; responsive để xem trên điện thoại.
- Giao diện: luôn dùng chế độ sáng, không thay đổi theo theme của trình duyệt hoặc hệ điều hành.
- Phản hồi thao tác: mọi hành động do người dùng chủ động thực hiện như tạo, lưu, xóa, nạp/xuất file, gửi duyệt, xét duyệt và quản lý tài khoản phải hiện thông báo thành công hoặc thất bại thống nhất; lỗi tải nền vẫn hiển thị tại màn hình để tránh thông báo lặp gây phiền.
- Triển khai: Cloudflare Pages Free và Supabase Free trong giai đoạn MVP.
- Sao lưu: cần export định kỳ vì Supabase Free không cung cấp automatic backup.

## 11. Tiêu chí thành công

- Người dùng đăng nhập và cùng xem một nguồn dữ liệu thống nhất.
- Import đúng đủ hạng mục/công việc từ sheet đầu, có báo lỗi trước khi ghi.
- Nhân viên không nhìn thấy nhánh công việc không liên quan đến phòng/ban và không sửa được công việc ngoài phạm vi tham gia.
- Nhân viên và Quản trị phòng/ban thuộc đơn vị phối hợp không thể hoàn thành công việc nếu chưa được một người đủ quyền duyệt; Quản trị phòng của đơn vị chủ trì và Quản trị dự án được tự xác nhận sau khi nộp đủ bằng chứng trong đúng phạm vi.
- Lịch sử cập nhật, gửi duyệt và bằng chứng truy vết được theo người dùng/thời gian.

## 12. Open Questions

1. Ai chịu trách nhiệm vận hành tài khoản quản trị viên đầu tiên và cấp/khóa tài khoản về sau?
2. `PTNL1`, `PTNL2` và `Z1` có tên đầy đủ cần hiển thị hay giữ nguyên mã?
3. Chính sách dung lượng, định dạng và thời gian lưu tài liệu bằng chứng là gì?
4. Tần suất backup/export dữ liệu trong giai đoạn MVP?
5. Danh mục vai trò tùy chỉnh và quyền mặc định cho TGĐ, Thư ký, Trưởng phòng sẽ được đưa vào giai đoạn triển khai phân quyền động nào?
