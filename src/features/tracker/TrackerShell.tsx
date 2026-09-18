import { useCallback, useEffect, useRef, useState } from 'react'
import { useAuth } from '../auth/authContext'
import { UsersPage } from '../users/UsersPage'
import type { Branch, PersonalNotification, Project } from '../../types/domain'
import { PortfolioPage } from './PortfolioPage'
import { GanttView } from './GanttView'
import { MilestonesView } from './MilestonesView'
import { ApprovalsView } from './ApprovalsView'
import { ProjectOverview } from './ProjectOverview'
import { ProjectActivity } from './ProjectActivity'
import { getPersonalNotifications, getProjects, getUnreadWorkItemCount, markNotificationsSeen } from './trackerService'
import { listBranches } from '../users/userService'
import { tthLogoDataUrl } from '../../assets/tthLogo'
import { parseRouteHash, routeHash, type Page } from '../../lib/routes'
import '../../styles/prototype.css'
import '../../styles/tracker.css'
import { useConfirm } from '../../components/confirmContext'
import { ChangePasswordDialog } from '../auth/ChangePasswordDialog'
import { useAutoRefresh } from '../../lib/useAutoRefresh'
import { NotificationBell } from './NotificationBell'
import { useToast } from '../../components/toastContext'

export function TrackerShell() {
  const { profile, signOut } = useAuth()
  const initialRoute = parseRouteHash(window.location.hash)
  const [page, setPage] = useState<Page>(initialRoute.page)
  const [project, setProject] = useState<Project | null>(null)
  const [selectedWorkItemId, setSelectedWorkItemId] = useState<string | null>(initialRoute.workItemId)
  const [branches, setBranches] = useState<Branch[]>([])
  const [selectedBranchId, setSelectedBranchId] = useState<string | null>(null)
  const [clock, setClock] = useState(new Date())
  const [hasUnsavedChanges, setHasUnsavedChanges] = useState(false)
  const [unreadActivityCount, setUnreadActivityCount] = useState(0)
  const [showChangePassword, setShowChangePassword] = useState(false)
  const [hasManagedProject, setHasManagedProject] = useState(false)
  const [notifications, setNotifications] = useState<PersonalNotification[]>([])
  const [notificationsLoading, setNotificationsLoading] = useState(true)
  const dirtyRef = useRef(false)
  const lastHashRef = useRef(window.location.hash || routeHash('projects'))
  const confirm = useConfirm()
  const notify = useToast()
  const isSystemAdmin = profile?.role === 'manager'
  const isBranchAdmin = Boolean(profile?.is_branch_admin)
  const canManageUsers = Boolean(isSystemAdmin || isBranchAdmin)
  const isHeadquartersUser = Boolean(isSystemAdmin || profile?.branch?.is_headquarters || !profile?.branch_id)
  const canManageProject = Boolean(isSystemAdmin || (isBranchAdmin && isHeadquartersUser) || isBranchAdmin || project?.can_manage)
  const canReview = Boolean(isSystemAdmin || isBranchAdmin || profile?.is_department_admin || hasManagedProject)

  const activeBranchId = isHeadquartersUser ? selectedBranchId : (profile?.branch_id ?? null)

  useEffect(() => {
    void listBranches().then((list) => {
      setBranches(list)
    }).catch(() => undefined)
  }, [])

  useEffect(() => {
    document.documentElement.dataset.theme = 'light'
    const timer = window.setInterval(() => setClock(new Date()), 1000)
    return () => window.clearInterval(timer)
  }, [])
  useEffect(() => { if (profile) void getProjects().then((projects) => setHasManagedProject(projects.some((item) => item.can_manage))).catch(() => undefined) }, [profile])

  const trackDirty = useCallback((dirty: boolean) => {
    dirtyRef.current = dirty
    setHasUnsavedChanges(dirty)
  }, [])
  const clearUnreadActivity = useCallback(() => setUnreadActivityCount(0), [])
  const refreshUnreadActivity = useCallback(async () => {
    if (!project) { setUnreadActivityCount(0); return }
    setUnreadActivityCount(await getUnreadWorkItemCount(project.id))
  }, [project])
  const refreshNotifications = useCallback(async () => {
    if (!profile) return
    setNotificationsLoading(true)
    try { setNotifications(await getPersonalNotifications(profile.id)) } finally { setNotificationsLoading(false) }
  }, [profile])

  useEffect(() => {
    let active = true
    if (!project || page === 'gantt' || page === 'activity') return () => { active = false }
    void getUnreadWorkItemCount(project.id).then((count) => { if (active) setUnreadActivityCount(count) }).catch(() => undefined)
    return () => { active = false }
  }, [page, project])
  useAutoRefresh(() => refreshUnreadActivity().catch(() => undefined), { enabled: Boolean(project) && page !== 'gantt' && page !== 'activity' && !hasUnsavedChanges })
  useEffect(() => {
    const timer = window.setTimeout(() => void refreshNotifications().catch(() => setNotificationsLoading(false)), 0)
    return () => window.clearTimeout(timer)
  }, [page, refreshNotifications])
  useAutoRefresh(() => refreshNotifications().catch(() => undefined), { enabled: !hasUnsavedChanges })

  const applyRoute = useCallback(async (hash: string) => {
    if (!profile) return
    const route = parseRouteHash(hash)
    if ((route.page === 'users' && !isSystemAdmin) || (route.page === 'approvals' && !canReview)) {
      const fallback = routeHash('projects')
      window.history.replaceState(null, '', fallback)
      lastHashRef.current = fallback
      setProject(null)
      setSelectedWorkItemId(null)
      setPage('projects')
      return
    }
    if (route.projectKey) {
      const projects = await getProjects()
      const nextProject = projects.find((candidate) => candidate.id === route.projectKey || candidate.code.toLocaleLowerCase('vi') === route.projectKey!.toLocaleLowerCase('vi'))
      if (!nextProject) {
        const fallback = routeHash('projects')
        window.history.replaceState(null, '', fallback)
        lastHashRef.current = fallback
        setProject(null)
        setSelectedWorkItemId(null)
        setPage('projects')
        return
      }
      setProject(nextProject)
      setSelectedWorkItemId(route.workItemId)
      setUnreadActivityCount(0)
    } else if (route.page === 'projects') {
      setProject(null)
      setSelectedWorkItemId(null)
    } else {
      setSelectedWorkItemId(null)
    }
    setPage(route.page)
  }, [canReview, isSystemAdmin, profile])

  useEffect(() => {
    if (!profile) return
    if (!window.location.hash) window.history.replaceState(null, '', routeHash('projects'))
    lastHashRef.current = window.location.hash
    const initialRouteTimer = window.setTimeout(() => void applyRoute(window.location.hash), 0)

    const onHashChange = () => {
      const nextHash = window.location.hash || routeHash('projects')
      if (!dirtyRef.current) {
        lastHashRef.current = nextHash
        void applyRoute(nextHash)
        return
      }
      void confirm({ title: 'Rời màn hình?', message: 'Màn hình đang có thay đổi chưa lưu. Nếu rời đi, các thay đổi này sẽ bị bỏ.', confirmLabel: 'Rời đi', tone: 'danger' }).then((accepted) => {
        if (!accepted) {
          window.history.replaceState(null, '', lastHashRef.current)
          return
        }
        trackDirty(false)
        lastHashRef.current = nextHash
        void applyRoute(nextHash)
      })
    }
    window.addEventListener('hashchange', onHashChange)
    return () => { window.clearTimeout(initialRouteTimer); window.removeEventListener('hashchange', onHashChange) }
  }, [applyRoute, confirm, profile, trackDirty])

  const updateAddress = (nextPage: Page, nextProject: Project | null, workItemId: string | null = null) => {
    const hash = routeHash(nextPage, nextProject?.code ?? null, workItemId)
    window.history.pushState(null, '', hash)
    lastHashRef.current = hash
  }
  const openProject = (next: Project) => {
    setProject(next)
    setSelectedWorkItemId(null)
    setUnreadActivityCount(0)
    setPage('gantt')
    updateAddress('gantt', next)
  }
  const navigate = async (next: Page, clearProject = false) => {
    if (hasUnsavedChanges && !await confirm({ title: 'Rời màn hình?', message: 'Màn hình đang có thay đổi chưa lưu. Nếu rời đi, các thay đổi này sẽ bị bỏ.', confirmLabel: 'Rời đi', tone: 'danger' })) return
    trackDirty(false)
    const nextProject = clearProject ? null : project
    if (clearProject) setProject(null)
    setSelectedWorkItemId(null)
    setPage(next)
    updateAddress(next, nextProject)
  }
  const openWorkItem = async (workItemId: string | null) => {
    if (!project) return
    if (hasUnsavedChanges && !await confirm({ title: 'Rời màn hình?', message: 'Màn hình đang có thay đổi chưa lưu. Nếu rời đi, các thay đổi này sẽ bị bỏ.', confirmLabel: 'Rời đi', tone: 'danger' })) return
    trackDirty(false)
    setSelectedWorkItemId(workItemId)
    setPage('gantt')
    updateAddress('gantt', project, workItemId)
  }
  const updateSelectedWorkItem = useCallback((workItemId: string | null) => {
    setSelectedWorkItemId(workItemId)
    if (!project || page !== 'gantt') return
    const hash = routeHash('gantt', project.code, workItemId)
    window.history.replaceState(null, '', hash)
    lastHashRef.current = hash
  }, [page, project])
  const openNotification = async (notification: PersonalNotification) => {
    if (hasUnsavedChanges && !await confirm({ title: 'Rời màn hình?', message: 'Màn hình đang có thay đổi chưa lưu. Nếu rời đi, các thay đổi này sẽ bị bỏ.', confirmLabel: 'Rời đi', tone: 'danger' })) return false
    try {
      const projects = await getProjects()
      const targetProject = projects.find((candidate) => candidate.id === notification.project_id)
      if (!targetProject) {
        setNotifications((items) => items.map((item) => item.work_item_id === notification.work_item_id ? { ...item, isUnread: false } : item))
        return false
      }
      if (!profile) return false
      await markNotificationsSeen([notification.work_item_id], profile.id)
      setNotifications((items) => items.map((item) => item.work_item_id === notification.work_item_id ? { ...item, isUnread: false } : item))
      trackDirty(false)
      setProject(targetProject)
      setSelectedWorkItemId(notification.work_item_id)
      setPage('gantt')
      updateAddress('gantt', targetProject, notification.work_item_id)
      return true
    } catch {
      notify('Không mở được thông báo. Vui lòng thử lại.', 'error')
      return false
    }
  }
  const markAllNotificationsAsSeen = async () => {
    if (!profile) return
    try {
      await markNotificationsSeen(notifications.map((item) => item.work_item_id), profile.id)
      setNotifications((items) => items.map((item) => ({ ...item, isUnread: false })))
      if (project) setUnreadActivityCount(0)
      notify('Đã đánh dấu tất cả thông báo là đã đọc.')
    } catch {
      notify('Không đánh dấu được thông báo. Vui lòng thử lại.', 'error')
    }
  }
  const backToPortfolio = () => { void navigate('projects', true) }
  const projectPage = project && ['overview', 'gantt', 'milestones', 'activity'].includes(page)

  if (!profile) return null

  return <div className="app tracker-app">
    <aside className="side">
      <div className="brandbox"><img className="tth-logo" src={tthLogoDataUrl} alt="TTH GROUP" /><div><b>TTH GROUP</b><span>Nền tảng điều hành số</span></div></div>
      <div className="navwrap"><div className="navlabel">Quản lý tiến độ công việc</div><nav className="nav"><div className="sub root-sub">
        <button className={page === 'projects' ? 'on' : ''} onClick={backToPortfolio}>Tổng quan công việc</button>
        {project && <><div className="cap">{project.name}</div><button className={page === 'overview' ? 'on' : ''} onClick={() => navigate('overview')}>Tổng quan tiến độ</button><button className={page === 'gantt' ? 'on' : ''} onClick={() => navigate('gantt')}>Tiến độ &amp; Gantt</button><button className={page === 'milestones' ? 'on' : ''} onClick={() => navigate('milestones')}>Mốc kiểm soát</button><button className={page === 'activity' ? 'on' : ''} onClick={() => navigate('activity')}><span>Nhật ký diễn biến</span>{unreadActivityCount > 0 && <span className="nav-activity-badge" title={`${unreadActivityCount} công việc có diễn biến mới`} aria-label={`${unreadActivityCount} công việc có diễn biến mới`}><i className="nav-activity-pulse" aria-hidden="true" /><b>{unreadActivityCount > 99 ? '99+' : unreadActivityCount}</b></span>}</button></>}
      </div>{(canReview || canManageUsers) && <><div className="navlabel nav-section">Quản trị</div><div className="sub root-sub">{canReview && <button className={page === 'approvals' ? 'on' : ''} onClick={() => navigate('approvals')}>Chờ duyệt</button>}{canManageUsers && <button className={page === 'users' ? 'on' : ''} onClick={() => navigate('users')}>{isSystemAdmin ? 'Người dùng & Chi nhánh' : 'Quản lý người dùng'}</button>}</div></>}</nav></div>
      <div className="clock"><b>{clock.toLocaleTimeString('vi-VN')}</b><span>{clock.toLocaleDateString('vi-VN', { weekday: 'short', day: '2-digit', month: '2-digit' })}</span></div>
    </aside>
      <div className="main"><header className="top">
        {isHeadquartersUser ? (
          <div className="branch-selector-wrap" style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ fontSize: 13, fontWeight: 600, color: 'var(--muted)' }}>Giám sát chi nhánh:</span>
            <select
              className="branch-select"
              value={selectedBranchId || ''}
              onChange={(e) => setSelectedBranchId(e.target.value || null)}
              style={{ padding: '4px 8px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--card-bg, #fff)', fontSize: 13 }}
            >
              <option value="">Toàn bộ Tập đoàn (Tất cả)</option>
              {branches.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.name} ({b.code}){b.is_headquarters ? ' ⭐' : ''}
                </option>
              ))}
            </select>
          </div>
        ) : profile.branch ? (
          <div className="chip branch-badge" title={profile.branch.name}>
            📍 {profile.branch.name}
          </div>
        ) : null}
        <span className="top-spacer" />{projectPage && <div className="chip">{project.code}</div>}<NotificationBell items={notifications} loading={notificationsLoading} onOpen={openNotification} onMarkAllSeen={markAllNotificationsAsSeen} /><div className="whoami"><div><b>{profile.full_name}</b><span>{isSystemAdmin ? 'Quản trị hệ thống' : isBranchAdmin ? 'Quản trị Chi nhánh' : canManageProject ? 'Quản trị dự án' : profile.is_department_admin ? 'Quản trị phòng/ban' : 'Nhân viên'}</span></div><div className="av account-department-tag">{isSystemAdmin ? 'ADMIN' : profile.department?.code || '—'}</div>{profile.username !== 'admin' && <button className="logout-mini" onClick={() => setShowChangePassword(true)}>Đổi mật khẩu</button>}<button className="logout-mini" onClick={() => void signOut()}>Đăng xuất</button></div></header>
      <main className="view">{page === 'projects' && <PortfolioPage isManager={isSystemAdmin} isBranchAdmin={isBranchAdmin} isDepartmentAdmin={profile.is_department_admin} currentBranchId={activeBranchId} branches={branches} onOpen={openProject} />}{page === 'overview' && project && <ProjectOverview project={project} onBack={backToPortfolio} onOpenWork={(workItemId) => void openWorkItem(workItemId)} />}{page === 'gantt' && project && <GanttView project={project} profile={profile} initialWorkItemId={selectedWorkItemId} onSelectedWorkItemChange={updateSelectedWorkItem} onBack={backToPortfolio} onDirtyChange={trackDirty} onUnreadCountChange={setUnreadActivityCount} />}{page === 'milestones' && project && <MilestonesView project={project} isManager={canManageProject} onBack={backToPortfolio} onDirtyChange={trackDirty} />}{page === 'activity' && project && <ProjectActivity project={project} profile={profile} canViewDeleteAudit={canManageProject} onBack={backToPortfolio} onOpenGantt={(workItemId) => void openWorkItem(workItemId)} onSeen={clearUnreadActivity} />}{page === 'approvals' && canReview && <ApprovalsView isManager />}{page === 'users' && canManageUsers && <div className="users-host"><UsersPage /></div>}</main>
    </div>{showChangePassword && profile.username !== 'admin' && <ChangePasswordDialog onClose={() => setShowChangePassword(false)} />}
  </div>
}
