export type AppRole = 'manager' | 'employee'

export type ProjectStatus = 'draft' | 'active' | 'completed' | 'archived'

export type WorkItemStatus =
  | 'not_started'
  | 'in_progress'
  | 'pending_approval'
  | 'completed'

export interface Branch {
  id: string
  code: string
  name: string
  address?: string | null
  is_headquarters?: boolean
  active: boolean
}

export interface Profile {
  id: string
  username: string
  full_name: string
  role: AppRole
  branch_id: string | null
  branch?: Branch | null
  is_branch_admin: boolean
  department_id: string | null
  department: Department | null
  is_department_admin: boolean
  active: boolean
}

export interface Department {
  id: string
  branch_id: string
  code: string
  name: string
  active: boolean
}

export type UserProfile = Profile

export interface Project {
  id: string
  branch_id: string
  branch?: Branch | null
  code: string
  name: string
  site: string | null
  start_date: string | null
  end_date: string | null
  status: ProjectStatus
  deleted_at: string | null
  deleted_by: string | null
  created_at: string
  updated_at: string
  administrator_ids: string[]
  can_manage: boolean
}

export interface WorkItem {
  id: string
  project_id: string
  parent_id: string | null
  wbs: string
  name: string
  source_responsibility_text: string | null
  lead_department_id: string | null
  lead_department: Department | null
  coordinating_department_ids: string[]
  coordinating_departments: Department[]
  start_date: string | null
  end_date: string | null
  status: WorkItemStatus
  sort_order: number
  version: number
  created_at: string
  updated_at: string
  participant_ids: string[]
  attachment: Attachment | null
  has_unseen_activity: boolean
}

export interface Attachment {
  id: string
  work_item_id: string
  storage_path: string
  file_name: string
  mime_type: string | null
  size_bytes: number
  uploaded_by: string
  uploaded_at: string
}

export interface ProgressUpdate {
  id: string
  work_item_id: string
  content: string
  created_by: string
  created_at: string
  author?: Pick<Profile, 'username' | 'full_name'> | null
}

export interface Milestone {
  id: string
  project_id: string
  name: string
  due_date: string
  condition_text: string | null
  owner_text: string | null
  achieved: boolean
  achieved_at: string | null
  sort_order: number
}

export interface CompletionRequest {
  id: string
  work_item_id: string
  attempt_no: number
  note: string | null
  status: 'pending' | 'approved' | 'rejected'
  submitted_by: string
  submitted_at: string
  work_item?: Pick<WorkItem, 'id' | 'project_id' | 'wbs' | 'name'> | null
  submitter?: Pick<Profile, 'username' | 'full_name'> | null
  project?: Pick<Project, 'id' | 'code' | 'name'> | null
}

export interface ProjectActivity {
  id: string
  work_item_id: string
  work_item_wbs: string
  work_item_name: string
  content: string
  actor_name: string
  created_at: string
  kind: 'progress' | 'submitted' | 'approved' | 'rejected' | 'deleted'
}

export interface PersonalNotification extends Omit<ProjectActivity, 'kind'> {
  project_id: string
  project_code: string
  project_name: string
  kind: Exclude<ProjectActivity['kind'], 'deleted'>
  isUnread?: boolean
}
