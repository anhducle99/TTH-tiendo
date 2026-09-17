# Tiến độ dự án PTPK

Hệ thống quản lý và theo dõi tiến độ dự án phòng khám đa chi nhánh, đa phòng ban.

## Trạng thái

- Giai đoạn: MVP đang chạy với dữ liệu Supabase
- Frontend: React 19, TypeScript, Vite
- Backend: Supabase Auth, PostgreSQL, Storage và Edge Functions
- Giao diện và nghiệp vụ nguồn: [`main/index.html`](https://github.com/quang11111222/tien-do-phong-kham/blob/main/index.html); bản local trong `prototype/` chỉ dùng để đối chiếu lịch sử
- Dữ liệu mẫu đã đưa lên database: 5 dự án; Khe Tre có 25 hạng mục, 132 công việc và 14 mốc kiểm soát

## Toolchain hiện có

- Git `2.55.0.windows.3`
- Node.js `v24.19.0`
- npm `11.17.0`
- Python: Chưa có trong `PATH`
- .NET SDK: Chưa có trong `PATH`

Node.js/npm đã sẵn sàng nếu chọn web stack. Chỉ cài Python hoặc .NET khi kiến trúc thực sự cần, tránh làm nặng máy và repository từ đầu.

## Chạy ứng dụng

```powershell
npm install
Copy-Item .env.example .env.local
npm run dev
```

Điền `VITE_SUPABASE_URL` và `VITE_SUPABASE_ANON_KEY` trong `.env.local`. Không đưa service-role key vào frontend.

## Kiểm tra

```powershell
npm run lint
npm run type-check
npm run test
npm run build
```

## Triển khai

Mỗi lần thay đổi được đưa vào nhánh `main`, workflow
`.github/workflows/deploy-pages.yml` sẽ kiểm tra, build và triển khai thư mục
`dist` lên GitHub Pages. Repository cần có hai Actions variables (đây là cấu
hình publishable được đóng gói vào frontend, không phải `service_role` secret):

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

Trong **Settings → Pages**, nguồn triển khai phải được đặt là **GitHub Actions**.

## Tài liệu

- [Project Brief](docs/PROJECT-BRIEF.md)
- [Decision Log](docs/DECISIONS.md)
- [Kiến trúc V2](docs/ARCHITECTURE.md)
- Database migrations: `supabase/migrations/`
- Edge Function tạo tài khoản: `supabase/functions/admin-create-user/index.ts`

## Nguyên tắc repository

- Không commit mật khẩu, token hoặc file `.env`.
- Thay đổi nghiệp vụ phải được ghi lại trong `docs/PROJECT-BRIEF.md`.
- Quyết định kiến trúc quan trọng được ghi trong `docs/DECISIONS.md`.
- Mỗi thay đổi code phải kèm bước kiểm tra phù hợp.
