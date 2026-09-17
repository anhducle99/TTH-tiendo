begin;

-- 1. Tạo bảng public.branches (Chi nhánh)
create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  code varchar(50) not null unique,
  name text not null,
  address text,
  is_headquarters boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.branches enable row level security;
grant select, insert, update, delete on public.branches to authenticated;

-- Khởi tạo chi nhánh mặc định cho dữ liệu hiện tại (HQ - Tổng công ty)
insert into public.branches (code, name, address, is_headquarters, active)
values ('HQ', 'Tổng công ty / Trụ sở chính (HQ)', 'Hệ thống Quản lý Tiến độ Tập đoàn TTH', true, true)
on conflict (code) do update set is_headquarters = true;

-- 2. Cập nhật bảng public.departments
-- Gán branch_id trỏ về chi nhánh HQ mặc định
alter table public.departments
  add column if not exists branch_id uuid references public.branches(id) on delete cascade;

update public.departments
set branch_id = (select id from public.branches where code = 'HQ')
where branch_id is null;

alter table public.departments
  alter column branch_id set not null;

-- Đổi ràng buộc UNIQUE từ code sang (branch_id, code) để các chi nhánh khác nhau có thể có cùng mã phòng ban
alter table public.departments drop constraint if exists departments_code_key;
alter table public.departments add constraint departments_branch_code_key unique (branch_id, code);

-- 3. Cập nhật bảng public.projects
alter table public.projects
  add column if not exists branch_id uuid references public.branches(id) on delete cascade;

update public.projects
set branch_id = (select id from public.branches where code = 'HQ')
where branch_id is null;

alter table public.projects
  alter column branch_id set not null;

create index if not exists projects_branch_idx on public.projects(branch_id);

-- 4. Cập nhật bảng public.profiles
alter table public.profiles
  add column if not exists branch_id uuid references public.branches(id) on delete set null,
  add column if not exists is_branch_admin boolean not null default false;

update public.profiles
set branch_id = (select id from public.branches where code = 'HQ')
where branch_id is null and role <> 'manager';

-- 5. Cập nhật các hàm bảo mật và phân quyền RLS

-- Kiểm tra người dùng có thuộc Chi nhánh Tổng công ty (HQ) hay không
create or replace function public.is_headquarters_user()
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select public.is_manager() or exists (
    select 1
    from public.profiles profile
    join public.branches branch on branch.id = profile.branch_id
    where profile.id = auth.uid()
      and profile.active
      and (profile.branch_id is null or branch.is_headquarters)
  );
$$;

-- Kiểm tra người dùng có phải Quản trị Chi nhánh của target_branch_id
-- (Quản trị Tổng công ty / HQ hoặc Quản trị của chính chi nhánh đó)
create or replace function public.is_branch_admin(target_branch_id uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select public.is_manager() or exists (
    select 1
    from public.profiles profile
    left join public.branches branch on branch.id = profile.branch_id
    where profile.id = auth.uid()
      and profile.active
      and (
        (branch.is_headquarters and profile.is_branch_admin)
        or (profile.branch_id = target_branch_id and profile.is_branch_admin)
      )
  );
$$;

-- Hàm kiểm tra quyền xem chi nhánh
create or replace function public.can_view_branch(target_branch_id uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select public.is_headquarters_user() or exists (
    select 1 from public.profiles
    where id = auth.uid()
      and active
      and branch_id = target_branch_id
  );
$$;

-- Cập nhật can_view_project:
-- - Cán bộ Tổng công ty (HQ) được quyền giám sát tất cả dự án của mọi chi nhánh
-- - Nhân sự chi nhánh thành viên chỉ xem dự án nội bộ của chi nhánh mình
create or replace function public.can_view_project(target_project_id uuid)
returns boolean
language plpgsql
stable
security definer set search_path = public
as $$
declare
  target_branch_id uuid;
  user_branch_id uuid;
  user_is_branch_admin boolean := false;
  user_is_dept_admin boolean := false;
  user_is_hq boolean := false;
begin
  if not public.is_active_user() then return false; end if;
  if public.is_manager() then return true; end if;

  select branch_id into target_branch_id
  from public.projects
  where id = target_project_id;

  select profile.branch_id, profile.is_branch_admin, profile.is_department_admin, coalesce(branch.is_headquarters, false)
  into user_branch_id, user_is_branch_admin, user_is_dept_admin, user_is_hq
  from public.profiles profile
  left join public.branches branch on branch.id = profile.branch_id
  where profile.id = auth.uid() and profile.active;

  -- Nếu thuộc Chi nhánh Tổng công ty (HQ): được quyền giám sát / theo dõi toàn bộ các dự án ở các chi nhánh
  if user_is_hq or user_branch_id is null then
    return true;
  end if;

  -- Nếu là nhân sự chi nhánh thành viên nhưng khác chi nhánh của dự án thì chặn
  if user_branch_id is not null and target_branch_id is not null and user_branch_id <> target_branch_id then
    return false;
  end if;

  -- Nếu là Quản trị Chi nhánh của chi nhánh này
  if user_is_branch_admin and user_branch_id = target_branch_id then
    return true;
  end if;

  -- Nếu là Quản trị dự án
  if public.is_project_admin(target_project_id) then return true; end if;

  -- Nếu là Quản trị phòng ban
  if user_is_dept_admin then return true; end if;

  -- Nhân viên: xem nếu có công việc liên quan trong phạm vi
  return exists (
    select 1
    from public.work_items item
    where item.project_id = target_project_id
      and public.can_view_work_item_detail(item.id)
  );
end;
$$;

-- RLS policies cho bảng branches
drop policy if exists branches_read on public.branches;
create policy branches_read on public.branches
for select to authenticated
using (public.can_view_branch(id));

drop policy if exists branches_manage on public.branches;
create policy branches_manage on public.branches
for all to authenticated
using (public.is_manager())
with check (public.is_manager());

-- RLS policies cho bảng departments
drop policy if exists departments_read on public.departments;
create policy departments_read on public.departments
for select to authenticated
using (public.can_view_branch(branch_id));

drop policy if exists departments_manage on public.departments;
create policy departments_manage on public.departments
for all to authenticated
using (public.is_branch_admin(branch_id))
with check (public.is_branch_admin(branch_id));

-- RLS policy quản lý projects
drop policy if exists projects_manage on public.projects;
create policy projects_manage on public.projects
for all to authenticated
using (public.is_branch_admin(branch_id) or public.can_manage_project(id))
with check (public.is_branch_admin(branch_id) or public.can_manage_project(id));

grant execute on function public.is_branch_admin(uuid), public.can_view_branch(uuid) to authenticated;

commit;
