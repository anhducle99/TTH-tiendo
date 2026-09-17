import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react'
import { useConfirm } from '../../components/confirmContext'
import { useAuth } from '../auth/authContext'
import type { AppRole, Branch, Department, UserProfile } from '../../types/domain'
import { normalizeUsername, USERNAME_PATTERN } from '../../lib/username'
import { createUser, listBranches, listDepartments, listUsers, resetUserPassword, setUserActive, updateUserProfile } from './userService'
import { useAutoRefresh } from '../../lib/useAutoRefresh'
import { useToast } from '../../components/toastContext'

const emptyForm = { fullName: '', username: '', password: '', role: 'employee' as AppRole, branchId: '', isBranchAdmin: false, departmentId: '', isDepartmentAdmin: false }
const PAGE_SIZE = 10
type UserDialog = { kind: 'edit'; user: UserProfile } | { kind: 'password'; user: UserProfile } | null

export function UsersPage() {
  const { profile } = useAuth()
  const confirm = useConfirm()
  const notify = useToast()
  const [users, setUsers] = useState<UserProfile[]>([])
  const [branches, setBranches] = useState<Branch[]>([])
  const [departments, setDepartments] = useState<Department[]>([])
  const [form, setForm] = useState(emptyForm)
  const [dialog, setDialog] = useState<UserDialog>(null)
  const [loading, setLoading] = useState(true)
  const [submitting, setSubmitting] = useState(false)
  const [busyUserId, setBusyUserId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [query, setQuery] = useState('')
  const [page, setPage] = useState(1)

  const isSuperAdmin = profile?.role === 'manager'

  const loadData = useCallback(async (showLoading = true) => {
    if (showLoading) setLoading(true)
    try {
      const [nextUsers, nextBranches, nextDepartments] = await Promise.all([listUsers(), listBranches(), listDepartments()])
      setUsers(nextUsers)
      setBranches(nextBranches)
      setDepartments(nextDepartments)
    }
    catch { setError('Không tải được danh sách người dùng.') }
    finally { if (showLoading) setLoading(false) }
  }, [])

  useEffect(() => {
    const timer = window.setTimeout(() => void loadData(), 0)
    return () => window.clearTimeout(timer)
  }, [loadData])
  useAutoRefresh(() => loadData(false), { enabled: !dialog && !submitting && !busyUserId, intervalMs: 30_000 })

  const availableDepartments = useMemo(() => {
    if (!form.branchId) return departments
    return departments.filter((d) => d.branch_id === form.branchId)
  }, [departments, form.branchId])

  const filteredUsers = useMemo(() => {
    const keyword = query.trim().toLocaleLowerCase('vi')
    if (!keyword) return users
    return users.filter((user) => `${user.full_name} ${user.username} ${user.branch?.name ?? ''} ${user.department?.name ?? ''}`.toLocaleLowerCase('vi').includes(keyword))
  }, [query, users])
  const pageCount = Math.max(1, Math.ceil(filteredUsers.length / PAGE_SIZE))
  const currentPage = Math.min(page, pageCount)
  const visibleUsers = filteredUsers.slice((currentPage - 1) * PAGE_SIZE, currentPage * PAGE_SIZE)

  const handleSubmit = async (event: FormEvent) => {
    event.preventDefault()
    setError(null)
    setSuccess(null)
    const fullName = form.fullName.trim()
    if (fullName.length < 2) { const message = 'Họ và tên phải có ít nhất 2 ký tự.'; setError(message); notify(message, 'error'); return }
    if (form.password.length < 8) { const message = 'Mật khẩu tạm phải có ít nhất 8 ký tự.'; setError(message); notify(message, 'error'); return }
    const username = normalizeUsername(form.username)
    if (!USERNAME_PATTERN.test(username)) { const message = 'Tài khoản gồm 3–32 ký tự: chữ thường, số, dấu chấm, gạch ngang hoặc gạch dưới.'; setError(message); notify(message, 'error'); return }
    if (form.role === 'employee' && !form.departmentId) { const message = 'Nhân viên phải được gắn với một phòng/ban.'; setError(message); notify(message, 'error'); return }

    setSubmitting(true)
    try {
      await createUser({
        ...form,
        branchId: form.branchId || (isSuperAdmin ? null : profile?.branch_id ?? null),
        departmentId: form.departmentId || null,
        fullName,
        username
      })
      setSuccess(`Đã tạo tài khoản ${username} cho ${fullName}.`)
      notify(`Đã tạo tài khoản ${username} cho ${fullName}.`)
      setForm(emptyForm)
      await loadData()
    } catch {
      const message = 'Không tạo được tài khoản. Kiểm tra tên trùng, dữ liệu nhập hoặc quyền quản trị viên.'
      setError(message)
      notify(message, 'error')
    } finally { setSubmitting(false) }
  }

  const toggleActive = async (user: UserProfile) => {
    const nextActive = !user.active
    const accepted = await confirm(nextActive ? {
      title: 'Mở lại tài khoản?', message: `${user.full_name} sẽ có thể đăng nhập và sử dụng hệ thống trở lại.`, confirmLabel: 'Mở tài khoản',
    } : {
      title: 'Khóa tài khoản?', message: `${user.full_name} sẽ không thể đăng nhập. Dữ liệu và lịch sử thao tác của tài khoản vẫn được giữ lại.`, confirmLabel: 'Khóa tài khoản', tone: 'danger',
    })
    if (!accepted) return
    setBusyUserId(user.id)
    setError(null)
    setSuccess(null)
    try {
      await setUserActive(user.id, nextActive)
      setSuccess(`Đã ${nextActive ? 'mở lại' : 'khóa'} tài khoản ${user.username}.`)
      notify(`Đã ${nextActive ? 'mở lại' : 'khóa'} tài khoản ${user.username}.`)
      await loadData()
    } catch { const message = `Không thể ${nextActive ? 'mở lại' : 'khóa'} tài khoản ${user.username}.`; setError(message); notify(message, 'error') }
    finally { setBusyUserId(null) }
  }

  return <section>
    <div className="page-heading"><div><p className="eyebrow">QUẢN TRỊ HỆ THỐNG</p><h1>Quản lý người dùng</h1><p className="muted">Quản lý tài khoản theo Chi nhánh và Phòng ban trực thuộc.</p></div></div>
    <div className="admin-grid">
      <form className="content-card user-form" onSubmit={handleSubmit}>
        <div><h2>Tạo tài khoản</h2><p className="muted">Cấp tài khoản và phân quyền Chi nhánh / Phòng ban.</p></div>
        <label>Họ và tên<input required maxLength={100} autoComplete="name" value={form.fullName} onChange={(event) => setForm({ ...form, fullName: event.target.value })} placeholder="Nguyễn Văn An" /></label>
        <label>Tài khoản<input required autoComplete="off" pattern="[a-z0-9._-]{3,32}" value={form.username} onChange={(event) => setForm({ ...form, username: event.target.value.toLowerCase() })} placeholder="nguyenvanan" /></label>
        <label>Mật khẩu tạm<input required minLength={8} type="password" autoComplete="new-password" value={form.password} onChange={(event) => setForm({ ...form, password: event.target.value })} /></label>
        
        {isSuperAdmin && (
          <label>Chi nhánh<select value={form.branchId} onChange={(event) => setForm({ ...form, branchId: event.target.value, departmentId: '' })}><option value="">Chưa gắn chi nhánh (Hội sở/Toàn hệ thống)</option>{branches.map((b) => <option key={b.id} value={b.id}>{b.name} ({b.code})</option>)}</select></label>
        )}

        <label>Phòng/ban<select required={form.role === 'employee'} value={form.departmentId} onChange={(event) => setForm({ ...form, departmentId: event.target.value })}><option value="">Chưa gắn phòng/ban</option>{availableDepartments.map((department) => <option key={department.id} value={department.id}>{department.name}</option>)}</select></label>
        <label>Cấp quyền<select value={form.role} onChange={(event) => setForm({ ...form, role: event.target.value as AppRole, isDepartmentAdmin: event.target.value === 'manager' ? false : form.isDepartmentAdmin, isBranchAdmin: event.target.value === 'manager' ? false : form.isBranchAdmin })}><option value="employee">Nhân sự / Quản trị chi nhánh - phòng ban</option>{isSuperAdmin && <option value="manager">Quản trị toàn hệ thống (HQ)</option>}</select></label>
        
        {form.role === 'employee' && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', margin: '4px 0' }}>
            {isSuperAdmin && form.branchId && (
              <label className="user-check"><input type="checkbox" checked={form.isBranchAdmin} onChange={(event) => setForm({ ...form, isBranchAdmin: event.target.checked })} /> Quản trị Chi nhánh (Giám đốc / Admin Chi nhánh)</label>
            )}
            <label className="user-check"><input type="checkbox" checked={form.isDepartmentAdmin} onChange={(event) => setForm({ ...form, isDepartmentAdmin: event.target.checked })} /> Quản trị phòng/ban (Trưởng phòng)</label>
          </div>
        )}
        <button className="primary-button" disabled={submitting} type="submit">{submitting ? 'Đang tạo…' : 'Tạo tài khoản'}</button>
      </form>

      <div className="content-card user-list-card">
        <div className="card-heading"><div><h2>Danh sách tài khoản</h2><small>Không xóa tài khoản để giữ lịch sử thao tác.</small></div><span>{query ? `${filteredUsers.length}/${users.length}` : users.length} người</span></div>
        <div className="user-list-toolbar"><input type="search" value={query} onChange={(event) => { setQuery(event.target.value); setPage(1) }} placeholder="Tìm theo họ tên, tài khoản, chi nhánh, phòng ban…" aria-label="Tìm người dùng" /></div>
        {(error || success) && <div className={`user-page-alert alert ${error ? 'error' : 'success'}`}>{error ?? success}</div>}
        {loading && <div className="state-message">Đang tải người dùng…</div>}
        {!loading && users.length === 0 && <div className="state-message">Chưa có tài khoản.</div>}
        {!loading && users.length > 0 && !filteredUsers.length && <div className="state-message">Không có tài khoản khớp từ khóa.</div>}
        {!loading && visibleUsers.length > 0 && <><div className="table-wrap"><table className="users-table">
          <thead><tr><th>Người dùng</th><th>Chi nhánh</th><th>Phòng/ban</th><th>Vai trò</th><th>Trạng thái</th><th aria-label="Thao tác" /></tr></thead>
          <tbody>{visibleUsers.map((user) => {
            const isRoot = user.username === 'admin'
            const isSelf = user.id === profile?.id
            const busy = busyUserId === user.id
            const roleLabel = user.role === 'manager'
              ? 'Quản trị hệ thống'
              : user.is_branch_admin
              ? 'Quản trị Chi nhánh'
              : user.is_department_admin
              ? 'Quản trị phòng/ban'
              : 'Nhân viên'
            return <tr key={user.id}>
              <td><strong>{user.full_name}</strong><small className="user-account">@{user.username}{isRoot && <span className="root-badge">Gốc</span>}{isSelf && <span className="self-badge">Bạn</span>}</small></td>
              <td>{user.branch?.name || <span className="muted">Toàn hệ thống</span>}</td>
              <td>{user.department?.name || '—'}</td>
              <td>{roleLabel}</td>
              <td><span className={`status ${user.active ? 'active' : 'archived'}`}>{user.active ? 'Đang hoạt động' : 'Đã khóa'}</span></td>
              <td><div className="user-actions">
                <button className="btn" disabled={busy || isRoot} title={isRoot ? 'Tài khoản admin gốc không được chỉnh sửa' : undefined} onClick={() => setDialog({ kind: 'edit', user })}>Chỉnh sửa</button>
                <button className="btn" disabled={busy || isRoot} title={isRoot ? 'Tài khoản admin gốc không được đặt lại mật khẩu' : undefined} onClick={() => setDialog({ kind: 'password', user })}>Đặt lại mật khẩu</button>
                <button className={`btn ${user.active ? 'danger-outline' : ''}`} disabled={busy || isRoot || isSelf} title={isRoot ? 'Tài khoản admin gốc luôn được bảo vệ' : isSelf ? 'Không thể tự khóa tài khoản đang đăng nhập' : undefined} onClick={() => void toggleActive(user)}>{busy ? 'Đang xử lý…' : user.active ? 'Khóa' : 'Mở lại'}</button>
              </div></td>
            </tr>
          })}</tbody>
        </table></div>{pageCount > 1 && <div className="user-pagination"><span>Trang {currentPage}/{pageCount}</span><div><button className="btn" disabled={currentPage === 1} onClick={() => setPage(Math.max(1, currentPage - 1))}>← Trước</button><button className="btn" disabled={currentPage === pageCount} onClick={() => setPage(Math.min(pageCount, currentPage + 1))}>Sau →</button></div></div>}</>}
      </div>
    </div>

    {dialog?.kind === 'edit' && <EditUserDialog branches={branches} departments={departments} currentUserId={profile?.id ?? ''} isSuperAdmin={isSuperAdmin} user={dialog.user} onClose={() => setDialog(null)} onSaved={async (message) => { setDialog(null); setSuccess(message); notify(message); await loadData() }} />}
    {dialog?.kind === 'password' && <PasswordDialog user={dialog.user} onClose={() => setDialog(null)} onSaved={(message) => { setDialog(null); setSuccess(message); notify(message) }} />}
  </section>
}

function EditUserDialog({ branches, currentUserId, isSuperAdmin, user, departments, onClose, onSaved }: { branches: Branch[]; currentUserId: string; isSuperAdmin: boolean; user: UserProfile; departments: Department[]; onClose: () => void; onSaved: (message: string) => Promise<void> }) {
  const notify = useToast()
  const isRoot = user.username === 'admin'
  const isSelf = user.id === currentUserId
  const [fullName, setFullName] = useState(user.full_name)
  const [role, setRole] = useState(user.role)
  const [branchId, setBranchId] = useState(user.branch_id ?? '')
  const [isBranchAdmin, setIsBranchAdmin] = useState(user.is_branch_admin)
  const [departmentId, setDepartmentId] = useState(user.department_id ?? '')
  const [isDepartmentAdmin, setIsDepartmentAdmin] = useState(user.is_department_admin)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const availableDepartments = useMemo(() => {
    if (!branchId) return departments
    return departments.filter((d) => d.branch_id === branchId)
  }, [departments, branchId])

  const save = async (event: FormEvent) => {
    event.preventDefault()
    if (isRoot) { const message = 'Tài khoản admin gốc không được chỉnh sửa.'; setError(message); notify(message, 'error'); return }
    const nextName = fullName.trim()
    if (nextName.length < 2) { const message = 'Họ và tên phải có ít nhất 2 ký tự.'; setError(message); notify(message, 'error'); return }
    if (role === 'employee' && !departmentId) { const message = 'Nhân viên phải được gắn với một phòng/ban.'; setError(message); notify(message, 'error'); return }
    setSaving(true)
    setError(null)
    try {
      await updateUserProfile(
        user.id,
        nextName,
        role,
        branchId || null,
        role === 'employee' && isBranchAdmin,
        departmentId || null,
        role === 'employee' && isDepartmentAdmin
      )
      await onSaved(`Đã cập nhật tài khoản ${user.username}.`)
    }
    catch { const message = 'Không cập nhật được tài khoản. Kiểm tra quyền và dữ liệu nhập.'; setError(message); notify(message, 'error'); setSaving(false) }
  }

  return <div className="user-dialog-layer" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose() }}><form className="user-dialog" role="dialog" aria-modal="true" aria-labelledby="edit-user-title" onSubmit={save}>
    <div className="user-dialog-heading"><div><p className="eyebrow">CHỈNH SỬA TÀI KHOẢN</p><h2 id="edit-user-title">@{user.username}</h2></div><button type="button" className="user-dialog-close" aria-label="Đóng" onClick={onClose}>×</button></div>
    <label>Họ và tên<input required maxLength={100} value={fullName} onChange={(event) => setFullName(event.target.value)} autoFocus /></label>

    {isSuperAdmin && (
      <label>Chi nhánh<select value={branchId} disabled={isRoot} onChange={(event) => { setBranchId(event.target.value); setDepartmentId('') }}><option value="">Chưa gắn chi nhánh (Toàn hệ thống)</option>{branches.map((b) => <option key={b.id} value={b.id}>{b.name} ({b.code})</option>)}</select></label>
    )}

    <label>Phòng/ban<select value={departmentId} disabled={isRoot} onChange={(event) => setDepartmentId(event.target.value)}><option value="">Chưa gắn phòng/ban</option>{availableDepartments.map((department) => <option key={department.id} value={department.id}>{department.name}</option>)}</select></label>
    <label>Cấp quyền<select value={role} disabled={isRoot || isSelf} onChange={(event) => { const next = event.target.value as AppRole; setRole(next); if (next === 'manager') { setIsDepartmentAdmin(false); setIsBranchAdmin(false) } }}><option value="employee">Nhân sự / Quản trị chi nhánh - phòng ban</option>{isSuperAdmin && <option value="manager">Quản trị toàn hệ thống (HQ)</option>}</select><small>{isRoot ? 'Tài khoản admin gốc luôn giữ quyền Quản trị hệ thống.' : isSelf ? 'Không thể tự thay đổi cấp quyền của tài khoản đang đăng nhập.' : 'Quyền quản trị dự án được gắn riêng tại từng dự án.'}</small></label>
    
    {role === 'employee' && (
      <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', margin: '4px 0' }}>
        {isSuperAdmin && branchId && (
          <label className="user-check"><input type="checkbox" checked={isBranchAdmin} disabled={isRoot || isSelf} onChange={(event) => setIsBranchAdmin(event.target.checked)} /> Quản trị Chi nhánh (Giám đốc Chi nhánh)</label>
        )}
        <label className="user-check"><input type="checkbox" checked={isDepartmentAdmin} disabled={isRoot || isSelf} onChange={(event) => setIsDepartmentAdmin(event.target.checked)} /> Quản trị phòng/ban (Trưởng phòng)</label>
      </div>
    )}

    {error && <div className="alert error">{error}</div>}
    <div className="user-dialog-actions"><button type="button" className="btn" onClick={onClose}>Hủy bỏ</button><button className="btn pri" disabled={saving}>{saving ? 'Đang lưu…' : 'Lưu thay đổi'}</button></div>
  </form></div>
}

function PasswordDialog({ user, onClose, onSaved }: { user: UserProfile; onClose: () => void; onSaved: (message: string) => void }) {
  const notify = useToast()
  const [password, setPassword] = useState('')
  const [confirmation, setConfirmation] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const save = async (event: FormEvent) => {
    event.preventDefault()
    if (user.username === 'admin') { const message = 'Tài khoản admin gốc không được đặt lại mật khẩu.'; setError(message); notify(message, 'error'); return }
    if (password.length < 8) { const message = 'Mật khẩu mới phải có ít nhất 8 ký tự.'; setError(message); notify(message, 'error'); return }
    if (password !== confirmation) { const message = 'Hai lần nhập mật khẩu chưa khớp.'; setError(message); notify(message, 'error'); return }
    setSaving(true)
    setError(null)
    try { await resetUserPassword(user.id, password); onSaved(`Đã đặt lại mật khẩu cho tài khoản ${user.username}.`) }
    catch { const message = 'Không đặt lại được mật khẩu. Vui lòng thử lại.'; setError(message); notify(message, 'error'); setSaving(false) }
  }

  return <div className="user-dialog-layer" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose() }}><form className="user-dialog" role="dialog" aria-modal="true" aria-labelledby="reset-password-title" onSubmit={save}>
    <div className="user-dialog-heading"><div><p className="eyebrow">BẢO MẬT TÀI KHOẢN</p><h2 id="reset-password-title">Đặt lại mật khẩu</h2><p>{user.full_name} · @{user.username}</p></div><button type="button" className="user-dialog-close" aria-label="Đóng" onClick={onClose}>×</button></div>
    <label>Mật khẩu mới<input required minLength={8} type="password" autoComplete="new-password" value={password} onChange={(event) => setPassword(event.target.value)} autoFocus /></label>
    <label>Nhập lại mật khẩu<input required minLength={8} type="password" autoComplete="new-password" value={confirmation} onChange={(event) => setConfirmation(event.target.value)} /></label>
    {error && <div className="alert error">{error}</div>}
    <div className="user-dialog-actions"><button type="button" className="btn" onClick={onClose}>Hủy bỏ</button><button className="btn pri" disabled={saving}>{saving ? 'Đang cập nhật…' : 'Đặt lại mật khẩu'}</button></div>
  </form></div>
}
