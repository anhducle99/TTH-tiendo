import { supabase } from '../../lib/supabase'
import type { AppRole, Branch, Department, UserProfile } from '../../types/domain'

export interface CreateUserInput {
  username: string
  fullName: string
  password: string
  role: AppRole
  branchId: string | null
  isBranchAdmin: boolean
  departmentId: string | null
  isDepartmentAdmin: boolean
}

interface UserActionInput {
  action: 'create' | 'update_profile' | 'set_active' | 'reset_password'
  targetUserId: string
  fullName?: string
  password?: string
  role?: AppRole
  active?: boolean
  branchId?: string | null
  isBranchAdmin?: boolean
  departmentId?: string | null
  isDepartmentAdmin?: boolean
}

export async function listBranches(): Promise<Branch[]> {
  if (!supabase) return []
  const { data, error } = await supabase
    .from('branches')
    .select('id, code, name, address, is_headquarters, active')
    .eq('active', true)
    .order('name')
  if (error) throw error
  return (data ?? []) as Branch[]
}

export async function listUsers(): Promise<UserProfile[]> {
  if (!supabase) return []
  const { data, error } = await supabase
    .from('profiles')
    .select('id, username, full_name, role, branch_id, is_branch_admin, department_id, is_department_admin, active, branch:branches(id, code, name, active), department:departments(id, branch_id, code, name, active)')
    .order('full_name')

  if (error) throw error
  return (data ?? []).map((row) => ({
    ...row,
    branch: Array.isArray(row.branch) ? row.branch[0] ?? null : row.branch,
    department: Array.isArray(row.department) ? row.department[0] ?? null : row.department,
  })) as unknown as UserProfile[]
}

export async function listDepartments(branchId?: string): Promise<Department[]> {
  if (!supabase) return []
  let query = supabase.from('departments').select('id, branch_id, code, name, active').eq('active', true)
  if (branchId) query = query.eq('branch_id', branchId)
  const { data, error } = await query.order('sort_order')
  if (error) throw error
  return (data ?? []) as Department[]
}

export async function createUser(input: CreateUserInput): Promise<void> {
  if (!supabase) throw new Error('Chưa cấu hình kết nối Supabase.')

  const { error } = await supabase.functions.invoke('admin-create-user', {
    body: {
      action: 'create',
      username: input.username,
      fullName: input.fullName,
      password: input.password,
      role: input.role,
      branchId: input.branchId,
      isBranchAdmin: input.isBranchAdmin,
      departmentId: input.departmentId,
      isDepartmentAdmin: input.isDepartmentAdmin,
    },
  })

  if (error) throw error
}

async function invokeUserAction(input: UserActionInput): Promise<void> {
  if (!supabase) throw new Error('Chưa cấu hình kết nối Supabase.')
  const { error } = await supabase.functions.invoke('admin-create-user', { body: input })
  if (error) throw error
}

export async function updateUserProfile(
  userId: string,
  fullName: string,
  role: AppRole,
  branchId: string | null,
  isBranchAdmin: boolean,
  departmentId: string | null,
  isDepartmentAdmin: boolean
): Promise<void> {
  await invokeUserAction({
    action: 'update_profile',
    targetUserId: userId,
    fullName,
    role,
    branchId,
    isBranchAdmin,
    departmentId,
    isDepartmentAdmin,
  })
}

export async function setUserActive(userId: string, active: boolean): Promise<void> {
  await invokeUserAction({ action: 'set_active', targetUserId: userId, active })
}

export async function resetUserPassword(userId: string, password: string): Promise<void> {
  await invokeUserAction({ action: 'reset_password', targetUserId: userId, password })
}
