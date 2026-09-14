import { useEffect, useRef, useState } from 'react'
import type { PersonalNotification } from '../../types/domain'

function relativeTime(value: string) {
  const seconds = Math.max(0, Math.floor((Date.now() - new Date(value).getTime()) / 1000))
  if (seconds < 60) return 'Vừa xong'
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes} phút trước`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours} giờ trước`
  const days = Math.floor(hours / 24)
  return days < 7 ? `${days} ngày trước` : new Date(value).toLocaleDateString('vi-VN')
}

const kindLabel = { progress: 'Diễn biến mới', submitted: 'Gửi hoàn thành', approved: 'Đã duyệt', rejected: 'Đã từ chối' }

interface NotificationBellProps {
  items: PersonalNotification[]
  loading: boolean
  onOpen: (item: PersonalNotification) => Promise<boolean>
  onMarkAllSeen: () => Promise<void>
}

export function NotificationBell({ items, loading, onOpen, onMarkAllSeen }: NotificationBellProps) {
  const [open, setOpen] = useState(false)
  const rootRef = useRef<HTMLDivElement>(null)
  const unreadCount = items.filter((item) => item.isUnread).length

  useEffect(() => {
    if (!open) return
    const close = (event: MouseEvent) => { if (!rootRef.current?.contains(event.target as Node)) setOpen(false) }
    const escape = (event: KeyboardEvent) => { if (event.key === 'Escape') setOpen(false) }
    document.addEventListener('mousedown', close)
    document.addEventListener('keydown', escape)
    return () => { document.removeEventListener('mousedown', close); document.removeEventListener('keydown', escape) }
  }, [open])

  return <div className="notification-root" ref={rootRef}>
    <button className={`notification-bell ${open ? 'on' : ''}`} aria-label={`Thông báo${unreadCount ? `, ${unreadCount} chưa đọc` : ''}`} aria-expanded={open} onClick={() => setOpen((value) => !value)}>
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4" /></svg>
      {unreadCount > 0 && <span className="notification-count">{unreadCount > 99 ? '99+' : unreadCount}</span>}
    </button>
    {open && <section className="notification-panel" aria-label="Danh sách thông báo">
      <header><div><b>Thông báo</b><span>{unreadCount ? `${unreadCount} chưa đọc` : 'Đã xem hết'}</span></div>{unreadCount > 0 && <button disabled={loading} onClick={() => void onMarkAllSeen()}>Đánh dấu đã đọc</button>}</header>
      <div className="notification-list">
        {loading && !items.length ? <div className="notification-empty">Đang tải thông báo…</div> : items.length ? items.map((item) => <button className={`notification-item notification-${item.kind}${item.isUnread ? '' : ' seen'}`} key={item.id} onClick={() => void onOpen(item).then((opened) => { if (opened) setOpen(false) })}>
          {item.isUnread && <span className="notification-dot" />}
          <span className="notification-copy"><b>{kindLabel[item.kind]}</b><strong>{item.work_item_wbs}. {item.work_item_name}</strong><span>{item.actor_name}: {item.content}</span><small>{item.project_name} · {relativeTime(item.created_at)}</small></span>
        </button>) : <div className="notification-empty"><b>Không có thông báo</b><span>Các diễn biến và kết quả xét duyệt mới sẽ xuất hiện tại đây.</span></div>}
      </div>
    </section>}
  </div>
}
