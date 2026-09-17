import { createClient } from 'jsr:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

type AppRole = 'manager' | 'employee'

interface RequestBody {
  action?: 'create' | 'update_profile' | 'set_active' | 'reset_password'
  targetUserId?: string
  username?: string
  fullName?: string
  password?: string
  role?: AppRole
  active?: boolean
  branchId?: string | null
  isBranchAdmin?: boolean
  departmentId?: string | null
  isDepartmentAdmin?: boolean
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const authorization = request.headers.get('Authorization')

  if (!supabaseUrl || !anonKey || !serviceRoleKey || !authorization) {
    return json({ error: 'Unauthorized' }, 401)
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: callerData, error: callerError } = await callerClient.auth.getUser()
  if (callerError || !callerData.user) return json({ error: 'Unauthorized' }, 401)

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: callerProfile } = await adminClient
    .from('profiles')
      .select('role, active, branch_id, is_branch_admin')
    .eq('id', callerData.user.id)
    .maybeSingle()

  const isSuperAdmin = callerProfile?.role === 'manager'
  const isBranchAdmin = Boolean(callerProfile?.is_branch_admin && callerProfile?.branch_id)

  if ((!isSuperAdmin && !isBranchAdmin) || !callerProfile?.active) {
    return json({ error: 'Forbidden' }, 403)
  }

  let body: RequestBody
  try {
    body = await request.json()
  } catch {
    return json({ error: 'Dữ liệu không hợp lệ.' }, 400)
  }

  const action = body.action ?? 'create'
  const password = body.password ?? ''
  const role = body.role === 'manager' && isSuperAdmin ? 'manager' : 'employee'
  const fullName = body.fullName?.trim() ?? ''
  const branchId = isSuperAdmin ? (body.branchId || null) : callerProfile.branch_id
  const isTargetBranchAdmin = isSuperAdmin ? Boolean(body.isBranchAdmin) : false
  const departmentId = body.departmentId || null
  const isDepartmentAdmin = role === 'employee' && Boolean(body.isDepartmentAdmin)

  if (action === 'create') {
    const username = body.username?.trim().toLowerCase()
    if (!username || !/^[a-z0-9._-]{3,32}$/.test(username) || fullName.length < 2 || fullName.length > 100 || password.length < 8 || (role === 'employee' && !departmentId)) {
      return json({ error: 'Thiếu hoặc sai dữ liệu tài khoản.' }, 400)
    }

    const { data: created, error: createError } = await adminClient.auth.admin.createUser({
      email: `${username}@ptpk.local`,
      password,
      email_confirm: true,
      user_metadata: { username, full_name: fullName },
    })
    if (createError || !created.user) {
      return json({ error: createError?.message ?? 'Không tạo được tài khoản.' }, 400)
    }

    const { error: profileError } = await callerClient
      .from('profiles')
      .update({
        username,
        full_name: fullName,
        role,
        branch_id: branchId,
        is_branch_admin: isTargetBranchAdmin,
        department_id: departmentId,
        is_department_admin: isDepartmentAdmin,
        active: true
      })
      .eq('id', created.user.id)

    if (profileError) {
      await adminClient.auth.admin.deleteUser(created.user.id)
      return json({ error: 'Không gán được hồ sơ người dùng.' }, 500)
    }
    return json({ id: created.user.id, username, fullName, role }, 201)
  }

  if (!body.targetUserId) return json({ error: 'Thiếu tài khoản cần cập nhật.' }, 400)

  const { data: targetProfile, error: targetError } = await adminClient
    .from('profiles')
    .select('id, username, full_name, role, branch_id, is_branch_admin, department_id, is_department_admin, active')
    .eq('id', body.targetUserId)
    .maybeSingle()
  if (targetError || !targetProfile) return json({ error: 'Không tìm thấy tài khoản.' }, 404)

  if (targetProfile.username === 'admin') {
    return json({ error: 'Tài khoản admin gốc được bảo vệ và không thể chỉnh sửa.' }, 400)
  }

  if (!isSuperAdmin && targetProfile.branch_id !== callerProfile.branch_id) {
    return json({ error: 'Chỉ được quản lý tài khoản thuộc chi nhánh của mình.' }, 403)
  }

  if (action === 'update_profile') {
    if (fullName.length < 2 || fullName.length > 100) return json({ error: 'Họ và tên phải có từ 2 đến 100 ký tự.' }, 400)
    if (role === 'employee' && !departmentId) return json({ error: 'Nhân viên phải được gắn với một phòng/ban.' }, 400)
    if (targetProfile.id === callerData.user.id && role !== targetProfile.role) return json({ error: 'Không được tự thay đổi vai trò.' }, 400)

    const updatePayload: Record<string, unknown> = {
      full_name: fullName,
      role,
      department_id: departmentId,
      is_department_admin: isDepartmentAdmin
    }
    if (isSuperAdmin) {
      updatePayload.branch_id = branchId
      updatePayload.is_branch_admin = isTargetBranchAdmin
    }

    const { error } = await callerClient.from('profiles').update(updatePayload).eq('id', targetProfile.id)
    if (error) return json({ error: error.message }, 400)
    return json({ ok: true })
  }

  if (action === 'set_active') {
    if (typeof body.active !== 'boolean') return json({ error: 'Trạng thái tài khoản không hợp lệ.' }, 400)
    if (targetProfile.id === callerData.user.id) return json({ error: 'Không được tự thay đổi trạng thái tài khoản.' }, 400)

    const { error: authError } = await adminClient.auth.admin.updateUserById(targetProfile.id, {
      ban_duration: body.active ? 'none' : '876000h',
    })
    if (authError) return json({ error: authError.message }, 400)

    const { error: profileError } = await callerClient.from('profiles').update({ active: body.active }).eq('id', targetProfile.id)
    if (profileError) {
      await adminClient.auth.admin.updateUserById(targetProfile.id, { ban_duration: body.active ? '876000h' : 'none' })
      return json({ error: profileError.message }, 400)
    }
    return json({ ok: true })
  }

  if (action === 'reset_password') {
    if (password.length < 8) return json({ error: 'Mật khẩu mới phải có ít nhất 8 ký tự.' }, 400)
    const { error } = await adminClient.auth.admin.updateUserById(targetProfile.id, { password })
    if (error) return json({ error: error.message }, 400)
    await adminClient.from('audit_logs').insert({
      entity_type: 'profiles',
      entity_id: targetProfile.id,
      action: 'reset_password',
      actor_id: callerData.user.id,
    })
    return json({ ok: true })
  }

  return json({ error: 'Thao tác không được hỗ trợ.' }, 400)
})
