export function SetupPage() {
  return (
    <main className="setup-page">
      <section className="setup-card">
        <span className="brand-mark">TTH</span>
        <p className="eyebrow">TIẾN ĐỘ DỰ ÁN PTPK</p>
        <h1>Ứng dụng đã sẵn sàng kết nối dữ liệu</h1>
        <p>
          Tạo file <code>.env.local</code> từ <code>.env.example</code>, sau đó điền URL và publishable
          key của Supabase.
        </p>
        <div className="alert info">
          Ứng dụng đang đợi cấu hình kết nối cơ sở dữ liệu Supabase để chạy với dữ liệu thực tế.
        </div>
        <div style={{ marginTop: '1.5rem', display: 'flex', gap: '0.75rem', flexWrap: 'wrap' }}>
          <a
            href="/prototype.html"
            className="primary-button"
            style={{ textDecoration: 'none', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}
          >
            Xem trước giao diện & dữ liệu mẫu (Prototype)
          </a>
        </div>
      </section>
    </main>
  )
}
