import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react'
import type { CompletionRequest, Department, Milestone, Profile, Project, ProgressUpdate, UserProfile, WorkItem, WorkItemStatus } from '../../types/domain'
import { addProgress, cloneProjectPlan, createWorkItem, getDepartments, getMilestones, getPendingRequests, getProgressUpdates, getProjects, getUsers, getWorkItems, importProjectPlan, markWorkItemActivitySeen, removeEvidence, removeWorkItem, requestCompletion, reviewRequest, saveWorkItem, saveWorkItemParticipants, uploadEvidence, viewEvidence } from './trackerService'
import { exportProject } from './excelService'
import { ExcelImportModal } from './ExcelImportModal'
import { ProjectHeader } from './ProjectHeader'
import { DepartmentMultiSelect } from './DepartmentMultiSelect'
import { ParticipantMultiSelect } from './ParticipantMultiSelect'
import { eligibleParticipants, retainEligibleParticipantIds } from './participantEligibility'
import { defaultWorkScope, filterWorkItemsByScope, matchesWorkScopeDirect, type WorkScope } from './workScope'
import { useConfirm } from '../../components/confirmContext'
import { useAutoRefresh } from '../../lib/useAutoRefresh'
import { canAddChildWorkItem, canCompleteWorkItemDirectly, canEditWorkItem, canManageWorkItemStructure, canReviewCompletion, canViewWorkItemDetails, participantManagementScope } from '../../lib/permissions'
import { displayWorkItemWbs } from './workItemDisplay'
import { useToast } from '../../components/toastContext'

const labels: Record<WorkItemStatus, string> = { not_started: 'Chưa thực hiện', in_progress: 'Đang thực hiện', pending_approval: 'Chờ duyệt', completed: 'Hoàn thành' }
const classes: Record<WorkItemStatus | 'late', string> = { not_started: 'p-todo', in_progress: 'p-doing', pending_approval: 'p-pending', completed: 'p-done', late: 'p-late' }
type DrawerTab = 'info' | 'evidence' | 'log' | 'approval'

export function GanttView({ project, profile, initialWorkItemId, onSelectedWorkItemChange, onBack, onDirtyChange, onUnreadCountChange }: { project: Project; profile: Profile; initialWorkItemId: string | null; onSelectedWorkItemChange: (workItemId: string | null) => void; onBack: () => void; onDirtyChange: (dirty: boolean) => void; onUnreadCountChange: (count: number) => void }) {
  const canManageProject = profile.role === 'manager' || project.can_manage
  const notify = useToast()
  const [items, setItems] = useState<WorkItem[]>([])
  const [users, setUsers] = useState<UserProfile[]>([])
  const [departments, setDepartments] = useState<Department[]>([])
  const [milestones, setMilestones] = useState<Milestone[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [query, setQuery] = useState('')
  const [leadFilter, setLeadFilter] = useState('')
  const [filter, setFilter] = useState<WorkItemStatus | 'late' | ''>('')
  const [scope, setScope] = useState<WorkScope>(() => defaultWorkScope(profile.role, canManageProject, profile.is_department_admin))
  const [zoom, setZoom] = useState<'day' | 'week' | 'month'>('week')
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set())
  const [selected, setSelected] = useState<string | null>(null)
  const [draftItem, setDraftItem] = useState<WorkItem | null>(null)
  const [showImport, setShowImport] = useState(false)
  const [showClone, setShowClone] = useState(false)
  const [drawerDirty, setDrawerDirty] = useState(false)
  const [drawerTab, setDrawerTab] = useState<DrawerTab>('info')
  const [cloneSources, setCloneSources] = useState<Project[]>([])
  const [cloneSourceId, setCloneSourceId] = useState('')
  const [cloneStart, setCloneStart] = useState(project.start_date ?? today())

  const applyItems = useCallback((nextItems: WorkItem[]) => { setItems(nextItems); onUnreadCountChange(nextItems.filter((item) => item.has_unseen_activity).length) }, [onUnreadCountChange])
  const load = async () => { const [nextItems, nextUsers, nextMilestones, nextDepartments] = await Promise.all([getWorkItems(project.id), getUsers(project.branch_id), getMilestones(project.id), getDepartments(project.branch_id)]); applyItems(nextItems); setUsers(nextUsers); setMilestones(nextMilestones); setDepartments(nextDepartments) }
  useEffect(() => { let active = true; void Promise.all([getWorkItems(project.id), getUsers(project.branch_id), getMilestones(project.id), getDepartments(project.branch_id)]).then(([nextItems, nextUsers, nextMilestones, nextDepartments]) => { if (!active) return; applyItems(nextItems); setUsers(nextUsers); setMilestones(nextMilestones); setDepartments(nextDepartments) }).catch(() => { if (active) setError('Không tải được tiến độ dự án.') }).finally(() => { if (active) setLoading(false) }); return () => { active = false } }, [project.id, project.branch_id, applyItems])
  useAutoRefresh(() => load().catch(() => setError('Không tự cập nhật được dữ liệu mới.')), { enabled: !drawerDirty && !showImport && !showClone })
  useEffect(() => {
    if (!initialWorkItemId || loading) return
    const timer = window.setTimeout(() => {
      const item = items.find((candidate) => candidate.id === initialWorkItemId)
      if (!item) {
        setError('Công việc trong đường dẫn không còn tồn tại hoặc đã bị xóa.')
        onSelectedWorkItemChange(null)
        return
      }
      if (selected === item.id) return
      if (!filterWorkItemsByScope(items, scope, profile.id, profile.department_id).some((candidate) => candidate.id === item.id)) setScope('visible')
      setDraftItem(null)
      setSelected(item.id)
      setDrawerTab(canReviewCompletion({ profile, projectCanManage: canManageProject, leadDepartmentId: item.lead_department_id }) && item.status === 'pending_approval' ? 'approval' : 'info')
      setCollapsed((current) => {
        const next = new Set(current)
        let parentId = item.parent_id
        while (parentId) { next.delete(parentId); parentId = items.find((candidate) => candidate.id === parentId)?.parent_id ?? null }
        return next
      })
      if (item.has_unseen_activity) void markWorkItemActivitySeen(item.id, profile.id).catch(() => setError('Không đánh dấu được diễn biến đã xem.'))
    }, 0)
    return () => window.clearTimeout(timer)
  }, [canManageProject, initialWorkItemId, items, loading, onSelectedWorkItemChange, profile, scope, selected])

  const children = useMemo(() => groupByParent(items), [items])
  const scopedItems = useMemo(() => filterWorkItemsByScope(items, scope, profile.id, profile.department_id), [items, profile.department_id, profile.id, scope])
  const scopedChildren = useMemo(() => groupByParent(scopedItems), [scopedItems])
  const collapsibleIds = useMemo(() => scopedItems.filter((item) => scopedChildren.get(item.id)?.length).map((item) => item.id), [scopedChildren, scopedItems])
  const allCollapsed = collapsibleIds.length > 0 && collapsibleIds.every((id) => collapsed.has(id))
  const allLeaves = items.filter((item) => !(children.get(item.id)?.length))
  const leaves = scopedItems.filter((item) => !(children.get(item.id)?.length))
  const counts = countStatuses(leaves)
  const scopeCounts = {
    mine: allLeaves.filter((item) => matchesWorkScopeDirect(item, 'mine', profile.id, profile.department_id)).length,
    department: allLeaves.filter((item) => matchesWorkScopeDirect(item, 'department', profile.id, profile.department_id)).length,
    visible: allLeaves.length,
  }
  const leads = [...new Map(leaves.flatMap((item) => item.lead_department ? [[item.lead_department.id, item.lead_department] as const] : [])).values()].sort((a, b) => a.code.localeCompare(b.code))
  const startDate = minDate([project.start_date, ...allLeaves.map((item) => item.start_date), ...milestones.map((item) => item.due_date)]) || today()
  const endDate = maxDate([project.end_date, ...allLeaves.map((item) => item.end_date), ...milestones.map((item) => item.due_date)]) || startDate
  const pixelsPerDay = zoom === 'day' ? 22 : zoom === 'week' ? 7 : 3
  const totalDays = Math.max(1, dayDiff(startDate, endDate) + 1)
  const width = totalDays * pixelsPerDay
  const flatRows = flatten(scopedItems, scopedChildren, collapsed).filter((item) => {
    const departmentText = [item.lead_department, ...item.coordinating_departments].filter((department): department is Department => Boolean(department)).map((department) => `${department.code} ${department.name}`).join(' ')
    const matchesText = !query || `${item.wbs} ${item.name} ${departmentText}`.toLowerCase().includes(query.toLowerCase())
    const matchesLead = !leadFilter || item.lead_department_id === leadFilter || descendants(item.id, scopedItems).some((child) => child.lead_department_id === leadFilter)
    const state = aggregateStatus(item, scopedItems, scopedChildren)
    return matchesText && matchesLead && (!filter || state === filter)
  })
  const selectedItem = items.find((item) => item.id === selected) ?? null
  const unreadActivityCount = items.filter((item) => item.has_unseen_activity).length
  const structureAccess = (item: WorkItem) => ({
    role: profile.role,
    canManageProject,
    departmentId: profile.department_id,
    isDepartmentAdmin: profile.is_department_admin,
    parentId: item.parent_id,
    leadDepartmentIdsInPath: leadDepartmentPath(item, items),
  })
  const canManageItem = (item: WorkItem) => canManageWorkItemStructure(structureAccess(item))
  const canAddChild = (item: WorkItem) => canAddChildWorkItem(structureAccess(item))
  const canViewDetails = (item: WorkItem) => {
    const branch = [item, ...descendants(item.id, items)]
    return canViewWorkItemDetails({
      ...structureAccess(item),
      leadDepartmentIdsInBranch: branch.map((candidate) => candidate.lead_department_id),
      coordinatingDepartmentIds: branch.flatMap((candidate) => candidate.coordinating_department_ids),
      participantIds: branch.flatMap((candidate) => candidate.participant_ids),
      userId: profile.id,
    })
  }

  const toggle = (id: string) => setCollapsed((current) => { const next = new Set(current); if (next.has(id)) next.delete(id); else next.add(id); return next })
  const run = async (action: () => Promise<void>, successMessage: string) => { setError(null); try { await action(); await load(); notify(successMessage) } catch (caught) { const message = caught instanceof Error ? caught.message : 'Không thực hiện được thao tác.'; setError(message); notify(message, 'error') } }
  const scrollToday = () => { const container = document.querySelector<HTMLElement>('.tt'); const line = container?.querySelector<HTMLElement>('.now'); if (container && line) container.scrollLeft = Math.max(0, line.offsetLeft - container.clientWidth * 0.55) }
  const openClone = async () => { try { const projects = (await getProjects()).filter((item) => item.id !== project.id); const viable = (await Promise.all(projects.map(async (item) => ({ item, hasPlan: (await getWorkItems(item.id)).length > 0 })))).filter((entry) => entry.hasPlan).map((entry) => entry.item); setCloneSources(viable); setCloneSourceId(viable[0]?.id ?? ''); setShowClone(true) } catch { const message = 'Không tải được danh sách dự án để nhân bản.'; setError(message); notify(message, 'error') } }
  const reportDirty = useCallback((dirty: boolean) => { setDrawerDirty(dirty); onDirtyChange(dirty) }, [onDirtyChange])
  const openDraft = (parent: WorkItem | null) => {
    if ((!parent && !canManageProject) || (parent && !canAddChild(parent))) {
      setError('Kế hoạch đã được khóa. Chỉ Quản trị dự án hoặc Quản trị hệ thống được thêm đầu mục công việc.')
      return
    }
    setSelected(null); setDrawerTab('info'); onSelectedWorkItemChange(null); setDraftItem(makeDraft(project.id, parent, items))
  }
  const openExisting = (item: WorkItem) => {
    setDraftItem(null)
    if (selected !== item.id) setDrawerTab(canReviewCompletion({ profile, projectCanManage: canManageProject, leadDepartmentId: item.lead_department_id }) && item.status === 'pending_approval' ? 'approval' : 'info')
    setSelected(item.id)
    onSelectedWorkItemChange(item.id)
    if (!canViewDetails(item) || !item.has_unseen_activity) return
    const nextItems = items.map((candidate) => candidate.id === item.id ? { ...candidate, has_unseen_activity: false } : candidate)
    applyItems(nextItems)
    void markWorkItemActivitySeen(item.id, profile.id).catch(() => setError('Không đánh dấu được diễn biến đã xem.'))
  }
  const closeDrawer = () => { reportDirty(false); setSelected(null); setDraftItem(null); onSelectedWorkItemChange(null) }
  const created = async () => { await load(); reportDirty(false); setDraftItem(null); setSelected(null); onSelectedWorkItemChange(null) }

  if (!loading && !items.length) return <><ProjectHeader project={project} section="Tiến độ & sơ đồ Gantt" onBack={onBack} />{error && <div className="note warn offline">{error}</div>}<div className="card empty empty-plan"><h3>Dự án này chưa có tiến độ chi tiết</h3><p className="muted">Tạo bộ hạng mục bằng cách nhân bản từ một dự án đã có, hoặc thêm từng hạng mục.</p>{canManageProject ? <div className="row2"><button className="btn pri" onClick={() => setShowImport(true)}>Nạp từ file Excel</button><button className="btn" onClick={() => void openClone()}>Nhân bản từ dự án khác</button><button className="btn" onClick={() => openDraft(null)}>Thêm hạng mục thủ công</button></div> : <div className="tiny muted">Quản trị dự án chưa thiết lập tiến độ cho dự án này.</div>}</div>{draftItem && <WorkDrawer projectCanManage={canManageProject} canViewDetails canManageStructure canAddChild={false} item={draftItem} items={items} users={users} departments={departments} profile={profile} isNew tab={drawerTab} onTabChange={setDrawerTab} onClose={closeDrawer} onCreated={created} onAddChild={openDraft} onChanged={load} onError={setError} onDirtyChange={reportDirty} />}{showImport && <ExcelImportModal onClose={() => setShowImport(false)} onImport={async (imported) => { await importProjectPlan(project.id, imported); await load() }} />}{showClone && <CloneModal sources={cloneSources} sourceId={cloneSourceId} startDate={cloneStart} onSourceChange={setCloneSourceId} onStartChange={setCloneStart} onClose={() => setShowClone(false)} onClone={async () => { await run(() => cloneProjectPlan(project.id, cloneSourceId, cloneStart), 'Đã nhân bản tiến độ từ dự án được chọn.'); setShowClone(false) }} />}</>

  return <>
    <ProjectHeader project={project} section="Tiến độ & sơ đồ Gantt" onBack={onBack} />
    {error && <div className="note warn offline">{error}</div>}
    <div className="sum"><div className="u"><b>{leaves.length}</b><span>Công việc</span></div><div className="u"><b>{counts.completed}</b><span>Hoàn thành</span></div><div className="u"><b>{counts.in_progress}</b><span>Đang thực hiện</span></div><div className="u"><b className="dl">{counts.late}</b><span>Quá hạn</span></div><div className="u"><b className="dw">{counts.pending_approval}</b><span>Chờ duyệt</span></div><div className="grow"><span className="tiny muted">Tiến độ chung {leaves.length ? Math.round(counts.completed / leaves.length * 100) : 0}%</span><div className="bar"><i style={{ width: `${leaves.length ? counts.completed / leaves.length * 100 : 0}%`, background: 'var(--st-done)' }} /></div></div></div>
    {unreadActivityCount > 0 && <button className="activity-unread-note" onClick={() => { const first = items.find((item) => item.has_unseen_activity); if (first) openExisting(first) }}><span className="activity-pulse" aria-hidden="true" /><span><b>{unreadActivityCount} công việc có diễn biến mới</b><small>Bấm để mở công việc đầu tiên chưa xem.</small></span><strong>Xem ngay →</strong></button>}
    {!canManageProject && <div className="note plan-locked-note"><b>Kế hoạch đã được chốt.</b> Chỉ Quản trị dự án hoặc Quản trị hệ thống được thêm, sửa hoặc xóa đầu mục. Bạn vẫn có thể cập nhật diễn biến, bằng chứng và xử lý công việc theo quyền được giao.</div>}
    <div className="work-scope"><span>Phạm vi hiển thị</span><div className="seg" role="group" aria-label="Phạm vi công việc"><button className={scope === 'mine' ? 'on' : ''} onClick={() => setScope('mine')}>Việc của tôi <b>{scopeCounts.mine}</b></button>{profile.is_department_admin && profile.department_id && <button className={scope === 'department' ? 'on' : ''} onClick={() => setScope('department')}>Công việc phòng tôi <b>{scopeCounts.department}</b></button>}<button className={scope === 'visible' ? 'on' : ''} onClick={() => setScope('visible')}>{profile.is_department_admin ? 'Tất cả tiến độ' : 'Tất cả công việc liên quan'} <b>{scopeCounts.visible}</b></button></div><small>{scope === 'mine' ? 'Chỉ hiển thị việc bạn được giao và các hạng mục cha liên quan.' : scope === 'department' ? 'Hiển thị công việc do phòng/ban của bạn chủ trì hoặc phối hợp.' : profile.is_department_admin ? 'Hiển thị toàn bộ tiến độ dự án; chi tiết nghiệp vụ chỉ mở với công việc liên quan đến phòng/ban của bạn.' : 'Hiển thị toàn bộ công việc tài khoản này có quyền xem.'}</small></div>
    <div className="tbar"><div><input type="search" placeholder="Tìm đầu việc…" value={query} onChange={(event) => setQuery(event.target.value)} /><select aria-label="Lọc theo đơn vị chủ trì" value={leadFilter} onChange={(event) => setLeadFilter(event.target.value)}><option value="">Tất cả đơn vị chủ trì</option>{leads.map((lead) => <option key={lead.id} value={lead.id}>{lead.code}</option>)}</select><StatusFilter value="" active={filter === ''} count={leaves.length} label="Tất cả" onClick={() => setFilter('')} />{(['not_started','in_progress','pending_approval','completed','late'] as const).map((state) => <StatusFilter key={state} value={state} active={filter === state} count={counts[state]} label={state === 'late' ? 'Quá hạn' : labels[state]} onClick={() => setFilter(filter === state ? '' : state)} />)}</div><div><div className="seg">{(['day','week','month'] as const).map((value) => <button key={value} className={zoom === value ? 'on' : ''} onClick={() => setZoom(value)}>{value === 'day' ? 'Ngày' : value === 'week' ? 'Tuần' : 'Tháng'}</button>)}</div><button className="btn" onClick={scrollToday}>Hôm nay</button><button className="btn" aria-pressed={allCollapsed} onClick={() => setCollapsed(allCollapsed ? new Set() : new Set(collapsibleIds))}>{allCollapsed ? 'Mở rộng tất cả' : 'Thu gọn tất cả'}</button><button className="btn" onClick={() => void exportProject(project, items).then(() => notify('Đã xuất file Excel tiến độ.')).catch((caught) => { const message = caught instanceof Error ? caught.message : 'Không xuất được Excel.'; setError(message); notify(message, 'error') })}>Xuất Excel</button>{canManageProject && <button className="btn" onClick={() => setShowImport(true)}>Nạp Excel</button>}<span style={{ flex: 1 }} />{canManageProject && <button className="btn pri" onClick={() => openDraft(null)}>+ Hạng mục</button>}</div></div>
    {loading ? <div className="card empty">Đang tải tiến độ…</div> : <div className="tt"><div className="trow thead"><div className="lft"><div className="cell c-wbs">Mã</div><div className="cell c-name">Hạng mục công việc</div><div className="cell c-lead">Chủ trì</div><div className="cell c-d">Bắt đầu</div><div className="cell c-d">Kết thúc</div><div className="cell c-n">Số ngày</div><div className="cell c-st">Trạng thái</div><div className="cell c-act" /></div><TimelineHeader start={startDate} end={endDate} width={width} pixelsPerDay={pixelsPerDay} zoom={zoom} milestones={milestones} /></div>{flatRows.map((item) => {
      const ownChildren = scopedChildren.get(item.id) ?? []
      const span = ownChildren.length ? spanOf(item, scopedItems) : { start: item.start_date, end: item.end_date }
      const state = aggregateStatus(item, scopedItems, scopedChildren)
      const left = span.start ? dayDiff(startDate, span.start) * pixelsPerDay : 0
      const barWidth = span.start && span.end ? Math.max(3, (dayDiff(span.start, span.end) + 1) * pixelsPerDay) : 0
      return <div className={`trow ${ownChildren.length ? 'g' : ''} ${selected === item.id ? 'sel' : ''}`} key={item.id} onClick={() => openExisting(item)}><div className="lft"><div className="cell c-wbs">{ownChildren.length > 0 && <button className="exp" onClick={(event) => { event.stopPropagation(); toggle(item.id) }}>{collapsed.has(item.id) ? '▶' : '▼'}</button>}{displayWorkItemWbs(item.wbs)}</div><div className="cell c-name" style={{ paddingLeft: 8 + depth(item, scopedItems) * 12 }}>{item.has_unseen_activity && <span className="activity-new-badge" title="Có diễn biến mới" aria-label="Có diễn biến mới"><i className="activity-pulse" aria-hidden="true" />Mới</span>}{item.name}</div><div className="cell c-lead" title={responsibilityLabel(item)}>{item.lead_department?.name || '—'}</div><div className="cell c-d">{date(span.start)}</div><div className="cell c-d">{date(span.end)}</div><div className="cell c-n">{span.start && span.end ? dayDiff(span.start, span.end) + 1 : '—'}</div><div className="cell c-st"><span className={`pill ${classes[state]} ${ownChildren.length ? 'status-summary' : 'status-leaf'}`} title={ownChildren.length ? 'Trạng thái tổng hợp từ các công việc cuối nhánh' : 'Trạng thái của công việc cuối nhánh'}><i />{state === 'late' ? 'Quá hạn' : labels[state]}</span></div><div className="cell c-act">{canAddChild(item) && <button className="rowbtn" title="Thêm công việc con" onClick={(event) => { event.stopPropagation(); openDraft(item) }}>+</button>}</div></div><div className="time" style={{ width, backgroundImage: `repeating-linear-gradient(90deg,var(--line-2) 0 1px,transparent 1px ${7 * pixelsPerDay}px)` }}>{barWidth > 0 && <div className={`gbar ${ownChildren.length ? 'pbar' : ''}`} style={{ left, width: barWidth, background: ownChildren.length ? undefined : statusColor(state) }}>{item.has_unseen_activity && <span className="gantt-activity-pulse" />}<span className="gbar-label">{item.name}</span></div>}<TodayLine start={startDate} pixelsPerDay={pixelsPerDay} /></div></div>
    })}{!flatRows.length && <div className="empty">Không có đầu việc nào khớp bộ lọc.</div>}</div>}
    {(draftItem ?? selectedItem) && <WorkDrawer projectCanManage={canManageProject} canViewDetails={draftItem ? true : canViewDetails(selectedItem!)} canManageStructure={draftItem ? (draftItem.parent_id === null ? canManageProject : Boolean(items.find((item) => item.id === draftItem.parent_id && canAddChild(item)))) : canManageItem(selectedItem!)} canAddChild={draftItem ? false : canAddChild(selectedItem!)} key={`${(draftItem ?? selectedItem)!.id}-${(draftItem ?? selectedItem)!.version}-${(draftItem ?? selectedItem)!.attachment?.id ?? ''}`} item={(draftItem ?? selectedItem)!} items={items} users={users} departments={departments} profile={profile} isNew={Boolean(draftItem)} tab={drawerTab} onTabChange={setDrawerTab} onClose={closeDrawer} onCreated={created} onAddChild={openDraft} onChanged={load} onError={setError} onDirtyChange={reportDirty} />}
    {showImport && <ExcelImportModal onClose={() => setShowImport(false)} onImport={async (imported) => { await importProjectPlan(project.id, imported); await load() }} />}
  </>
}

function CloneModal({ sources, sourceId, startDate, onSourceChange, onStartChange, onClose, onClone }: { sources: Project[]; sourceId: string; startDate: string; onSourceChange: (value: string) => void; onStartChange: (value: string) => void; onClose: () => void; onClone: () => Promise<void> }) {
  return <div className="modal on" role="dialog" aria-modal="true" aria-label="Nhân bản bộ hạng mục"><div className="mbox"><header><h2>Nhân bản bộ hạng mục</h2><button className="btn" onClick={onClose}>✕</button></header><div className="mbody">{sources.length ? <><label className="f"><span>Lấy từ dự án</span><select value={sourceId} onChange={(event) => onSourceChange(event.target.value)}>{sources.map((source) => <option value={source.id} key={source.id}>{source.name}</option>)}</select></label><label className="f"><span>Ngày bắt đầu của dự án mới</span><input type="date" value={startDate} onChange={(event) => onStartChange(event.target.value)} /></label><div className="note">Ngày kế hoạch được dịch theo ngày bắt đầu mới. Trạng thái, bằng chứng, người tham gia và diễn biến không nhân bản.</div></> : <div className="empty">Chưa có dự án nào khác có tiến độ để nhân bản.</div>}</div><footer className="mfoot"><button className="btn" onClick={onClose}>Hủy</button><button className="btn pri" disabled={!sourceId || !startDate} onClick={() => void onClone()}>Nhân bản</button></footer></div></div>
}

function WorkDrawer({ item, items, users, departments, profile, projectCanManage, canViewDetails, canManageStructure, canAddChild, isNew, tab, onTabChange, onClose, onCreated, onAddChild, onChanged, onError, onDirtyChange }: { item: WorkItem; items: WorkItem[]; users: UserProfile[]; departments: Department[]; profile: Profile; projectCanManage: boolean; canViewDetails: boolean; canManageStructure: boolean; canAddChild: boolean; isNew: boolean; tab: DrawerTab; onTabChange: (tab: DrawerTab) => void; onClose: () => void; onCreated: (id: string) => Promise<void>; onAddChild: (parent: WorkItem) => void; onChanged: () => Promise<void>; onError: (message: string | null) => void; onDirtyChange: (dirty: boolean) => void }) {
  const notify = useToast()
  const initialForm = () => ({ name: item.name, leadDepartmentId: item.lead_department_id ?? '', coordinatingDepartmentIds: item.coordinating_department_ids, startDate: item.start_date ?? '', endDate: item.end_date ?? '', status: item.status, participantIds: retainEligibleParticipantIds(item.participant_ids, users, item.lead_department_id ?? '', item.coordinating_department_ids) })
  const [form, setForm] = useState(initialForm)
  const [updates, setUpdates] = useState<ProgressUpdate[]>([])
  const [note, setNote] = useState('')
  const [pendingRequest, setPendingRequest] = useState<CompletionRequest | null>(null)
  const [reviewNote, setReviewNote] = useState('')
  const canReviewItem = canViewDetails && canReviewCompletion({ profile, projectCanManage, leadDepartmentId: item.lead_department_id })
  const completesDirectly = canCompleteWorkItemDirectly({ profile, projectCanManage, leadDepartmentId: item.lead_department_id })
  const [approvalLoading, setApprovalLoading] = useState(canReviewItem && item.status === 'pending_approval')
  const [busy, setBusy] = useState(false)
  const confirm = useConfirm()
  const hasChildren = items.some((candidate) => candidate.parent_id === item.id)
  const isGroup = item.parent_id === null || hasChildren
  const displayedStatus = aggregateStatus(item, items, groupByParent(items))
  const canUpdate = canViewDetails && canEditWorkItem({ role: profile.role, canManageProject: projectCanManage, userId: profile.id, participantIds: item.participant_ids })
  const isEvidenceLocked = !isNew && (item.status === 'pending_approval' || item.status === 'completed')
  const canEditInfo = canManageStructure
  const participantScope = participantManagementScope({
    role: profile.role,
    canManageProject: projectCanManage,
    departmentId: profile.department_id,
    isDepartmentAdmin: profile.is_department_admin,
    leadDepartmentId: item.lead_department_id,
    coordinatingDepartmentIds: item.coordinating_department_ids,
  })
  const canManageParticipants = !isNew && !isGroup && participantScope !== 'none'
  const canManageEvidence = canUpdate && !isEvidenceLocked
  const canLogProgress = canUpdate
  const participantUsers = useMemo(
    () => eligibleParticipants(users, form.leadDepartmentId, form.coordinatingDepartmentIds),
    [form.coordinatingDepartmentIds, form.leadDepartmentId, users],
  )
  const participantUsersForManager = participantScope === 'own_department'
    ? participantUsers.filter((user) => user.department_id === profile.department_id)
    : participantUsers
  const progressLockReason = !canUpdate
    ? (isGroup ? 'Nhân viên chỉ ghi diễn biến tại công việc chi tiết được phân công.' : 'Bạn chỉ có quyền xem công việc này. Quản trị viên cần thêm bạn vào danh sách người tham gia để cập nhật.')
    : null
  const dirty = isNew || JSON.stringify(form) !== JSON.stringify(initialForm())
  useEffect(() => {
    if (isNew || !canViewDetails) return
    void getProgressUpdates(item.id).then(setUpdates)
  }, [canViewDetails, isNew, item.id])
  useEffect(() => {
    if (!canReviewItem || item.status !== 'pending_approval') return
    let active = true
    void getPendingRequests().then((requests) => { if (active) setPendingRequest(requests.find((request) => request.work_item_id === item.id) ?? null) }).catch(() => { if (active) onError('Không tải được yêu cầu chờ duyệt của công việc.') }).finally(() => { if (active) setApprovalLoading(false) })
    return () => { active = false }
  }, [canReviewItem, item.id, item.status, onError])
  useEffect(() => { onDirtyChange(dirty) }, [dirty, onDirtyChange])
  const run = async (action: () => Promise<void>, successMessage: string, after?: () => void) => { setBusy(true); onError(null); try { await action(); await onChanged(); after?.(); notify(successMessage) } catch (caught) { const message = caught instanceof Error ? caught.message : 'Không thực hiện được thao tác.'; onError(message); notify(message, 'error') } finally { setBusy(false) } }
  const requestClose = async () => { if (dirty && !await confirm({ title: 'Bỏ thay đổi chưa lưu?', message: isNew ? 'Hạng mục/công việc mới chưa được lưu. Đóng panel sẽ bỏ bản nháp này.' : 'Panel đang có thay đổi chưa lưu. Đóng panel sẽ bỏ các thay đổi.', confirmLabel: 'Đóng và bỏ', tone: 'danger' })) return; onClose() }
  const switchTab = async (next: DrawerTab) => { if (!canViewDetails && next !== 'info') return; if (next === tab) return; if (dirty && !await confirm({ title: 'Chuyển tab?', message: 'Các thay đổi chưa lưu trong tab Thông tin sẽ bị bỏ.', confirmLabel: 'Chuyển tab', tone: 'danger' })) return; onTabChange(next) }
  const changeDepartments = (leadDepartmentId: string, coordinatingDepartmentIds: string[]) => setForm((current) => ({
    ...current,
    leadDepartmentId,
    coordinatingDepartmentIds,
    participantIds: retainEligibleParticipantIds(current.participantIds, users, leadDepartmentId, coordinatingDepartmentIds),
  }))
  const submit = async (event: FormEvent) => {
    event.preventDefault()
    if (!canEditInfo) return
    if (!form.name.trim()) { const message = 'Tên hạng mục/công việc không được để trống.'; onError(message); notify(message, 'error'); return }
    if (form.startDate && form.endDate && form.endDate < form.startDate) { const message = 'Ngày kết thúc phải từ ngày bắt đầu trở đi.'; onError(message); notify(message, 'error'); return }
    setBusy(true); onError(null)
    try {
      if (isNew) {
        const id = await createWorkItem({ projectId: item.project_id, parentId: item.parent_id, wbs: item.wbs, ...form })
        await onCreated(id)
        notify(`Đã tạo ${isGroup ? 'hạng mục' : 'công việc'} mới.`)
      } else {
        await saveWorkItem(item, form)
        await onChanged()
        onClose()
        notify(`Đã lưu thay đổi ${isGroup ? 'hạng mục' : 'công việc'}.`)
      }
    } catch (caught) { const message = caught instanceof Error ? caught.message : 'Không lưu được hạng mục/công việc.'; onError(message); notify(message, 'error') } finally { setBusy(false) }
  }
  const saveParticipants = async () => {
    await run(() => saveWorkItemParticipants(item, form.participantIds), 'Đã lưu phân công người tham gia.', onClose)
  }
  const addChild = async () => { if (dirty && !await confirm({ title: 'Thêm công việc con?', message: 'Các thay đổi chưa lưu trên panel hiện tại sẽ bị bỏ trước khi mở công việc con mới.', confirmLabel: 'Tiếp tục', tone: 'danger' })) return; onAddChild(item) }
  const deleteCurrent = async () => { if (await confirm({ title: `Xóa ${isGroup ? 'hạng mục' : 'công việc'}?`, message: `${item.name}${hasChildren ? ' và toàn bộ công việc con bên trong' : ''} sẽ bị xóa. Không thể xóa nếu bên trong có bằng chứng đã nộp.`, confirmLabel: 'Xóa', tone: 'danger' })) await run(() => removeWorkItem(item.id), `Đã xóa ${isGroup ? 'hạng mục' : 'công việc'}.`, onClose) }
  const deleteEvidence = async () => { if (!canManageEvidence) { const message = 'Bằng chứng đã nộp được khóa và không thể xóa.'; onError(message); notify(message, 'error'); return } if (item.attachment && await confirm({ title: 'Xóa tệp bằng chứng?', message: `${item.attachment.file_name} sẽ bị xóa khỏi công việc. Thao tác này không thể hoàn tác.`, confirmLabel: 'Xóa tệp', tone: 'danger' })) await run(() => removeEvidence(item.attachment!), 'Đã xóa tệp bằng chứng.') }
  const decide = async (decision: 'approved' | 'rejected') => {
    if (!pendingRequest) return
    if (pendingRequest.submitted_by === profile.id) { const message = 'Người gửi không được tự duyệt yêu cầu của mình.'; onError(message); notify(message, 'error'); return }
    if (decision === 'rejected' && !reviewNote.trim()) { const message = 'Từ chối phải nhập lý do.'; onError(message); notify(message, 'error'); return }
    await run(() => reviewRequest(pendingRequest.id, decision, reviewNote), decision === 'approved' ? 'Đã duyệt hoàn thành công việc.' : 'Đã từ chối yêu cầu hoàn thành.', () => onTabChange('evidence'))
  }
  return <><aside className="drawer on" aria-label={isNew ? `Thêm ${isGroup ? 'hạng mục' : 'công việc'}` : 'Chi tiết công việc'}><div id="dwrap"><div className="dhead"><div style={{ flex: 1 }}><div className="eyebrow">{isGroup ? 'Hạng mục' : 'Công việc'} · {item.wbs}</div><h2>{isNew ? `Thêm ${isGroup ? 'hạng mục' : 'công việc'} mới` : item.name}</h2>{isNew ? <span className="tiny unsaved">Chưa lưu — chỉ nút Lưu mới ghi vào tiến độ</span> : <span className={`pill ${classes[displayedStatus]}`}><i />{displayedStatus === 'late' ? 'Quá hạn' : labels[displayedStatus]}</span>}</div><button className="btn" aria-label="Đóng panel" onClick={() => void requestClose()}>✕</button></div><div className="dtabs"><button className={tab === 'info' ? 'on' : ''} onClick={() => void switchTab('info')}>Thông tin</button>{canViewDetails && !isNew && (!isGroup || item.attachment) && <button className={tab === 'evidence' ? 'on' : ''} onClick={() => void switchTab('evidence')}>Bằng chứng <span className="cnt">{item.attachment ? 1 : 0}</span></button>}{canViewDetails && !isNew && <button className={tab === 'log' ? 'on' : ''} onClick={() => void switchTab('log')}>Diễn biến <span className="cnt">{updates.length}</span></button>}{canViewDetails && !isNew && canReviewItem && item.status === 'pending_approval' && <button className={`approval-tab ${tab === 'approval' ? 'on' : ''}`} onClick={() => void switchTab('approval')}>Xét duyệt <span className="cnt">1</span></button>}</div><div className="dbody">
    {tab === 'info' && !canViewDetails && <div className="note"><b>Chỉ xem tiến độ tổng quan.</b><br />Bằng chứng và diễn biến chỉ hiển thị khi phòng/ban của bạn là đơn vị chủ trì hoặc phối hợp công việc này.</div>}
    {tab === 'info' && <><form className="sec" onSubmit={(event) => void submit(event)}><h3>Thông tin {isGroup ? 'hạng mục' : 'công việc'}</h3><div className="fg"><label className="f wide"><span>{isGroup ? 'Tên hạng mục' : 'Tên công việc'}</span><textarea autoFocus={isNew} disabled={!canEditInfo} value={form.name} onChange={(event) => setForm({ ...form, name: event.target.value })} /></label><label className="f wide"><span>Đơn vị chủ trì</span><select disabled={!canEditInfo} value={form.leadDepartmentId} onChange={(event) => { const leadDepartmentId = event.target.value; changeDepartments(leadDepartmentId, form.coordinatingDepartmentIds.filter((id) => id !== leadDepartmentId)) }}><option value="">Chưa chọn đơn vị chủ trì</option>{departments.map((department) => <option key={department.id} value={department.id}>{department.code} — {department.name}</option>)}</select></label><DepartmentMultiSelect departments={departments} disabled={!canEditInfo} leadDepartmentId={form.leadDepartmentId} selectedIds={form.coordinatingDepartmentIds} onChange={(coordinatingDepartmentIds) => changeDepartments(form.leadDepartmentId, coordinatingDepartmentIds)} />{!isGroup && <><label className="f"><span>Bắt đầu</span><input disabled={!canEditInfo} type="date" value={form.startDate} onChange={(event) => setForm({ ...form, startDate: event.target.value })} /></label><label className="f"><span>Kết thúc</span><input disabled={!canEditInfo} type="date" value={form.endDate} onChange={(event) => setForm({ ...form, endDate: event.target.value })} /></label></>}{!isGroup && canEditInfo && <label className="f wide"><span>Trạng thái</span><select disabled={!canEditInfo} value={form.status} onChange={(event) => setForm({ ...form, status: event.target.value as WorkItemStatus })}><option value="not_started">Chưa thực hiện</option><option value="in_progress">Đang thực hiện</option><option value="pending_approval" disabled>Chờ duyệt</option><option value="completed" disabled>Hoàn thành qua duyệt</option></select></label>}{!isGroup && (canEditInfo || canManageParticipants) && <ParticipantMultiSelect users={canEditInfo ? participantUsers : participantUsersForManager} disabled={!canEditInfo && !canManageParticipants} selectedIds={form.participantIds} onChange={(participantIds) => setForm({ ...form, participantIds })} placeholder={form.leadDepartmentId || form.coordinatingDepartmentIds.length ? 'Chọn người thuộc các đơn vị liên quan' : 'Chọn đơn vị chủ trì/phối hợp trước'} />}</div>{participantScope === 'own_department' && <div className="note" style={{ marginTop: 10 }}>Bạn chỉ thay đổi người tham gia thuộc phòng/ban của mình. Phân công của các đơn vị khác được giữ nguyên.</div>}{isGroup && <div className="note" style={{ marginTop: 10 }}>Ngày và trạng thái của hạng mục tự tính từ các công việc con.</div>}{canEditInfo ? <div className="row2" style={{ marginTop: 10 }}><button className="btn pri" disabled={busy || !form.name.trim()}>{busy ? 'Đang lưu…' : isNew ? `Lưu ${isGroup ? 'hạng mục' : 'công việc'}` : 'Lưu thay đổi'}</button>{dirty && !isNew && <span className="tiny unsaved">Có thay đổi chưa lưu</span>}</div> : canManageParticipants && <div className="row2" style={{ marginTop: 10 }}><button type="button" className="btn pri" disabled={busy || !dirty} onClick={() => void saveParticipants()}>{busy ? 'Đang lưu…' : 'Lưu phân công'}</button>{dirty && <span className="tiny unsaved">Có thay đổi phân công chưa lưu</span>}</div>}</form>{(isNew || canAddChild || canManageStructure) && <div className="sec"><h3>Thao tác</h3>{isNew ? <><button className="btn dgr" onClick={() => void requestClose()}>Hủy bỏ, không thêm nữa</button><div className="tiny muted" style={{ marginTop: 8 }}>Bản nháp này chưa được ghi vào database.</div></> : <div className="row2">{canAddChild && <button className="btn" onClick={() => void addChild()}>+ Công việc con</button>}{canManageStructure && <button className="btn dgr" onClick={() => void deleteCurrent()}>Xóa</button>}</div>}</div>}</>}
    {tab === 'evidence' && (!isGroup || item.attachment) && <><div className="sec"><h3>Tài liệu bằng chứng ({item.attachment ? 1 : 0})</h3>{isEvidenceLocked && <div className="note">Bằng chứng đã nộp được khóa để phục vụ xét duyệt và truy vết. Bạn vẫn có thể mở xem nhưng không thể thay hoặc xóa tệp.</div>}{item.attachment ? <div className="evi"><span className="ic">FILE</span><button className="t" onClick={() => void viewEvidence(item.attachment!)}>{item.attachment.file_name}</button><button disabled={!canManageEvidence} title={isEvidenceLocked ? 'Bằng chứng đã được khóa' : undefined} aria-label="Xóa tệp bằng chứng" onClick={() => void deleteEvidence()}>✕</button></div> : canManageEvidence && !isGroup ? <label className="drop">Bấm để chọn tệp bằng chứng<input hidden type="file" onChange={(event) => { const file = event.target.files?.[0]; if (file) void run(() => uploadEvidence(item.id, file, profile.id), 'Đã tải lên tệp bằng chứng.') }} /></label> : <div className="tiny muted">Chưa có bằng chứng.</div>}</div>{canManageEvidence && !isGroup && <div className="sec"><h3>Gửi hoàn thành</h3><div className="f"><label><span>{completesDirectly ? 'Ghi chú hoàn thành' : 'Ghi chú gửi duyệt'}</span><textarea value={note} onChange={(event) => setNote(event.target.value)} /></label></div><div className="row2" style={{ marginTop: 9 }}><button className="btn ok" disabled={busy || !item.attachment} onClick={() => void run(() => requestCompletion(item.id, note), completesDirectly ? 'Đã nộp bằng chứng và hoàn thành công việc.' : 'Đã gửi công việc cho quản trị viên duyệt.')}>{completesDirectly ? 'Nộp bằng chứng và hoàn thành' : 'Gửi quản trị viên duyệt'}</button>{!item.attachment && <span className="tiny muted">Cần đúng 1 tài liệu bằng chứng</span>}</div></div>}</>}
    {tab === 'log' && <div className="sec"><h3>Diễn biến công việc ({updates.length})</h3>{updates.length ? <div className="log">{updates.map((update) => <div className="li" key={update.id}><div className="dot" /><div><div className="m">{dateTime(update.created_at)} · {update.author?.full_name || update.author?.username}</div><p>{update.content}</p></div></div>)}</div> : <div className="tiny muted">Chưa có diễn biến nào.</div>}{canLogProgress ? <><div className="f" style={{ marginTop: 10 }}><label><span>Ghi diễn biến mới</span><textarea value={note} onChange={(event) => setNote(event.target.value)} placeholder="Hiện trường hôm nay thế nào? Vướng gì?" /></label></div><button className="btn pri" disabled={!note.trim() || busy} style={{ marginTop: 8 }} onClick={() => void run(async () => { await addProgress(item.id, note, profile.id); await markWorkItemActivitySeen(item.id, profile.id); setNote(''); setUpdates(await getProgressUpdates(item.id)) }, 'Đã ghi diễn biến mới.')}>Ghi diễn biến</button></> : <div className="note" style={{ marginTop: 10 }}>{progressLockReason}</div>}</div>}
    {tab === 'approval' && canReviewItem && item.status === 'pending_approval' && <div className="sec approval-panel"><h3>Xét duyệt hoàn thành</h3>{approvalLoading ? <div className="tiny muted">Đang tải yêu cầu chờ duyệt…</div> : pendingRequest ? <><div className="approval-request"><span>Người gửi</span><b>{pendingRequest.submitter?.full_name || pendingRequest.submitter?.username || '—'}</b><span>Thời gian gửi</span><b>{dateTime(pendingRequest.submitted_at)}</b><span>Lần gửi</span><b>{pendingRequest.attempt_no}</b><span>Ghi chú</span><p>{pendingRequest.note || 'Không có ghi chú'}</p></div>{item.attachment && <div className="approval-evidence"><span className="tiny muted">Bằng chứng kèm theo</span><button className="btn" onClick={() => void viewEvidence(item.attachment!)}>Xem {item.attachment.file_name}</button></div>}<label className="f"><span>Nhận xét / lý do từ chối</span><textarea value={reviewNote} onChange={(event) => setReviewNote(event.target.value)} placeholder="Bắt buộc nhập khi từ chối" /></label><div className="approval-panel-actions"><button className="btn dgr" disabled={busy} onClick={() => void decide('rejected')}>{busy ? 'Đang xử lý…' : 'Từ chối'}</button><button className="btn ok" disabled={busy} onClick={() => void decide('approved')}>{busy ? 'Đang xử lý…' : 'Duyệt hoàn thành'}</button></div><div className="tiny muted">Chỉ cần một quản trị viên hợp lệ xử lý; hệ thống không duyệt hai cấp.</div></> : <div className="note warn">Yêu cầu có thể vừa được quản trị viên khác xử lý. Hãy tải lại dữ liệu.</div>}</div>}
  </div></div></aside><div className="scrim on" onClick={() => void requestClose()} /></>
}

function TimelineHeader({ start, end, width, pixelsPerDay, zoom, milestones }: { start: string; end: string; width: number; pixelsPerDay: number; zoom: 'day' | 'week' | 'month'; milestones: Milestone[] }) {
  const months: { label: string; left: number; width: number }[] = []
  let cursor = new Date(`${start}T00:00:00`); const last = new Date(`${end}T00:00:00`)
  while (cursor <= last) { const monthStart = new Date(cursor.getFullYear(), cursor.getMonth(), 1); const monthEnd = new Date(cursor.getFullYear(), cursor.getMonth() + 1, 0); const visibleStart = monthStart < new Date(`${start}T00:00:00`) ? new Date(`${start}T00:00:00`) : monthStart; const visibleEnd = monthEnd > last ? last : monthEnd; months.push({ label: `Tháng ${cursor.getMonth() + 1}/${cursor.getFullYear()}`, left: dayDiff(start, iso(visibleStart)) * pixelsPerDay, width: (dayDiff(iso(visibleStart), iso(visibleEnd)) + 1) * pixelsPerDay }); cursor = new Date(cursor.getFullYear(), cursor.getMonth() + 1, 1) }
  const steps = zoom === 'day' ? 1 : 7
  return <div className="time" style={{ width }}>{months.map((month) => <div className="mo" key={month.label} style={{ left: month.left, width: month.width }}>{month.label}</div>)}{zoom !== 'month' && Array.from({ length: Math.ceil((dayDiff(start, end) + 1) / steps) }, (_, index) => { const value = new Date(new Date(`${start}T00:00:00`).getTime() + index * steps * 86_400_000); return <div className="dy" key={index} style={{ left: index * steps * pixelsPerDay, width: steps * pixelsPerDay }}>{zoom === 'day' ? value.getDate() : `${value.getDate()}/${value.getMonth() + 1}`}</div> })}{milestones.filter((item) => item.due_date >= start && item.due_date <= end).map((item) => { const state = item.achieved ? 'Đã đạt' : item.due_date < today() ? 'Quá hạn chưa đạt' : 'Chưa đến hạn'; return <div key={item.id} className={`mk ${item.achieved ? 'ok' : item.due_date < today() ? 'bad' : ''}`} style={{ left: dayDiff(start, item.due_date) * pixelsPerDay }} tabIndex={0} aria-label={`Mốc ${item.name}, hạn ${date(item.due_date)}, ${state}`}><i className="mk-diamond" /><div className="mk-tooltip" role="tooltip"><b>{item.name}</b><span><strong>Ngày phải đạt:</strong> {date(item.due_date)}</span><span><strong>Đơn vị chủ trì:</strong> {item.owner_text || 'Chưa xác định'}</span>{item.condition_text && <span><strong>Điều kiện:</strong> {item.condition_text}</span>}<em className={item.achieved ? 'done' : item.due_date < today() ? 'late' : ''}>{state}</em></div></div> })}<TodayLine start={start} pixelsPerDay={pixelsPerDay} label /></div>
}
function TodayLine({ start, pixelsPerDay, label = false }: { start: string; pixelsPerDay: number; label?: boolean }) { const left = dayDiff(start, today()) * pixelsPerDay; return <>{left >= 0 && <div className="now" style={{ left }} />}{label && left >= 0 && <div className="nowlab" style={{ left }}>{new Date().getDate()}/{new Date().getMonth() + 1}</div>}</> }
function StatusFilter({ active, count, label, onClick }: { value: string; active: boolean; count: number; label: string; onClick: () => void }) { return <button className={`fchip ${active ? 'on' : ''}`} onClick={onClick}>{label} {count}</button> }
function groupByParent(items: WorkItem[]) { const result = new Map<string, WorkItem[]>(); items.forEach((item) => { if (!item.parent_id) return; result.set(item.parent_id, [...(result.get(item.parent_id) ?? []), item]) }); return result }
function makeDraft(projectId: string, parent: WorkItem | null, items: WorkItem[]): WorkItem {
  const siblings = items.filter((item) => item.parent_id === (parent?.id ?? null))
  const next = siblings.length + 1
  const timestamp = new Date().toISOString()
  return {
    id: `draft-${crypto.randomUUID()}`,
    project_id: projectId,
    parent_id: parent?.id ?? null,
    wbs: parent ? `${parent.wbs}.${next}` : roman(next),
    name: parent ? 'Công việc mới' : 'HẠNG MỤC MỚI',
    source_responsibility_text: parent?.source_responsibility_text ?? null,
    lead_department_id: parent?.lead_department_id ?? null,
    lead_department: parent?.lead_department ?? null,
    coordinating_department_ids: [],
    coordinating_departments: [],
    start_date: parent ? today() : null,
    end_date: parent ? today() : null,
    status: 'not_started',
    sort_order: items.reduce((max, item) => Math.max(max, item.sort_order), -1) + 1,
    version: 1,
    created_at: timestamp,
    updated_at: timestamp,
    participant_ids: [],
    attachment: null,
    has_unseen_activity: false,
  }
}
function flatten(items: WorkItem[], children: Map<string, WorkItem[]>, collapsed: Set<string>) { const result: WorkItem[] = []; const visit = (item: WorkItem) => { result.push(item); if (!collapsed.has(item.id)) (children.get(item.id) ?? []).forEach(visit) }; items.filter((item) => !item.parent_id).forEach(visit); return result }
function descendants(id: string, items: WorkItem[]): WorkItem[] { const direct = items.filter((item) => item.parent_id === id); return direct.flatMap((item) => [item, ...descendants(item.id, items)]) }
function leadDepartmentPath(item: WorkItem, items: WorkItem[]) {
  const result: Array<string | null> = []
  let current: WorkItem | undefined = item
  while (current) {
    result.push(current.lead_department_id)
    current = current.parent_id ? items.find((candidate) => candidate.id === current?.parent_id) : undefined
  }
  return result
}
function spanOf(item: WorkItem, items: WorkItem[]) { const nodes = descendants(item.id, items); return { start: minDate(nodes.map((node) => node.start_date)), end: maxDate(nodes.map((node) => node.end_date)) } }
function depth(item: WorkItem, items: WorkItem[]) { let result = 0; let parent = item.parent_id; while (parent) { result += 1; parent = items.find((candidate) => candidate.id === parent)?.parent_id ?? null } return result }
function liveStatus(item: WorkItem): WorkItemStatus | 'late' { return item.status !== 'completed' && item.status !== 'pending_approval' && item.end_date && item.end_date < today() ? 'late' : item.status }
function aggregateStatus(item: WorkItem, items: WorkItem[], children: Map<string, WorkItem[]>): WorkItemStatus | 'late' {
  const ownChildren = children.get(item.id) ?? []
  if (!ownChildren.length) return liveStatus(item)
  const leafStates = descendants(item.id, items).filter((node) => !(children.get(node.id)?.length)).map(liveStatus)
  if (leafStates.length && leafStates.every((state) => state === 'completed')) return 'completed'
  if (leafStates.includes('pending_approval')) return 'pending_approval'
  if (leafStates.includes('late')) return 'late'
  if (leafStates.some((state) => state === 'in_progress' || state === 'completed')) return 'in_progress'
  return 'not_started'
}
function responsibilityLabel(item: WorkItem) {
  const lead = item.lead_department ? `Chủ trì: ${item.lead_department.code}` : 'Chưa chọn đơn vị chủ trì'
  const coordinating = item.coordinating_departments.length ? `Phối hợp: ${item.coordinating_departments.map((department) => department.code).join(', ')}` : 'Không có đơn vị phối hợp'
  return `${lead} · ${coordinating}`
}
function countStatuses(items: WorkItem[]) { const result = { not_started: 0, in_progress: 0, pending_approval: 0, completed: 0, late: 0 }; items.forEach((item) => { result[liveStatus(item)] += 1 }); return result }
function minDate(values: (string | null)[]) { return values.filter((value): value is string => Boolean(value)).sort()[0] ?? null }
function maxDate(values: (string | null)[]) { return values.filter((value): value is string => Boolean(value)).sort().at(-1) ?? null }
function dayDiff(start: string, end: string) { return Math.round((new Date(`${end}T00:00:00`).getTime() - new Date(`${start}T00:00:00`).getTime()) / 86_400_000) }
function statusColor(value: WorkItemStatus | 'late') { return ({ not_started: 'var(--st-todo)', in_progress: 'var(--st-doing)', pending_approval: 'var(--st-pending)', completed: 'var(--st-done)', late: 'var(--st-late)' })[value] }
function date(value: string | null) { return value ? new Intl.DateTimeFormat('vi-VN').format(new Date(`${value}T00:00:00`)) : '—' }
function dateTime(value: string) { return new Intl.DateTimeFormat('vi-VN', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(value)) }
function iso(value: Date) { return `${value.getFullYear()}-${String(value.getMonth() + 1).padStart(2, '0')}-${String(value.getDate()).padStart(2, '0')}` }
function today() { return new Date().toISOString().slice(0, 10) }
function roman(value: number) { const pairs: [number, string][] = [[1000,'M'],[900,'CM'],[500,'D'],[400,'CD'],[100,'C'],[90,'XC'],[50,'L'],[40,'XL'],[10,'X'],[9,'IX'],[5,'V'],[4,'IV'],[1,'I']]; let rest=value; let result=''; for(const [amount,symbol] of pairs){while(rest>=amount){result+=symbol;rest-=amount}} return result }
