-- ==========================================
-- Migration: 202609090001_initial_schema.sql
-- ==========================================
create extension if not exists pgcrypto;

create type public.app_role as enum ('manager', 'employee');
create type public.project_status as enum ('draft', 'active', 'completed', 'archived');
create type public.work_item_status as enum ('not_started', 'in_progress', 'pending_approval', 'completed');
create type public.completion_request_status as enum ('pending', 'approved', 'rejected');

create table public.departments (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table public.department_aliases (
  alias text primary key,
  department_id uuid not null references public.departments(id) on delete cascade
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role public.app_role not null default 'employee',
  department_id uuid references public.departments(id),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  site text,
  start_date date,
  end_date date,
  status public.project_status not null default 'draft',
  source_file_name text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint projects_date_order check (start_date is null or end_date is null or start_date <= end_date)
);

create table public.work_items (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  parent_id uuid references public.work_items(id) on delete cascade,
  wbs text not null,
  name text not null,
  source_responsibility_text text,
  start_date date,
  end_date date,
  status public.work_item_status not null default 'not_started',
  sort_order integer not null default 0,
  version integer not null default 1,
  created_by uuid not null references public.profiles(id),
  updated_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint work_items_date_order check (start_date is null or end_date is null or start_date <= end_date),
  constraint work_items_parent_not_self check (parent_id is null or parent_id <> id)
);

create index work_items_project_sort_idx on public.work_items(project_id, sort_order);
create index work_items_parent_idx on public.work_items(parent_id);

create table public.work_item_participants (
  work_item_id uuid not null references public.work_items(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  assigned_by uuid not null references public.profiles(id),
  assigned_at timestamptz not null default now(),
  primary key (work_item_id, user_id)
);

create index work_item_participants_user_idx on public.work_item_participants(user_id);

create table public.progress_updates (
  id uuid primary key default gen_random_uuid(),
  work_item_id uuid not null references public.work_items(id) on delete cascade,
  content text not null check (length(trim(content)) > 0),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.completion_requests (
  id uuid primary key default gen_random_uuid(),
  work_item_id uuid not null references public.work_items(id) on delete cascade,
  attempt_no integer not null,
  note text,
  status public.completion_request_status not null default 'pending',
  submitted_by uuid not null references public.profiles(id),
  submitted_at timestamptz not null default now(),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  review_note text,
  unique (work_item_id, attempt_no)
);

create unique index completion_requests_one_pending_idx
  on public.completion_requests(work_item_id)
  where status = 'pending';

create table public.milestones (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  name text not null,
  due_date date not null,
  condition_text text,
  achieved boolean not null default false,
  achieved_at date,
  sort_order integer not null default 0,
  created_by uuid not null references public.profiles(id),
  updated_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.attachments (
  id uuid primary key default gen_random_uuid(),
  work_item_id uuid not null references public.work_items(id) on delete cascade,
  completion_request_id uuid references public.completion_requests(id) on delete cascade,
  storage_path text not null unique,
  file_name text not null,
  mime_type text,
  size_bytes bigint not null check (size_bytes >= 0),
  uploaded_by uuid not null references public.profiles(id),
  uploaded_at timestamptz not null default now()
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  entity_type text not null,
  entity_id uuid not null,
  action text not null,
  actor_id uuid references public.profiles(id),
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);

create index audit_logs_entity_idx on public.audit_logs(entity_type, entity_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
create trigger projects_set_updated_at before update on public.projects
for each row execute function public.set_updated_at();
create trigger work_items_set_updated_at before update on public.work_items
for each row execute function public.set_updated_at();
create trigger milestones_set_updated_at before update on public.milestones
for each row execute function public.set_updated_at();

create or replace function public.set_record_actor()
returns trigger
language plpgsql
as $$
begin
  if to_jsonb(new) ? 'created_by' and tg_op = 'INSERT' then
    new := jsonb_populate_record(new, jsonb_build_object('created_by', auth.uid()));
  end if;
  if to_jsonb(new) ? 'updated_by' then
    new := jsonb_populate_record(new, jsonb_build_object('updated_by', auth.uid()));
  end if;
  if to_jsonb(new) ? 'assigned_by' and tg_op = 'INSERT' then
    new := jsonb_populate_record(new, jsonb_build_object('assigned_by', auth.uid()));
  end if;
  return new;
end;
$$;

create trigger projects_set_actor before insert on public.projects
for each row execute function public.set_record_actor();
create trigger work_items_set_actor before insert or update on public.work_items
for each row execute function public.set_record_actor();
create trigger milestones_set_actor before insert or update on public.milestones
for each row execute function public.set_record_actor();
create trigger participants_set_actor before insert on public.work_item_participants
for each row execute function public.set_record_actor();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), split_part(new.email, '@', 1)));
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.is_manager()
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'manager' and active
  );
$$;

create or replace function public.is_work_item_participant(target_work_item_id uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1 from public.work_item_participants
    where work_item_id = target_work_item_id and user_id = auth.uid()
  );
$$;

create or replace function public.submit_work_item_completion(target_work_item_id uuid, submission_note text default null)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  request_id uuid;
  next_attempt integer;
begin
  if not public.is_manager() and not public.is_work_item_participant(target_work_item_id) then
    raise exception 'Bạn không tham gia công việc này';
  end if;

  if exists (select 1 from public.completion_requests where work_item_id = target_work_item_id and status = 'pending') then
    raise exception 'Công việc đã có yêu cầu chờ duyệt';
  end if;

  select coalesce(max(attempt_no), 0) + 1 into next_attempt
  from public.completion_requests where work_item_id = target_work_item_id;

  insert into public.completion_requests (work_item_id, attempt_no, note, submitted_by)
  values (target_work_item_id, next_attempt, nullif(trim(submission_note), ''), auth.uid())
  returning id into request_id;

  update public.work_items
  set status = 'pending_approval', updated_by = auth.uid(), version = version + 1
  where id = target_work_item_id and status <> 'completed';

  if not found then raise exception 'Không thể gửi duyệt công việc đã hoàn thành'; end if;
  return request_id;
end;
$$;

create or replace function public.review_completion_request(
  target_request_id uuid,
  decision public.completion_request_status,
  manager_note text default null
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  target_work_item_id uuid;
begin
  if not public.is_manager() then raise exception 'Chỉ sếp được duyệt công việc'; end if;
  if decision not in ('approved', 'rejected') then raise exception 'Kết quả duyệt không hợp lệ'; end if;

  update public.completion_requests
  set status = decision, reviewed_by = auth.uid(), reviewed_at = now(), review_note = nullif(trim(manager_note), '')
  where id = target_request_id and status = 'pending'
  returning work_item_id into target_work_item_id;

  if target_work_item_id is null then raise exception 'Yêu cầu không còn ở trạng thái chờ duyệt'; end if;

  update public.work_items
  set status = case when decision = 'approved' then 'completed' else 'in_progress' end,
      updated_by = auth.uid(), version = version + 1
  where id = target_work_item_id;
end;
$$;

create or replace function public.audit_row_change()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  old_data jsonb;
  new_data jsonb;
  target_id uuid;
begin
  old_data := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end;
  new_data := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end;
  target_id := coalesce((new_data ->> 'id')::uuid, (old_data ->> 'id')::uuid);

  insert into public.audit_logs (entity_type, entity_id, action, actor_id, before_data, after_data)
  values (tg_table_name, target_id, lower(tg_op), auth.uid(), old_data, new_data);

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create trigger projects_audit after insert or update or delete on public.projects
for each row execute function public.audit_row_change();
create trigger work_items_audit after insert or update or delete on public.work_items
for each row execute function public.audit_row_change();
create trigger completion_requests_audit after insert or update or delete on public.completion_requests
for each row execute function public.audit_row_change();
create trigger milestones_audit after insert or update or delete on public.milestones
for each row execute function public.audit_row_change();

alter table public.departments enable row level security;
alter table public.department_aliases enable row level security;
alter table public.profiles enable row level security;
alter table public.projects enable row level security;
alter table public.work_items enable row level security;
alter table public.work_item_participants enable row level security;
alter table public.progress_updates enable row level security;
alter table public.completion_requests enable row level security;
alter table public.milestones enable row level security;
alter table public.attachments enable row level security;
alter table public.audit_logs enable row level security;

revoke all on all tables in schema public from anon, authenticated;
grant select on public.departments, public.profiles, public.projects, public.work_items,
  public.work_item_participants, public.progress_updates, public.completion_requests,
  public.milestones, public.attachments to authenticated;
grant select on public.department_aliases to authenticated;
grant insert on public.progress_updates, public.attachments to authenticated;
grant all on public.departments, public.department_aliases, public.profiles, public.projects,
  public.work_items, public.work_item_participants, public.milestones to authenticated;
grant select on public.audit_logs to authenticated;
grant execute on function public.submit_work_item_completion(uuid, text) to authenticated;
grant execute on function public.review_completion_request(uuid, public.completion_request_status, text) to authenticated;
revoke execute on function public.submit_work_item_completion(uuid, text) from public, anon;
revoke execute on function public.review_completion_request(uuid, public.completion_request_status, text) from public, anon;

create policy departments_read on public.departments for select to authenticated using (true);
create policy department_aliases_read on public.department_aliases for select to authenticated using (true);
create policy profiles_read on public.profiles for select to authenticated using (true);
create policy projects_read on public.projects for select to authenticated using (true);
create policy work_items_read on public.work_items for select to authenticated using (true);
create policy participants_read on public.work_item_participants for select to authenticated using (true);
create policy progress_updates_read on public.progress_updates for select to authenticated using (true);
create policy completion_requests_read on public.completion_requests for select to authenticated using (true);
create policy milestones_read on public.milestones for select to authenticated using (true);
create policy attachments_read on public.attachments for select to authenticated using (true);
create policy audit_logs_read_manager on public.audit_logs for select to authenticated using (public.is_manager());

create policy departments_manage_manager on public.departments for all to authenticated using (public.is_manager()) with check (public.is_manager());
create policy department_aliases_manage_manager on public.department_aliases for all to authenticated using (public.is_manager()) with check (public.is_manager());
create policy profiles_manage_manager on public.profiles for update to authenticated using (public.is_manager()) with check (public.is_manager());
create policy projects_manage_manager on public.projects for all to authenticated using (public.is_manager()) with check (public.is_manager());
create policy work_items_manage_manager on public.work_items for all to authenticated using (public.is_manager()) with check (public.is_manager());
create policy participants_manage_manager on public.work_item_participants for all to authenticated using (public.is_manager()) with check (public.is_manager());
create policy milestones_manage_manager on public.milestones for all to authenticated using (public.is_manager()) with check (public.is_manager());

create policy progress_updates_add_participant on public.progress_updates
for insert to authenticated
with check (
  created_by = auth.uid()
  and (public.is_manager() or public.is_work_item_participant(work_item_id))
  and exists (select 1 from public.work_items where id = work_item_id and status <> 'pending_approval' and status <> 'completed')
);

create policy attachments_add_participant on public.attachments
for insert to authenticated
with check (
  uploaded_by = auth.uid()
  and (public.is_manager() or public.is_work_item_participant(work_item_id))
);

insert into storage.buckets (id, name, public, file_size_limit)
values ('evidence', 'evidence', false, 52428800)
on conflict (id) do nothing;

create policy evidence_read_authenticated on storage.objects
for select to authenticated using (bucket_id = 'evidence');

create policy evidence_upload_participant on storage.objects
for insert to authenticated
with check (
  bucket_id = 'evidence'
  and (
    public.is_manager()
    or public.is_work_item_participant(((storage.foldername(name))[1])::uuid)
  )
);

insert into public.departments (code, name, sort_order) values
  ('CN-NVY', 'Công nghệ - Nghiệp vụ y', 1),
  ('CTXH', 'Công tác xã hội', 2),
  ('HCTH', 'Hành chính tổng hợp', 3),
  ('HCVHĐN', 'Hành chính Văn hóa Đối ngoại', 4),
  ('KSNB', 'Kiểm soát nội bộ', 5),
  ('MARKETING', 'Marketing', 6),
  ('PTNL1', 'PTNL1', 7),
  ('PTNL2', 'PTNL2', 8),
  ('CUNGUNG', 'Cung ứng', 9),
  ('PTDA', 'Phát triển dự án', 10),
  ('Z1', 'Z1', 11),
  ('TUYENDUNG', 'Tuyển dụng', 12),
  ('SOHOA', 'Số hóa', 13),
  ('TBTN', 'Thiết bị tòa nhà', 14),
  ('TBYT', 'Thiết bị y tế', 15),
  ('TCKT', 'Tài chính kế toán', 16),
  ('TCKH', 'Tài chính kế hoạch', 17),
  ('THIETKE', 'Thiết kế', 18),
  ('PTPK', 'Phát triển phòng khám', 19),
  ('BQLDA', 'Ban Quản lý dự án', 20),
  ('KT', 'Phòng Kỹ thuật', 21);

insert into public.department_aliases (alias, department_id)
select alias, d.id from (values
  ('NVY', 'CN-NVY'), ('P.NVY', 'CN-NVY'), ('PHÒNG NVY', 'CN-NVY'),
  ('MKT', 'MARKETING'), ('PHÒNG MKT', 'MARKETING'), ('PHÒNG MARKETING', 'MARKETING'),
  ('BQLDA', 'BQLDA'), ('BAN QLDA', 'BQLDA'), ('BAN QUẢN LÝ DỰ ÁN', 'BQLDA'),
  ('P.KỸ THUẬT', 'KT'), ('PHÒNG KỸ THUẬT', 'KT'), ('KỸ THUẬT', 'KT'),
  ('P.TBTN', 'TBTN'), ('PHÒNG TBTN', 'TBTN'),
  ('P.TBYT', 'TBYT'), ('PHÒNG TBYT', 'TBYT'), ('PHÒNG. TBYT', 'TBYT'),
  ('PHÒNG THIẾT KẾ', 'THIETKE'), ('PHÒNG HCTH', 'HCTH'),
  ('PHÒNG CUNG ỨNG', 'CUNGUNG'), ('PHÒNG SỐ HÓA', 'SOHOA'), ('PHÒNG PTPK', 'PTPK')
) as source(alias, code)
join public.departments d on d.code = source.code
on conflict (alias) do update set department_id = excluded.department_id;


-- ==========================================
-- Migration: 202609090002_username_auth.sql
-- ==========================================
alter table public.profiles add column if not exists username text;

update public.profiles p
set username = lower(split_part(u.email, '@', 1))
from auth.users u
where u.id = p.id and p.username is null;

alter table public.profiles alter column username set not null;
alter table public.profiles add constraint profiles_username_format
  check (username ~ '^[a-z0-9._-]{3,32}$');
create unique index profiles_username_lower_idx on public.profiles(lower(username));

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  requested_username text;
begin
  requested_username := lower(coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'username'), ''),
    split_part(new.email, '@', 1)
  ));

  insert into public.profiles (id, username, full_name)
  values (
    new.id,
    requested_username,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), requested_username)
  );
  return new;
end;
$$;



-- ==========================================
-- Setup Initial Root Admin User
-- ==========================================
do $$
declare
  admin_uid uuid := '00000000-0000-0000-0000-000000000001';
begin
  if not exists (select 1 from auth.users where id = admin_uid) then
    insert into auth.users (
      id,
      instance_id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at
    ) values (
      admin_uid,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'admin@ptpk.local',
      crypt('Admin@123456', gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}',
      '{"username":"admin","full_name":"Hệ Thống Quản Trị"}',
      now(),
      now()
    );
  end if;

  insert into public.profiles (id, username, full_name, role, active)
  values (admin_uid, 'admin', 'Hệ Thống Quản Trị', 'manager', true)
  on conflict (id) do update set
    username = 'admin',
    full_name = 'Hệ Thống Quản Trị',
    role = 'manager',
    active = true;
end;
$$;


-- ==========================================
-- Migration: 202609090003_seed_prototype_projects.sql
-- ==========================================
-- Sinh tự động từ prototype/index.html. Chỉ dùng để chuyển dữ liệu mẫu đã duyệt sang Supabase.
create or replace function public.set_record_actor()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is not null then
    if to_jsonb(new) ? 'created_by' and tg_op = 'INSERT' then
      new := jsonb_populate_record(new, jsonb_build_object('created_by', auth.uid()));
    end if;
    if to_jsonb(new) ? 'updated_by' then
      new := jsonb_populate_record(new, jsonb_build_object('updated_by', auth.uid()));
    end if;
    if to_jsonb(new) ? 'assigned_by' and tg_op = 'INSERT' then
      new := jsonb_populate_record(new, jsonb_build_object('assigned_by', auth.uid()));
    end if;
  end if;
  return new;
end;
$$;

do $$
declare
  actor_id uuid;
  khe_tre_id uuid;
begin
  select id into actor_id from public.profiles where username = 'admin' limit 1;
  if actor_id is null then raise exception 'Chưa có tài khoản admin để gán người tạo dữ liệu'; end if;

  insert into public.projects (code, name, site, start_date, end_date, status, source_file_name, created_by)
  values
    ('PK-KHETRE', 'Phòng khám Khe Tre', 'Khe Tre, Nam Đông', '2026-08-01', '2026-12-10', 'active', 'TIẾN ĐỘ KHE TRE 25.8.xlsx', actor_id),
    ('PK-QNGAI', 'Phòng khám Quảng Ngãi', 'Kho Lương thực, Quảng Ngãi', '2026-08-12', '2027-03-12', 'active', 'Biên bản 176.BBTTH', actor_id),
    ('PK-NVHOA', 'Phòng khám Nhà văn hoá', 'Bệnh viện Mắt Nguyên Phúc', null, '2027-02-12', 'active', 'Biên bản 176.BBTTH', actor_id),
    ('PK-SONTAY', 'Phòng khám Sơn Tây', 'Hà Tĩnh', '2026-08-12', null, 'active', 'Biên bản 176.BBTTH', actor_id),
    ('PK-CAOBANG', 'Phòng khám Cao Bằng', 'Cao Bằng', '2026-08-12', null, 'active', 'Biên bản 176.BBTTH', actor_id)
  on conflict (code) do update set
    name = excluded.name, site = excluded.site, start_date = excluded.start_date,
    end_date = excluded.end_date, source_file_name = excluded.source_file_name;

  select id into khe_tre_id from public.projects where code = 'PK-KHETRE';

  insert into public.work_items (project_id, parent_id, wbs, name, source_responsibility_text, sort_order, created_by, updated_by)
  select khe_tre_id, null, source.wbs, source.name, source.responsibility, source.sort_order, actor_id, actor_id
  from jsonb_to_recordset($groups$[{"wbs":"I","name":"CHUẨN BỊ – THIẾT KẾ","responsibility":null,"sort_order":0},{"wbs":"II","name":"LẬP DỰ TOÁN","responsibility":null,"sort_order":5},{"wbs":"III","name":"MỜI CHÀO & LỰA CHỌN NHÀ THẦU","responsibility":null,"sort_order":9},{"wbs":"IV","name":"PHẦN PHÁ DỠ NHÀ 4 TẦNG","responsibility":"P.Kỹ thuật","sort_order":15},{"wbs":"V","name":"PHẦN CẢI TẠO NHÀ 4 TẦNG","responsibility":"P.Kỹ thuật","sort_order":21},{"wbs":"VI","name":"PHẦN CẢI TẠO NHÀ 1 TẦNG","responsibility":"P.Kỹ thuật","sort_order":31},{"wbs":"VII","name":"PHẦN HÀNG RÀO VÀ CỔNG","responsibility":"P.Kỹ thuật","sort_order":35},{"wbs":"VIII","name":"HỆ THỐNG ĐIỆN","responsibility":"P.Kỹ thuật","sort_order":38},{"wbs":"IX","name":"HỆ THỐNG NƯỚC","responsibility":"P.Kỹ thuật","sort_order":47},{"wbs":"X","name":"HỆ THỐNG ĐIỆN NHẸ","responsibility":"P.TBTN","sort_order":55},{"wbs":"XI","name":"HỆ THỐNG KHÍ Y TẾ","responsibility":"P.TBTN","sort_order":63},{"wbs":"XII","name":"HỆ THỐNG PCCC","responsibility":"P.TBTN","sort_order":71},{"wbs":"XIII","name":"HỆ THỐNG ĐIỀU HÒA THÔNG GIÓ","responsibility":"P.Kỹ thuật","sort_order":80},{"wbs":"XIV","name":"HỆ THỐNG RO","responsibility":"P.TBTN","sort_order":89},{"wbs":"XV","name":"THI CÔNG TRẠM BIẾN ÁP 300 kVA","responsibility":"P.Kỹ thuật","sort_order":94},{"wbs":"XVI","name":"THI CÔNG KẾT CẤU BỂ XLNT","responsibility":"P.Kỹ thuật","sort_order":100},{"wbs":"XVII","name":"HỆ THỐNG XLNT CÔNG SUẤT 15 m³/NGÀY ĐÊM","responsibility":"P.TBTN","sort_order":107},{"wbs":"XVIII","name":"CHẠY THỬ ĐỒNG BỘ, HOÀN CÔNG, BÀN GIAO","responsibility":"P.Kỹ thuật","sort_order":116},{"wbs":"XIX","name":"TUYỂN DỤNG","responsibility":null,"sort_order":123},{"wbs":"XX","name":"MÁY MÓC, THIẾT BỊ Y TẾ","responsibility":null,"sort_order":128},{"wbs":"XXI","name":"DƯỢC & VẬT TƯ Y TẾ","responsibility":null,"sort_order":133},{"wbs":"XXII","name":"TRUYỀN THÔNG, MARKETING","responsibility":null,"sort_order":138},{"wbs":"XXIII","name":"WEBSITE, HỆ THỐNG MAIL, HIS","responsibility":null,"sort_order":143},{"wbs":"XXIV","name":"THỦ TỤC SAU 10/12/2026","responsibility":null,"sort_order":148},{"wbs":"XXV","name":"KÝ HỢP ĐỒNG KCB BHYT","responsibility":null,"sort_order":152}]$groups$::jsonb)
    as source(wbs text, name text, responsibility text, sort_order integer)
  where not exists (select 1 from public.work_items existing where existing.project_id = khe_tre_id and existing.wbs = source.wbs);

  insert into public.work_items (project_id, parent_id, wbs, name, source_responsibility_text, start_date, end_date, status, sort_order, created_by, updated_by)
  select khe_tre_id, parent.id, source.wbs, source.name, source.responsibility,
    source.start_date::date, source.end_date::date, source.status::public.work_item_status,
    source.sort_order, actor_id, actor_id
  from jsonb_to_recordset($tasks$[{"parent_wbs":"I","wbs":"I.1","name":"Rà soát hiện trạng, yêu cầu sử dụng và phạm vi cải tạo","responsibility":"Phòng Thiết kế","start_date":"2026-08-01","end_date":"2026-08-02","status":"completed","sort_order":1},{"parent_wbs":"I","wbs":"I.2","name":"Triển khai phương án thiết kế, mặt bằng và giải pháp kỹ thuật","responsibility":"Phòng Thiết kế","start_date":"2026-08-02","end_date":"2026-08-05","status":"completed","sort_order":2},{"parent_wbs":"I","wbs":"I.3","name":"Hoàn thiện bản vẽ, thuyết minh và hồ sơ thiết kế","responsibility":"Phòng Thiết kế","start_date":"2026-08-05","end_date":"2026-08-07","status":"completed","sort_order":3},{"parent_wbs":"I","wbs":"I.4","name":"Rà soát, chỉnh sửa và chốt hồ sơ thiết kế","responsibility":"Phòng Thiết kế","start_date":"2026-08-07","end_date":"2026-08-10","status":"completed","sort_order":4},{"parent_wbs":"II","wbs":"II.1","name":"Bóc tách khối lượng từ hồ sơ thiết kế","responsibility":"Phòng Kỹ thuật","start_date":"2026-08-11","end_date":"2026-08-12","status":"completed","sort_order":6},{"parent_wbs":"II","wbs":"II.2","name":"Xác lập đơn giá, chi phí vật tư, nhân công, máy","responsibility":"Phòng Kỹ thuật","start_date":"2026-08-12","end_date":"2026-08-13","status":"completed","sort_order":7},{"parent_wbs":"II","wbs":"II.3","name":"Kiểm tra, hoàn thiện và phê duyệt dự toán","responsibility":"Phòng Kỹ thuật","start_date":"2026-08-14","end_date":"2026-08-15","status":"completed","sort_order":8},{"parent_wbs":"III","wbs":"III.1","name":"Hoàn thiện HSMT/BOQ, yêu cầu kỹ thuật và tiêu chí đánh giá","responsibility":"Phòng HCTH","start_date":"2026-08-16","end_date":"2026-08-25","status":"in_progress","sort_order":10},{"parent_wbs":"III","wbs":"III.2","name":"Phê duyệt hồ sơ và danh sách nhà thầu","responsibility":"Phòng HCTH","start_date":"2026-08-26","end_date":"2026-08-26","status":"completed","sort_order":11},{"parent_wbs":"III","wbs":"III.3","name":"Phát hành mời chào/báo giá, khảo sát và làm rõ","responsibility":"Phòng HCTH","start_date":"2026-08-27","end_date":"2026-08-29","status":"completed","sort_order":12},{"parent_wbs":"III","wbs":"III.4","name":"Nhận và đánh giá hồ sơ chào giá","responsibility":"Phòng HCTH","start_date":"2026-08-30","end_date":"2026-09-01","status":"completed","sort_order":13},{"parent_wbs":"III","wbs":"III.5","name":"Đàm phán, phê duyệt kết quả và hoàn tất lựa chọn","responsibility":"Phòng HCTH","start_date":"2026-09-02","end_date":"2026-09-04","status":"in_progress","sort_order":14},{"parent_wbs":"IV","wbs":"IV.1","name":"Phá dỡ tường xây","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-04","end_date":"2026-09-08","status":"in_progress","sort_order":16},{"parent_wbs":"IV","wbs":"IV.2","name":"Tháo dỡ cửa và các cấu kiện cần tháo dỡ","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-06","end_date":"2026-09-10","status":"in_progress","sort_order":17},{"parent_wbs":"IV","wbs":"IV.3","name":"Cắt tường tạo cửa","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-09","end_date":"2026-09-11","status":"not_started","sort_order":18},{"parent_wbs":"IV","wbs":"IV.4","name":"Thu gom, vận chuyển phế liệu ra khỏi công trình","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-04","end_date":"2026-09-15","status":"in_progress","sort_order":19},{"parent_wbs":"IV","wbs":"IV.5","name":"Biện pháp an toàn tháo dỡ, che chắn, vệ sinh và bàn giao mặt bằng","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-04","end_date":"2026-09-15","status":"in_progress","sort_order":20},{"parent_wbs":"V","wbs":"V.1","name":"Xây tường, xây bậc tam cấp, bồn hoa","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-09","end_date":"2026-09-19","status":"not_started","sort_order":22},{"parent_wbs":"V","wbs":"V.2","name":"Trát tường trong và hoàn thiện bề mặt xây","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-14","end_date":"2026-09-23","status":"not_started","sort_order":23},{"parent_wbs":"V","wbs":"V.3","name":"Ốp gạch tường, thành bồn hoa và ốp đá tam cấp","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-18","end_date":"2026-09-28","status":"not_started","sort_order":24},{"parent_wbs":"V","wbs":"V.4","name":"Bả, sơn trong nhà; cạo sơn cũ và sơn ngoài nhà","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-18","end_date":"2026-10-03","status":"not_started","sort_order":25},{"parent_wbs":"V","wbs":"V.5","name":"Lát nền, sàn gạch 800x800 và 600x600","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-21","end_date":"2026-10-01","status":"not_started","sort_order":26},{"parent_wbs":"V","wbs":"V.6","name":"Cửa đi, cửa kính, cửa nhôm kính, vách nhôm kính, cửa gỗ, cửa chì","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-23","end_date":"2026-10-07","status":"not_started","sort_order":27},{"parent_wbs":"V","wbs":"V.7","name":"Trần thạch cao khung nổi và khung chìm","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-25","end_date":"2026-10-07","status":"not_started","sort_order":28},{"parent_wbs":"V","wbs":"V.8","name":"Bàn đá, khung bàn đá, bê tông nền và biển hiệu","responsibility":"P.Kỹ thuật, MKT / BQLDA","start_date":"2026-10-01","end_date":"2026-10-10","status":"not_started","sort_order":29},{"parent_wbs":"V","wbs":"V.9","name":"Kiểm tra, sửa lỗi và hoàn thiện kiến trúc","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-10-08","end_date":"2026-10-13","status":"not_started","sort_order":30},{"parent_wbs":"VI","wbs":"VI.1","name":"Cạo bỏ lớp sơn cũ ngoài nhà","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-09","end_date":"2026-09-13","status":"not_started","sort_order":32},{"parent_wbs":"VI","wbs":"VI.2","name":"Sơn ngoài nhà 1 nước lót, 2 nước phủ","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-14","end_date":"2026-09-21","status":"not_started","sort_order":33},{"parent_wbs":"VI","wbs":"VI.3","name":"Ốp đá","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-21","end_date":"2026-09-28","status":"not_started","sort_order":34},{"parent_wbs":"VII","wbs":"VII.1","name":"Dọn dẹp mặt bằng, nhổ cỏ","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-09","end_date":"2026-09-13","status":"not_started","sort_order":36},{"parent_wbs":"VII","wbs":"VII.2","name":"Sơn lại cổng, hàng rào và hoàn thiện","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-28","end_date":"2026-10-03","status":"not_started","sort_order":37},{"parent_wbs":"VIII","wbs":"VIII.1","name":"Cắt đục tường/sàn, tạo rãnh và lỗ chờ","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-14","end_date":"2026-09-23","status":"not_started","sort_order":39},{"parent_wbs":"VIII","wbs":"VIII.2","name":"Lắp ống luồn dây âm tường/âm sàn, hộp âm, hộp chia và ống chờ","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-19","end_date":"2026-10-01","status":"not_started","sort_order":40},{"parent_wbs":"VIII","wbs":"VIII.3","name":"Lắp máng cáp, thang cáp, giá đỡ và tuyến cáp kỹ thuật","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-25","end_date":"2026-10-08","status":"not_started","sort_order":41},{"parent_wbs":"VIII","wbs":"VIII.4","name":"Tủ điện tổng, tủ điện tầng, tủ thiết bị, MCCB/MCB","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-14","end_date":"2026-09-28","status":"not_started","sort_order":42},{"parent_wbs":"VIII","wbs":"VIII.5","name":"Ống luồn dây PVC, ống ruột gà, hộp chia, máng cáp và phụ kiện","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-18","end_date":"2026-10-08","status":"not_started","sort_order":43},{"parent_wbs":"VIII","wbs":"VIII.6","name":"Kéo rải dây dẫn các loại và dây tiếp địa","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-28","end_date":"2026-10-15","status":"not_started","sort_order":44},{"parent_wbs":"VIII","wbs":"VIII.7","name":"Đèn, công tắc, ổ cắm, quạt và thiết bị điện","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-10-08","end_date":"2026-10-22","status":"not_started","sort_order":45},{"parent_wbs":"VIII","wbs":"VIII.8","name":"Đấu nối, đo kiểm, chạy thử và khắc phục tồn tại","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-10-23","end_date":"2026-10-29","status":"not_started","sort_order":46},{"parent_wbs":"IX","wbs":"IX.1","name":"Cắt đục tường/sàn, tạo rãnh và lỗ chờ cấp thoát nước","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-14","end_date":"2026-09-23","status":"not_started","sort_order":48},{"parent_wbs":"IX","wbs":"IX.2","name":"Lắp ống cấp PPR âm tường/âm sàn, ống thoát và phụ kiện","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-19","end_date":"2026-10-05","status":"not_started","sort_order":49},{"parent_wbs":"IX","wbs":"IX.3","name":"Lắp ống đứng, tuyến ống chính, giá đỡ và đầu chờ thiết bị","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-28","end_date":"2026-10-13","status":"not_started","sort_order":50},{"parent_wbs":"IX","wbs":"IX.4","name":"Lắp đặt chậu rửa, lavabo, vòi, thiết bị cảm ứng và máy sấy tay","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-14","end_date":"2026-10-03","status":"not_started","sort_order":51},{"parent_wbs":"IX","wbs":"IX.5","name":"Cút, tê, măng sông, van, quang treo, ty ren và phụ kiện PPR","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-18","end_date":"2026-10-08","status":"not_started","sort_order":52},{"parent_wbs":"IX","wbs":"IX.6","name":"Lắp đặt tuyến ống PPR và ống thoát","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-28","end_date":"2026-10-19","status":"not_started","sort_order":53},{"parent_wbs":"IX","wbs":"IX.7","name":"Thử áp, thử kín, súc xả và nghiệm thu","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-10-20","end_date":"2026-10-29","status":"not_started","sort_order":54},{"parent_wbs":"X","wbs":"X.1","name":"Cắt đục, tạo lỗ chờ và tuyến ống âm","responsibility":"P.TBTN / BQLDA","start_date":"2026-09-28","end_date":"2026-10-08","status":"not_started","sort_order":56},{"parent_wbs":"X","wbs":"X.2","name":"Lắp ống luồn, hộp kỹ thuật, máng/thang cáp và dây chờ CAT6/cáp quang","responsibility":"P.TBTN / BQLDA","start_date":"2026-10-03","end_date":"2026-10-15","status":"not_started","sort_order":57},{"parent_wbs":"X","wbs":"X.3","name":"Hạ tầng cáp CAT5E/CAT6/AWG, cáp quang, nẹp, máng, thang cáp và phụ kiện","responsibility":"P.TBTN / BQLDA","start_date":"2026-09-28","end_date":"2026-10-15","status":"not_started","sort_order":58},{"parent_wbs":"X","wbs":"X.4","name":"Camera, Wifi, loa, Amply, Micro, máy chấm công và hệ thống hiển thị","responsibility":"P.TBTN / BQLDA","start_date":"2026-10-08","end_date":"2026-10-29","status":"not_started","sort_order":59},{"parent_wbs":"X","wbs":"X.5","name":"Tủ mạng, switch, router, ODF, UPS, NVR, máy chủ và phụ kiện","responsibility":"P.TBTN / BQLDA","start_date":"2026-10-15","end_date":"2026-11-01","status":"not_started","sort_order":60},{"parent_wbs":"X","wbs":"X.6","name":"Máy tính, máy in, tivi, màn hình, giá treo và thiết bị đầu cuối","responsibility":"P.TBTN / BQLDA","start_date":"2026-10-22","end_date":"2026-11-03","status":"not_started","sort_order":61},{"parent_wbs":"X","wbs":"X.7","name":"Đấu nối, cấu hình, kiểm tra và chạy thử toàn hệ thống","responsibility":"P.TBTN / BQLDA","start_date":"2026-11-02","end_date":"2026-11-08","status":"not_started","sort_order":62},{"parent_wbs":"XI","wbs":"XI.1","name":"Cắt đục tường/sàn, tạo rãnh và lỗ chờ","responsibility":"P.TBTN / BQLDA","start_date":"2026-09-28","end_date":"2026-10-05","status":"not_started","sort_order":64},{"parent_wbs":"XI","wbs":"XI.2","name":"Lắp ống đồng/ống khí y tế, giá đỡ, phụ kiện và tuyến ống chính","responsibility":"P.TBTN / BQLDA","start_date":"2026-10-03","end_date":"2026-10-19","status":"not_started","sort_order":65},{"parent_wbs":"XI","wbs":"XI.3","name":"Lắp van khu vực, hộp khí, đầu chờ và hoàn trả rãnh","responsibility":"P.TBTN / BQLDA","start_date":"2026-10-15","end_date":"2026-10-26","status":"not_started","sort_order":66},{"parent_wbs":"XI","wbs":"XI.4","name":"Ống đồng, ống PPR, cút, tê, van và phụ kiện","responsibility":"P.TBTN / BQLDA","start_date":"2026-09-28","end_date":"2026-10-15","status":"not_started","sort_order":67},{"parent_wbs":"XI","wbs":"XI.5","name":"Bộ hạ áp, máy sấy khí, bình khí, máy nén khí và tủ cấp nguồn","responsibility":"P.TBTN / BQLDA","start_date":"2026-10-15","end_date":"2026-10-26","status":"not_started","sort_order":68},{"parent_wbs":"XI","wbs":"XI.6","name":"Bộ gộp khí, hộp khí, đấu nối và hoàn thiện","responsibility":"P.TBTN / BQLDA","start_date":"2026-10-22","end_date":"2026-10-29","status":"not_started","sort_order":69},{"parent_wbs":"XI","wbs":"XI.7","name":"Thử kín, thử áp, kiểm tra chất lượng và nghiệm thu","responsibility":"P.TBTN / BQLDA","start_date":"2026-10-30","end_date":"2026-11-03","status":"not_started","sort_order":70},{"parent_wbs":"XII","wbs":"XII.1","name":"Cắt đục, khoan xuyên tường/sàn, tạo lỗ chờ","responsibility":"P.TBTN / BQLDA","start_date":"2026-09-28","end_date":"2026-10-08","status":"not_started","sort_order":72},{"parent_wbs":"XII","wbs":"XII.2","name":"Lắp ống kẽm PCCC, giá đỡ, ty treo, van và phụ kiện","responsibility":"P.TBTN / BQLDA","start_date":"2026-10-03","end_date":"2026-10-24","status":"not_started","sort_order":73},{"parent_wbs":"XII","wbs":"XII.3","name":"Lắp ống luồn dây báo cháy, hộp kỹ thuật và dây chờ","responsibility":"P.TBTN / BQLDA","start_date":"2026-10-08","end_date":"2026-10-22","status":"not_started","sort_order":74},{"parent_wbs":"XII","wbs":"XII.4","name":"Bịt xuyên sàn và hoàn trả xây dựng","responsibility":"P.TBTN / BQLDA","start_date":"2026-10-15","end_date":"2026-10-29","status":"not_started","sort_order":75},{"parent_wbs":"XII","wbs":"XII.5","name":"Kéo rải dây tín hiệu và ống PVC/ống mềm luồn dây","responsibility":"P.TBTN / BQLDA","start_date":"2026-09-28","end_date":"2026-10-15","status":"not_started","sort_order":76},{"parent_wbs":"XII","wbs":"XII.6","name":"Đầu báo, chuông đèn, module, hộp kỹ thuật và tủ báo cháy","responsibility":"P.TBTN / BQLDA","start_date":"2026-10-08","end_date":"2026-10-29","status":"not_started","sort_order":77},{"parent_wbs":"XII","wbs":"XII.7","name":"Bình chữa cháy, đèn thoát hiểm, đèn sự cố, biển chỉ dẫn","responsibility":"P.TBTN / BQLDA","start_date":"2026-10-15","end_date":"2026-11-03","status":"not_started","sort_order":78},{"parent_wbs":"XII","wbs":"XII.8","name":"Đấu nối, lập trình, kiểm tra liên động, chạy thử và hoàn thiện hồ sơ","responsibility":"P.TBTN / BQLDA","start_date":"2026-10-30","end_date":"2026-11-13","status":"not_started","sort_order":79},{"parent_wbs":"XIII","wbs":"XIII.1","name":"Cắt đục, khoan xuyên tường/sàn và tạo lỗ chờ","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-10-03","end_date":"2026-10-13","status":"not_started","sort_order":81},{"parent_wbs":"XIII","wbs":"XIII.2","name":"Lắp ống đồng gas, giá đỡ và tuyến ống chính","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-10-08","end_date":"2026-10-26","status":"not_started","sort_order":82},{"parent_wbs":"XIII","wbs":"XIII.3","name":"Lắp ống nước ngưng và bảo ôn","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-10-15","end_date":"2026-10-29","status":"not_started","sort_order":83},{"parent_wbs":"XIII","wbs":"XIII.4","name":"Lắp ống gió, giá treo và phụ kiện thông gió","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-10-08","end_date":"2026-10-29","status":"not_started","sort_order":84},{"parent_wbs":"XIII","wbs":"XIII.5","name":"Lắp đặt dàn nóng ODU và giá đỡ","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-10-03","end_date":"2026-10-19","status":"not_started","sort_order":85},{"parent_wbs":"XIII","wbs":"XIII.6","name":"Lắp đặt dàn lạnh các công suất","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-10-15","end_date":"2026-11-03","status":"not_started","sort_order":86},{"parent_wbs":"XIII","wbs":"XIII.7","name":"Lắp đặt ống gió, phụ kiện và hệ thống liên quan","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-10-15","end_date":"2026-11-03","status":"not_started","sort_order":87},{"parent_wbs":"XIII","wbs":"XIII.8","name":"Đấu nối, bảo ôn, kiểm tra, chạy thử và cân chỉnh","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-11-04","end_date":"2026-11-18","status":"not_started","sort_order":88},{"parent_wbs":"XIV","wbs":"XIV.1","name":"Lắp đặt tuyến ống cấp nước RO, ống hồi và giá đỡ","responsibility":"P.TBTN / BQLDA","start_date":"2026-10-20","end_date":"2026-10-31","status":"not_started","sort_order":90},{"parent_wbs":"XIV","wbs":"XIV.2","name":"Lắp đặt cụm xử lý RO: tiền xử lý, màng RO, bồn chứa và bơm","responsibility":"P.TBTN / BQLDA","start_date":"2026-10-25","end_date":"2026-11-08","status":"not_started","sort_order":91},{"parent_wbs":"XIV","wbs":"XIV.3","name":"Lắp đặt tủ điện, điều khiển, cảm biến và đấu nối hệ thống RO","responsibility":"P.TBTN / BQLDA","start_date":"2026-11-01","end_date":"2026-11-10","status":"not_started","sort_order":92},{"parent_wbs":"XIV","wbs":"XIV.4","name":"Súc rửa, khử trùng, kiểm tra chất lượng nước, chạy thử và nghiệm thu","responsibility":"P.TBTN / BQLDA","start_date":"2026-11-09","end_date":"2026-11-15","status":"not_started","sort_order":93},{"parent_wbs":"XV","wbs":"XV.1","name":"Thi công móng bệ TBA, rãnh cáp và hệ thống tiếp địa","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-21","end_date":"2026-10-02","status":"not_started","sort_order":95},{"parent_wbs":"XV","wbs":"XV.2","name":"Lắp đặt tủ trung thế, máy biến áp 300 kVA và tủ điện hạ thế","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-10-03","end_date":"2026-10-15","status":"not_started","sort_order":96},{"parent_wbs":"XV","wbs":"XV.3","name":"Thi công cáp trung thế/hạ thế, đầu cáp và đấu nối","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-10-10","end_date":"2026-10-24","status":"not_started","sort_order":97},{"parent_wbs":"XV","wbs":"XV.4","name":"Hoàn thiện tiếp địa, chống sét và kiểm tra hệ thống bảo vệ","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-10-18","end_date":"2026-10-28","status":"not_started","sort_order":98},{"parent_wbs":"XV","wbs":"XV.5","name":"Thí nghiệm điện, kiểm định, đóng điện và nghiệm thu TBA","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-10-29","end_date":"2026-11-05","status":"not_started","sort_order":99},{"parent_wbs":"XVI","wbs":"XVI.1","name":"Định vị, đào đất, xử lý nền và chuẩn bị mặt bằng","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-09","end_date":"2026-09-18","status":"not_started","sort_order":101},{"parent_wbs":"XVI","wbs":"XVI.2","name":"Bê tông lót, cốt thép và cốp pha đáy bể","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-19","end_date":"2026-09-28","status":"not_started","sort_order":102},{"parent_wbs":"XVI","wbs":"XVI.3","name":"Đổ bê tông đáy bể, xử lý mạch ngừng và chống thấm","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-09-29","end_date":"2026-10-03","status":"not_started","sort_order":103},{"parent_wbs":"XVI","wbs":"XVI.4","name":"Cốt thép, cốp pha và đổ bê tông thành bể/vách ngăn","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-10-01","end_date":"2026-10-13","status":"not_started","sort_order":104},{"parent_wbs":"XVI","wbs":"XVI.5","name":"Nắp bể, cổ ống, lỗ thăm và chi tiết chờ thiết bị công nghệ","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-10-11","end_date":"2026-10-19","status":"not_started","sort_order":105},{"parent_wbs":"XVI","wbs":"XVI.6","name":"Chống thấm, thử nước và hoàn thiện kết cấu bể","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-10-15","end_date":"2026-10-24","status":"not_started","sort_order":106},{"parent_wbs":"XVII","wbs":"XVII.1","name":"Lắp bơm, thiết bị tiền xử lý và thiết bị cơ khí trong bể","responsibility":"P.TBTN / BQLDA","start_date":"2026-10-25","end_date":"2026-11-03","status":"not_started","sort_order":108},{"parent_wbs":"XVII","wbs":"XVII.2","name":"Lắp đường ống công nghệ, van, giá đỡ và phụ kiện","responsibility":"P.TBTN / BQLDA","start_date":"2026-10-29","end_date":"2026-11-08","status":"not_started","sort_order":109},{"parent_wbs":"XVII","wbs":"XVII.3","name":"Lắp máy thổi khí, đường khí và hệ thống phân phối khí","responsibility":"P.TBTN / BQLDA","start_date":"2026-11-03","end_date":"2026-11-13","status":"not_started","sort_order":110},{"parent_wbs":"XVII","wbs":"XVII.4","name":"Lắp tủ điện điều khiển, cáp nguồn, cáp tín hiệu và đấu nối","responsibility":"P.TBTN / BQLDA","start_date":"2026-11-08","end_date":"2026-11-16","status":"not_started","sort_order":111},{"parent_wbs":"XVII","wbs":"XVII.5","name":"Lắp thiết bị đo, điều khiển và thiết bị phụ trợ","responsibility":"P.TBTN / BQLDA","start_date":"2026-11-11","end_date":"2026-11-18","status":"not_started","sort_order":112},{"parent_wbs":"XVII","wbs":"XVII.6","name":"Vệ sinh hệ thống, kiểm tra kín nước và hoàn thiện","responsibility":"P.TBTN / BQLDA","start_date":"2026-11-14","end_date":"2026-11-19","status":"not_started","sort_order":113},{"parent_wbs":"XVII","wbs":"XVII.7","name":"Chạy thử không tải, có tải và hiệu chỉnh công nghệ","responsibility":"P.TBTN / BQLDA","start_date":"2026-11-14","end_date":"2026-11-23","status":"not_started","sort_order":114},{"parent_wbs":"XVII","wbs":"XVII.8","name":"Lấy mẫu, hoàn thiện hồ sơ vận hành và nghiệm thu","responsibility":"P.TBTN / BQLDA","start_date":"2026-11-21","end_date":"2026-11-25","status":"not_started","sort_order":115},{"parent_wbs":"XVIII","wbs":"XVIII.1","name":"Đo kiểm điện, thử áp nước, thử kín khí y tế, kiểm tra PCCC","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-11-19","end_date":"2026-11-25","status":"not_started","sort_order":117},{"parent_wbs":"XVIII","wbs":"XVIII.2","name":"Chạy thử điều hòa – thông gió và cân chỉnh","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-11-20","end_date":"2026-11-25","status":"not_started","sort_order":118},{"parent_wbs":"XVIII","wbs":"XVIII.3","name":"Chạy thử điện nhẹ và cấu hình hệ thống","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-11-21","end_date":"2026-11-26","status":"not_started","sort_order":119},{"parent_wbs":"XVIII","wbs":"XVIII.4","name":"Hoàn thiện QA/QC, CO/CQ, bản vẽ hoàn công, hồ sơ vận hành","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-11-22","end_date":"2026-11-29","status":"not_started","sort_order":120},{"parent_wbs":"XVIII","wbs":"XVIII.5","name":"Nghiệm thu tổng thể","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-11-27","end_date":"2026-12-01","status":"not_started","sort_order":121},{"parent_wbs":"XVIII","wbs":"XVIII.6","name":"Vệ sinh, bàn giao hồ sơ và đưa công trình vào sử dụng","responsibility":"P.Kỹ thuật / BQLDA","start_date":"2026-12-02","end_date":"2026-12-03","status":"not_started","sort_order":122},{"parent_wbs":"XIX","wbs":"XIX.1","name":"Xác định cơ cấu nhân sự, định biên và mô tả vị trí","responsibility":"Phòng PTPK","start_date":"2026-08-10","end_date":"2026-08-19","status":"completed","sort_order":124},{"parent_wbs":"XIX","wbs":"XIX.2","name":"Đăng tuyển, tiếp nhận và sàng lọc hồ sơ","responsibility":"Phòng PTPK","start_date":"2026-08-20","end_date":"2026-09-10","status":"in_progress","sort_order":125},{"parent_wbs":"XIX","wbs":"XIX.3","name":"Phỏng vấn, kiểm tra chuyên môn và lựa chọn","responsibility":"Phòng PTPK","start_date":"2026-09-11","end_date":"2026-10-05","status":"not_started","sort_order":126},{"parent_wbs":"XIX","wbs":"XIX.4","name":"Hoàn thiện hồ sơ, ký hợp đồng và tiếp nhận nhân sự","responsibility":"Phòng PTPK","start_date":"2026-10-06","end_date":"2026-11-28","status":"not_started","sort_order":127},{"parent_wbs":"XX","wbs":"XX.1","name":"Chốt danh mục, thông số kỹ thuật và nhu cầu","responsibility":"Phòng TBYT / Cung ứng","start_date":"2026-08-20","end_date":"2026-08-23","status":"completed","sort_order":129},{"parent_wbs":"XX","wbs":"XX.2","name":"Lập yêu cầu báo giá, thẩm định cấu hình và lựa chọn nhà cung cấp","responsibility":"Phòng Cung ứng","start_date":"2026-08-21","end_date":"2026-09-10","status":"in_progress","sort_order":130},{"parent_wbs":"XX","wbs":"XX.3","name":"Đặt hàng, sản xuất/giao hàng","responsibility":"Phòng Cung ứng","start_date":"2026-09-11","end_date":"2026-10-31","status":"not_started","sort_order":131},{"parent_wbs":"XX","wbs":"XX.4","name":"Lắp đặt, kiểm tra, chạy thử và nghiệm thu","responsibility":"Phòng TBYT","start_date":"2026-11-01","end_date":"2026-11-23","status":"not_started","sort_order":132},{"parent_wbs":"XXI","wbs":"XXI.1","name":"Rà soát danh mục, định mức và nhu cầu tồn kho","responsibility":"Phòng Cung ứng","start_date":"2026-08-10","end_date":"2026-08-20","status":"completed","sort_order":134},{"parent_wbs":"XXI","wbs":"XXI.2","name":"Lập danh mục, tiêu chuẩn, hồ sơ mua sắm","responsibility":"Phòng Cung ứng","start_date":"2026-08-21","end_date":"2026-09-05","status":"in_progress","sort_order":135},{"parent_wbs":"XXI","wbs":"XXI.3","name":"Chào giá/lựa chọn nhà cung cấp và đặt hàng","responsibility":"Phòng Cung ứng","start_date":"2026-09-06","end_date":"2026-10-10","status":"in_progress","sort_order":136},{"parent_wbs":"XXI","wbs":"XXI.4","name":"Giao nhận, kiểm nhập, sắp xếp kho và hoàn thiện hồ sơ","responsibility":"Phòng Cung ứng","start_date":"2026-10-11","end_date":"2026-12-10","status":"not_started","sort_order":137},{"parent_wbs":"XXII","wbs":"XXII.1","name":"Xây dựng kế hoạch truyền thông, nhận diện và thông điệp khai trương","responsibility":"Phòng Marketing","start_date":"2026-08-10","end_date":"2026-08-20","status":"completed","sort_order":139},{"parent_wbs":"XXII","wbs":"XXII.2","name":"Chuẩn bị nội dung, hình ảnh, kênh truyền thông và lịch triển khai","responsibility":"Phòng Marketing","start_date":"2026-08-21","end_date":"2026-09-20","status":"in_progress","sort_order":140},{"parent_wbs":"XXII","wbs":"XXII.3","name":"Triển khai truyền thông trước khai trương","responsibility":"Phòng Marketing","start_date":"2026-09-21","end_date":"2026-11-10","status":"not_started","sort_order":141},{"parent_wbs":"XXII","wbs":"XXII.4","name":"Truyền thông cao điểm, phối hợp khai trương và tối ưu chiến dịch","responsibility":"Phòng Marketing","start_date":"2026-11-11","end_date":"2026-12-04","status":"not_started","sort_order":142},{"parent_wbs":"XXIII","wbs":"XXIII.1","name":"Khảo sát yêu cầu, kiến trúc hệ thống và phân quyền","responsibility":"Phòng Số hóa","start_date":"2026-08-10","end_date":"2026-08-20","status":"completed","sort_order":144},{"parent_wbs":"XXIII","wbs":"XXIII.2","name":"Thiết kế website, mail và cấu hình HIS","responsibility":"Phòng Số hóa","start_date":"2026-08-21","end_date":"2026-09-30","status":"in_progress","sort_order":145},{"parent_wbs":"XXIII","wbs":"XXIII.3","name":"Tích hợp, nhập dữ liệu, cấu hình quy trình nghiệp vụ","responsibility":"Phòng Số hóa","start_date":"2026-10-01","end_date":"2026-11-10","status":"not_started","sort_order":146},{"parent_wbs":"XXIII","wbs":"XXIII.4","name":"Kiểm thử, đào tạo người dùng, nghiệm thu và vận hành thử","responsibility":"Phòng Số hóa","start_date":"2026-11-11","end_date":"2026-11-29","status":"not_started","sort_order":147},{"parent_wbs":"XXIV","wbs":"XXIV.1","name":"Chuẩn bị và nộp hồ sơ xin Giấy phép hoạt động","responsibility":"Phòng NVY","start_date":"2026-12-11","end_date":"2026-12-17","status":"not_started","sort_order":149},{"parent_wbs":"XXIV","wbs":"XXIV.2","name":"Bổ sung/giải trình hồ sơ và phối hợp thẩm định","responsibility":"Phòng NVY / Các đơn vị","start_date":"2026-12-18","end_date":"2026-12-31","status":"not_started","sort_order":150},{"parent_wbs":"XXIV","wbs":"XXIV.3","name":"Nhận và hoàn tất Giấy phép hoạt động","responsibility":"Phòng NVY","start_date":"2027-01-01","end_date":"2027-01-10","status":"not_started","sort_order":151},{"parent_wbs":"XXV","wbs":"XXV.1","name":"Chuẩn bị hồ sơ, rà soát điều kiện và biểu mẫu ký hợp đồng","responsibility":"Phòng NVY / PTPK","start_date":"2026-12-11","end_date":"2026-12-20","status":"not_started","sort_order":153},{"parent_wbs":"XXV","wbs":"XXV.2","name":"Hoàn thiện hồ sơ, danh mục dịch vụ, nhân lực và cơ sở vật chất","responsibility":"Phòng NVY / PTPK","start_date":"2026-12-21","end_date":"2027-01-10","status":"not_started","sort_order":154},{"parent_wbs":"XXV","wbs":"XXV.3","name":"Làm việc, bổ sung/giải trình hồ sơ với cơ quan BHXH","responsibility":"Phòng NVY / PTPK","start_date":"2027-01-11","end_date":"2027-01-31","status":"not_started","sort_order":155},{"parent_wbs":"XXV","wbs":"XXV.4","name":"Hoàn tất ký hợp đồng KCB BHYT","responsibility":"Phòng NVY / PTPK","start_date":"2027-02-01","end_date":"2027-02-10","status":"not_started","sort_order":156}]$tasks$::jsonb)
    as source(parent_wbs text, wbs text, name text, responsibility text, start_date text, end_date text, status text, sort_order integer)
  join public.work_items parent on parent.project_id = khe_tre_id and parent.parent_id is null and parent.wbs = source.parent_wbs
  where not exists (select 1 from public.work_items existing where existing.project_id = khe_tre_id and existing.wbs = source.wbs);
end;
$$;


-- ==========================================
-- Migration: 202609090004_seed_milestones_and_workflow.sql
-- ==========================================
-- Mốc kiểm soát từ prototype và quy tắc bằng chứng/duyệt đã chốt.
create unique index if not exists attachments_one_evidence_per_work_item_idx on public.attachments(work_item_id) where completion_request_id is null;

drop policy if exists attachments_add_participant on public.attachments;
create policy attachments_add_participant on public.attachments for insert to authenticated with check (
  uploaded_by = auth.uid() and (public.is_manager() or public.is_work_item_participant(work_item_id))
  and not exists (select 1 from public.work_items child where child.parent_id = work_item_id)
);
drop policy if exists attachments_delete_participant on public.attachments;
create policy attachments_delete_participant on public.attachments for delete to authenticated using (public.is_manager() or public.is_work_item_participant(work_item_id));
drop policy if exists evidence_delete_participant on storage.objects;
create policy evidence_delete_participant on storage.objects for delete to authenticated using (
  bucket_id = 'evidence' and (public.is_manager() or public.is_work_item_participant(((storage.foldername(name))[1])::uuid))
);

create or replace function public.submit_work_item_completion(target_work_item_id uuid, submission_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare request_id uuid; next_attempt integer;
begin
  if not public.is_manager() and not public.is_work_item_participant(target_work_item_id) then raise exception 'Bạn không tham gia công việc này'; end if;
  if exists (select 1 from public.work_items where parent_id = target_work_item_id) then raise exception 'Chỉ công việc cuối nhánh mới được gửi hoàn thành'; end if;
  if (select count(*) from public.attachments where work_item_id = target_work_item_id and completion_request_id is null) <> 1 then raise exception 'Công việc phải có đúng một tệp bằng chứng'; end if;
  if exists (select 1 from public.completion_requests where work_item_id = target_work_item_id and status = 'pending') then raise exception 'Công việc đã có yêu cầu chờ duyệt'; end if;
  select coalesce(max(attempt_no), 0) + 1 into next_attempt from public.completion_requests where work_item_id = target_work_item_id;
  insert into public.completion_requests (work_item_id, attempt_no, note, submitted_by) values (target_work_item_id, next_attempt, nullif(trim(submission_note), ''), auth.uid()) returning id into request_id;
  update public.work_items set status = 'pending_approval', updated_by = auth.uid(), version = version + 1 where id = target_work_item_id and status not in ('pending_approval', 'completed');
  if not found then raise exception 'Công việc không thể gửi duyệt ở trạng thái hiện tại'; end if;
  return request_id;
end;
$$;

do $$
declare actor_id uuid; target_project_id uuid;
begin
  select id into actor_id from public.profiles where username = 'admin' limit 1;
  select id into target_project_id from public.projects where code = 'PK-KHETRE';
  insert into public.milestones (project_id, name, due_date, condition_text, achieved, achieved_at, sort_order, created_by, updated_by)
  select target_project_id, source.name, source.due_date::date, source.condition_text, source.achieved, source.achieved_at::date, source.sort_order, actor_id, actor_id
  from jsonb_to_recordset($m$[{"name":"Hoàn thành thiết kế","due_date":"2026-08-10","condition_text":"Đủ bản vẽ, thuyết minh và hồ sơ thiết kế để lập dự toán","achieved":true,"achieved_at":"2026-08-10","sort_order":0},{"name":"Hoàn thành lập dự toán","due_date":"2026-08-24","condition_text":"BOQ và dự toán được rà soát, phê duyệt","achieved":true,"achieved_at":"2026-08-24","sort_order":1},{"name":"Hoàn thành mời chào và lựa chọn nhà thầu","due_date":"2026-09-03","condition_text":"Chốt nhà thầu, sẵn sàng huy động","achieved":false,"achieved_at":null,"sort_order":2},{"name":"Hoàn thành phá dỡ chính","due_date":"2026-09-15","condition_text":"Mặt bằng sạch, đủ điều kiện triển khai các hạng mục tiếp theo","achieved":false,"achieved_at":null,"sort_order":3},{"name":"Hoàn thành kết cấu bể XLNT","due_date":"2026-10-26","condition_text":"Kết cấu, chống thấm và thử nước đạt","achieved":false,"achieved_at":null,"sort_order":4},{"name":"Hoàn thành phần MEP chính","due_date":"2026-11-28","condition_text":"Điện, nước, điện nhẹ, khí y tế, PCCC, điều hòa thông gió cơ bản hoàn thành","achieved":false,"achieved_at":null,"sort_order":5},{"name":"Hoàn thành máy móc, thiết bị y tế","due_date":"2026-11-08","condition_text":"Lắp đặt, chạy thử, nghiệm thu","achieved":false,"achieved_at":null,"sort_order":6},{"name":"Hoàn thành tuyển dụng bổ sung","due_date":"2026-11-28","condition_text":"Hoàn tất theo kế hoạch 3 tháng 20 ngày","achieved":false,"achieved_at":null,"sort_order":7},{"name":"Hoàn thành Website, mail, HIS","due_date":"2026-11-29","condition_text":"Kiểm thử, đào tạo và vận hành thử","achieved":false,"achieved_at":null,"sort_order":8},{"name":"Hoàn thành thi công TBA 300 kVA","due_date":"2026-11-05","condition_text":"Lắp đặt, thí nghiệm, đóng điện và nghiệm thu đạt yêu cầu","achieved":false,"achieved_at":null,"sort_order":9},{"name":"Hoàn thành hệ thống RO","due_date":"2026-11-15","condition_text":"Lắp đặt, súc rửa/khử trùng, kiểm tra chất lượng nước, chạy thử và nghiệm thu","achieved":false,"achieved_at":null,"sort_order":10},{"name":"Kết thúc tiến độ tổng thể","due_date":"2026-12-10","condition_text":"Các hạng mục trong phạm vi tổng thể sẵn sàng đưa vào giai đoạn thủ tục","achieved":false,"achieved_at":null,"sort_order":11},{"name":"Hoàn thành Giấy phép hoạt động","due_date":"2027-01-10","condition_text":"Thời gian 1 tháng, bắt đầu sau 10/12/2026","achieved":false,"achieved_at":null,"sort_order":12},{"name":"Hoàn thành ký hợp đồng KCB BHYT","due_date":"2027-02-10","condition_text":"Thời gian 2 tháng, bắt đầu sau 10/12/2026","achieved":false,"achieved_at":null,"sort_order":13}]$m$::jsonb) as source(name text, due_date text, condition_text text, achieved boolean, achieved_at text, sort_order integer)
  where not exists (select 1 from public.milestones existing where existing.project_id = target_project_id and existing.name = source.name);
end;
$$;


-- ==========================================
-- Migration: 202609090005_milestone_owner.sql
-- ==========================================
-- Giữ trường đơn vị chủ trì của mốc kiểm soát như prototype đã duyệt.
alter table public.milestones add column if not exists owner_text text;

update public.milestones milestone
set owner_text = source.owner_text
from (values
  ('Hoàn thành thiết kế', 'Phòng Thiết kế'),
  ('Hoàn thành lập dự toán', 'Phòng Kỹ thuật'),
  ('Hoàn thành mời chào và lựa chọn nhà thầu', 'Phòng HCTH'),
  ('Hoàn thành phá dỡ chính', 'Phòng Kỹ thuật'),
  ('Hoàn thành kết cấu bể XLNT', 'Phòng Kỹ thuật'),
  ('Hoàn thành phần MEP chính', 'Phòng Kỹ thuật/TBTN'),
  ('Hoàn thành máy móc, thiết bị y tế', 'Phòng Cung ứng/ TBYT'),
  ('Hoàn thành tuyển dụng bổ sung', 'Phòng PTPK'),
  ('Hoàn thành Website, mail, HIS', 'Phòng Số hóa'),
  ('Hoàn thành thi công TBA 300 kVA', 'Phòng Kỹ thuật'),
  ('Hoàn thành hệ thống RO', 'Phòng Kỹ thuật/TBTN'),
  ('Kết thúc tiến độ tổng thể', 'Phòng Kỹ thuật'),
  ('Hoàn thành Giấy phép hoạt động', 'Phòng NVY chủ trì'),
  ('Hoàn thành ký hợp đồng KCB BHYT', 'Phòng NVY chủ trì / PTPK phối hợp')
) as source(name, owner_text)
where milestone.name = source.name and milestone.owner_text is null;


-- ==========================================
-- Migration: 202609090006_import_project_plan.sql
-- ==========================================
-- Thay toàn bộ tiến độ một dự án trong một transaction sau bước preview Excel.
create or replace function public.import_project_plan(target_project_id uuid, plan_items jsonb)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  item jsonb;
  new_id uuid;
  parent_uuid uuid;
  id_map jsonb := '{}'::jsonb;
  inserted_count integer := 0;
begin
  if not public.is_manager() then raise exception 'Chỉ sếp được nạp tiến độ Excel'; end if;
  if jsonb_typeof(plan_items) <> 'array' or jsonb_array_length(plan_items) = 0 then raise exception 'File không có dữ liệu tiến độ'; end if;

  delete from public.work_items where project_id = target_project_id;

  for item in select value from jsonb_array_elements(plan_items) loop
    parent_uuid := null;
    if nullif(item->>'parent_client_id', '') is not null then
      parent_uuid := nullif(id_map->>(item->>'parent_client_id'), '')::uuid;
      if parent_uuid is null then raise exception 'Cấu trúc hạng mục không hợp lệ'; end if;
    end if;
    insert into public.work_items(project_id, parent_id, wbs, name, source_responsibility_text, start_date, end_date, status, sort_order)
    values (
      target_project_id, parent_uuid, item->>'wbs', trim(item->>'name'), nullif(trim(item->>'responsibility'), ''),
      nullif(item->>'start_date', '')::date, nullif(item->>'end_date', '')::date, 'not_started', (item->>'sort_order')::integer
    ) returning id into new_id;
    id_map := id_map || jsonb_build_object(item->>'client_id', new_id::text);
    inserted_count := inserted_count + 1;
  end loop;
  return inserted_count;
end;
$$;

grant execute on function public.import_project_plan(uuid, jsonb) to authenticated;


-- ==========================================
-- Migration: 202609090007_save_milestone_draft.sql
-- ==========================================
-- Lưu toàn bộ bản nháp mốc kiểm soát trong một transaction.
create or replace function public.save_project_milestones(target_project_id uuid, milestone_items jsonb)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare item jsonb; saved integer := 0; persisted_id uuid;
begin
  if not public.is_manager() then raise exception 'Chỉ sếp được sửa mốc kiểm soát'; end if;
  if jsonb_typeof(milestone_items) <> 'array' then raise exception 'Dữ liệu mốc không hợp lệ'; end if;

  delete from public.milestones
  where project_id = target_project_id
    and id not in (
      select (value->>'id')::uuid from jsonb_array_elements(milestone_items)
      where nullif(value->>'id', '') is not null
    );

  for item in select value from jsonb_array_elements(milestone_items) loop
    persisted_id := nullif(item->>'id', '')::uuid;
    if persisted_id is null then
      insert into public.milestones(project_id, name, due_date, owner_text, condition_text, achieved, achieved_at, sort_order)
      values (target_project_id, trim(item->>'name'), (item->>'due_date')::date, nullif(trim(item->>'owner_text'), ''), nullif(trim(item->>'condition_text'), ''), coalesce((item->>'achieved')::boolean, false), nullif(item->>'achieved_at', '')::date, (item->>'sort_order')::integer);
    else
      update public.milestones set
        name = trim(item->>'name'), due_date = (item->>'due_date')::date,
        owner_text = nullif(trim(item->>'owner_text'), ''), condition_text = nullif(trim(item->>'condition_text'), ''),
        achieved = coalesce((item->>'achieved')::boolean, false), achieved_at = nullif(item->>'achieved_at', '')::date,
        sort_order = (item->>'sort_order')::integer
      where id = persisted_id and project_id = target_project_id;
    end if;
    saved := saved + 1;
  end loop;
  return saved;
end;
$$;

grant execute on function public.save_project_milestones(uuid, jsonb) to authenticated;


-- ==========================================
-- Migration: 202609090008_create_work_item_draft.sql
-- ==========================================
create or replace function public.create_work_item(
  target_project_id uuid,
  target_parent_id uuid,
  target_wbs text,
  target_name text,
  target_responsibility text default null,
  target_start_date date default null,
  target_end_date date default null,
  target_status public.work_item_status default 'not_started',
  participant_ids uuid[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  next_sort integer;
begin
  if not public.is_manager() then
    raise exception 'Chỉ sếp được thêm hạng mục hoặc công việc';
  end if;
  if nullif(trim(target_name), '') is null then
    raise exception 'Tên hạng mục/công việc không được để trống';
  end if;
  if target_start_date is not null and target_end_date is not null and target_end_date < target_start_date then
    raise exception 'Ngày kết thúc phải từ ngày bắt đầu trở đi';
  end if;
  if target_parent_id is not null and not exists (
    select 1 from public.work_items where id = target_parent_id and project_id = target_project_id
  ) then
    raise exception 'Hạng mục cha không thuộc dự án này';
  end if;

  perform pg_advisory_xact_lock(hashtext(target_project_id::text));
  select coalesce(max(sort_order), -1) + 1 into next_sort
  from public.work_items where project_id = target_project_id;

  insert into public.work_items (
    project_id, parent_id, wbs, name, source_responsibility_text,
    start_date, end_date, status, sort_order
  ) values (
    target_project_id, target_parent_id, trim(target_wbs), trim(target_name),
    nullif(trim(target_responsibility), ''), target_start_date, target_end_date,
    target_status, next_sort
  ) returning id into new_id;

  insert into public.work_item_participants (work_item_id, user_id)
  select new_id, participant_id
  from unnest(coalesce(participant_ids, '{}'::uuid[])) as participant_id;

  return new_id;
end;
$$;

grant execute on function public.create_work_item(uuid, uuid, text, text, text, date, date, public.work_item_status, uuid[]) to authenticated;
revoke execute on function public.create_work_item(uuid, uuid, text, text, text, date, date, public.work_item_status, uuid[]) from public, anon;


-- ==========================================
-- Migration: 202609090009_project_soft_delete_and_atomic_work_item_update.sql
-- ==========================================
alter table public.projects
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references public.profiles(id);

comment on column public.projects.deleted_at is 'Thời điểm dự án bị xóa mềm; null nghĩa là đang sử dụng.';
comment on column public.projects.deleted_by is 'Người thực hiện xóa mềm dự án.';

-- Chuyển dữ liệu từng dùng trạng thái archived sang cơ chế xóa mềm mới.
update public.projects
set deleted_at = coalesce(deleted_at, updated_at),
    deleted_by = coalesce(deleted_by, created_by),
    status = 'active'
where status = 'archived';

create or replace function public.set_project_deleted(
  target_project_id uuid,
  deleted boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_manager() then
    raise exception 'Chỉ sếp được xóa hoặc khôi phục dự án';
  end if;

  update public.projects
  set deleted_at = case when deleted then now() else null end,
      deleted_by = case when deleted then auth.uid() else null end
  where id = target_project_id;

  if not found then
    raise exception 'Không tìm thấy dự án';
  end if;
end;
$$;

create or replace function public.update_work_item_details(
  target_work_item_id uuid,
  expected_version integer,
  target_name text,
  target_responsibility text,
  target_start_date date,
  target_end_date date,
  target_status public.work_item_status,
  participant_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  next_version integer;
begin
  if not public.is_manager() then
    raise exception 'Chỉ sếp được sửa thông tin và phân công công việc';
  end if;
  if nullif(trim(target_name), '') is null then
    raise exception 'Tên hạng mục/công việc không được để trống';
  end if;
  if target_start_date is not null and target_end_date is not null and target_end_date < target_start_date then
    raise exception 'Ngày kết thúc phải từ ngày bắt đầu trở đi';
  end if;

  update public.work_items
  set name = trim(target_name),
      source_responsibility_text = nullif(trim(target_responsibility), ''),
      start_date = target_start_date,
      end_date = target_end_date,
      status = target_status,
      version = version + 1
  where id = target_work_item_id and version = expected_version
  returning version into next_version;

  if next_version is null then
    raise exception 'Công việc vừa được người khác cập nhật. Hãy tải lại rồi thử lại.';
  end if;

  delete from public.work_item_participants where work_item_id = target_work_item_id;
  insert into public.work_item_participants (work_item_id, user_id)
  select target_work_item_id, participant_id
  from unnest(coalesce(participant_ids, '{}'::uuid[])) as participant_id;

  return next_version;
end;
$$;

grant execute on function public.set_project_deleted(uuid, boolean) to authenticated;
revoke execute on function public.set_project_deleted(uuid, boolean) from public, anon;
grant execute on function public.update_work_item_details(uuid, integer, text, text, date, date, public.work_item_status, uuid[]) to authenticated;
revoke execute on function public.update_work_item_details(uuid, integer, text, text, date, date, public.work_item_status, uuid[]) from public, anon;

-- Xóa mềm phải được thực thi ở database, không chỉ ẩn bằng giao diện.
drop policy if exists projects_read on public.projects;
create policy projects_read on public.projects for select to authenticated
using (deleted_at is null or public.is_manager());

drop policy if exists work_items_read on public.work_items;
create policy work_items_read on public.work_items for select to authenticated
using (public.is_manager() or exists (
  select 1 from public.projects project
  where project.id = work_items.project_id and project.deleted_at is null
));

drop policy if exists participants_read on public.work_item_participants;
create policy participants_read on public.work_item_participants for select to authenticated
using (public.is_manager() or exists (
  select 1 from public.work_items item join public.projects project on project.id = item.project_id
  where item.id = work_item_participants.work_item_id and project.deleted_at is null
));

drop policy if exists progress_updates_read on public.progress_updates;
create policy progress_updates_read on public.progress_updates for select to authenticated
using (public.is_manager() or exists (
  select 1 from public.work_items item join public.projects project on project.id = item.project_id
  where item.id = progress_updates.work_item_id and project.deleted_at is null
));

drop policy if exists completion_requests_read on public.completion_requests;
create policy completion_requests_read on public.completion_requests for select to authenticated
using (public.is_manager() or exists (
  select 1 from public.work_items item join public.projects project on project.id = item.project_id
  where item.id = completion_requests.work_item_id and project.deleted_at is null
));

drop policy if exists milestones_read on public.milestones;
create policy milestones_read on public.milestones for select to authenticated
using (public.is_manager() or exists (
  select 1 from public.projects project
  where project.id = milestones.project_id and project.deleted_at is null
));

drop policy if exists attachments_read on public.attachments;
create policy attachments_read on public.attachments for select to authenticated
using (public.is_manager() or exists (
  select 1 from public.work_items item join public.projects project on project.id = item.project_id
  where item.id = attachments.work_item_id and project.deleted_at is null
));


-- ==========================================
-- Migration: 202609090010_decouple_departments_from_users.sql
-- ==========================================
-- Phòng ban là danh mục đơn vị tham gia công việc, không phải thuộc tính hồ sơ người dùng.
alter table public.profiles drop column if exists department_id;


-- ==========================================
-- Migration: 202609090011_structured_departments_and_activity_reads.sql
-- ==========================================
begin;

alter table public.work_items
  add column if not exists lead_department_id uuid references public.departments(id);

create index if not exists work_items_lead_department_idx
  on public.work_items(lead_department_id);

create table if not exists public.work_item_coordinating_departments (
  work_item_id uuid not null references public.work_items(id) on delete cascade,
  department_id uuid not null references public.departments(id),
  created_at timestamptz not null default now(),
  primary key (work_item_id, department_id)
);

create index if not exists work_item_coordinating_departments_department_idx
  on public.work_item_coordinating_departments(department_id);

create table if not exists public.work_item_activity_reads (
  work_item_id uuid not null references public.work_items(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  last_seen_at timestamptz not null default now(),
  primary key (work_item_id, user_id)
);

create index if not exists work_item_activity_reads_user_idx
  on public.work_item_activity_reads(user_id);

create or replace function public.resolve_department_reference(reference_text text)
returns uuid
language sql
stable
set search_path = public
as $$
  select candidate.id
  from (
    select department.id, 0 as priority
    from public.departments department
    where upper(trim(reference_text)) in (upper(department.code), upper(department.name))
    union all
    select alias.department_id, 1 as priority
    from public.department_aliases alias
    where upper(trim(reference_text)) = upper(alias.alias)
  ) candidate
  order by candidate.priority
  limit 1;
$$;

-- Tách dữ liệu Excel cũ: phần đầu là chủ trì, các phần sau dấu / hoặc dấu phẩy là phối hợp.
update public.work_items item
set lead_department_id = public.resolve_department_reference(
  trim(split_part(split_part(item.source_responsibility_text, '/', 1), ',', 1))
)
where item.lead_department_id is null
  and nullif(trim(item.source_responsibility_text), '') is not null;

insert into public.work_item_coordinating_departments(work_item_id, department_id)
select item.id, public.resolve_department_reference(token.value)
from public.work_items item
cross join lateral regexp_split_to_table(item.source_responsibility_text, '\s*[/,]\s*') with ordinality token(value, position)
where token.position > 1
  and public.resolve_department_reference(token.value) is not null
  and public.resolve_department_reference(token.value) is distinct from item.lead_department_id
on conflict do nothing;

alter table public.work_item_coordinating_departments enable row level security;
alter table public.work_item_activity_reads enable row level security;

grant select on public.work_item_coordinating_departments to authenticated;
grant all on public.work_item_coordinating_departments to authenticated;
grant select, insert, update on public.work_item_activity_reads to authenticated;

create policy coordinating_departments_read on public.work_item_coordinating_departments
for select to authenticated using (true);

create policy coordinating_departments_manage_manager on public.work_item_coordinating_departments
for all to authenticated using (public.is_manager()) with check (public.is_manager());

create policy activity_reads_read_own on public.work_item_activity_reads
for select to authenticated using (user_id = auth.uid());

create policy activity_reads_insert_own on public.work_item_activity_reads
for insert to authenticated with check (user_id = auth.uid());

create policy activity_reads_update_own on public.work_item_activity_reads
for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop function if exists public.create_work_item(uuid, uuid, text, text, text, date, date, public.work_item_status, uuid[]);

create function public.create_work_item(
  target_project_id uuid,
  target_parent_id uuid,
  target_wbs text,
  target_name text,
  target_lead_department_id uuid default null,
  coordinating_department_ids uuid[] default '{}',
  target_start_date date default null,
  target_end_date date default null,
  target_status public.work_item_status default 'not_started',
  participant_ids uuid[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  next_sort integer;
  responsibility_text text;
begin
  if not public.is_manager() then raise exception 'Chỉ sếp được thêm hạng mục hoặc công việc'; end if;
  if nullif(trim(target_name), '') is null then raise exception 'Tên hạng mục/công việc không được để trống'; end if;
  if target_start_date is not null and target_end_date is not null and target_end_date < target_start_date then raise exception 'Ngày kết thúc phải từ ngày bắt đầu trở đi'; end if;
  if target_parent_id is not null and not exists (select 1 from public.work_items where id = target_parent_id and project_id = target_project_id) then raise exception 'Hạng mục cha không thuộc dự án này'; end if;
  if target_lead_department_id is not null and not exists (select 1 from public.departments where id = target_lead_department_id and active) then raise exception 'Đơn vị chủ trì không hợp lệ'; end if;

  perform pg_advisory_xact_lock(hashtext(target_project_id::text));
  select coalesce(max(sort_order), -1) + 1 into next_sort from public.work_items where project_id = target_project_id;
  select concat_ws(' / ', lead.code, nullif(coordinators.codes, '')) into responsibility_text
  from (select code from public.departments where id = target_lead_department_id) lead
  full join (select string_agg(department.code, ', ' order by department.sort_order) as codes from public.departments department where department.id = any(coalesce(coordinating_department_ids, '{}'::uuid[])) and department.id is distinct from target_lead_department_id) coordinators on true;

  insert into public.work_items(project_id, parent_id, wbs, name, source_responsibility_text, lead_department_id, start_date, end_date, status, sort_order)
  values (target_project_id, target_parent_id, trim(target_wbs), trim(target_name), nullif(responsibility_text, ''), target_lead_department_id, target_start_date, target_end_date, target_status, next_sort)
  returning id into new_id;

  insert into public.work_item_coordinating_departments(work_item_id, department_id)
  select new_id, department_id from unnest(coalesce(coordinating_department_ids, '{}'::uuid[])) department_id
  where department_id is distinct from target_lead_department_id;

  insert into public.work_item_participants(work_item_id, user_id)
  select new_id, participant_id from unnest(coalesce(participant_ids, '{}'::uuid[])) participant_id;
  return new_id;
end;
$$;

grant execute on function public.create_work_item(uuid, uuid, text, text, uuid, uuid[], date, date, public.work_item_status, uuid[]) to authenticated;
revoke execute on function public.create_work_item(uuid, uuid, text, text, uuid, uuid[], date, date, public.work_item_status, uuid[]) from public, anon;

drop function if exists public.update_work_item_details(uuid, integer, text, text, date, date, public.work_item_status, uuid[]);

create function public.update_work_item_details(
  target_work_item_id uuid,
  expected_version integer,
  target_name text,
  target_lead_department_id uuid,
  coordinating_department_ids uuid[],
  target_start_date date,
  target_end_date date,
  target_status public.work_item_status,
  participant_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  next_version integer;
  responsibility_text text;
begin
  if not public.is_manager() then raise exception 'Chỉ sếp được sửa thông tin và phân công công việc'; end if;
  if nullif(trim(target_name), '') is null then raise exception 'Tên hạng mục/công việc không được để trống'; end if;
  if target_start_date is not null and target_end_date is not null and target_end_date < target_start_date then raise exception 'Ngày kết thúc phải từ ngày bắt đầu trở đi'; end if;
  if target_lead_department_id is not null and not exists (select 1 from public.departments where id = target_lead_department_id and active) then raise exception 'Đơn vị chủ trì không hợp lệ'; end if;

  select concat_ws(' / ', lead.code, nullif(coordinators.codes, '')) into responsibility_text
  from (select code from public.departments where id = target_lead_department_id) lead
  full join (select string_agg(department.code, ', ' order by department.sort_order) as codes from public.departments department where department.id = any(coalesce(coordinating_department_ids, '{}'::uuid[])) and department.id is distinct from target_lead_department_id) coordinators on true;

  update public.work_items
  set name = trim(target_name), source_responsibility_text = nullif(responsibility_text, ''), lead_department_id = target_lead_department_id,
      start_date = target_start_date, end_date = target_end_date, status = target_status, version = version + 1
  where id = target_work_item_id and version = expected_version
  returning version into next_version;
  if next_version is null then raise exception 'Công việc vừa được người khác cập nhật. Hãy tải lại rồi thử lại.'; end if;

  delete from public.work_item_coordinating_departments where work_item_id = target_work_item_id;
  insert into public.work_item_coordinating_departments(work_item_id, department_id)
  select target_work_item_id, department_id from unnest(coalesce(coordinating_department_ids, '{}'::uuid[])) department_id
  where department_id is distinct from target_lead_department_id;

  delete from public.work_item_participants where work_item_id = target_work_item_id;
  insert into public.work_item_participants(work_item_id, user_id)
  select target_work_item_id, participant_id from unnest(coalesce(participant_ids, '{}'::uuid[])) participant_id;
  return next_version;
end;
$$;

grant execute on function public.update_work_item_details(uuid, integer, text, uuid, uuid[], date, date, public.work_item_status, uuid[]) to authenticated;
revoke execute on function public.update_work_item_details(uuid, integer, text, uuid, uuid[], date, date, public.work_item_status, uuid[]) from public, anon;

create or replace function public.import_project_plan(target_project_id uuid, plan_items jsonb)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  item jsonb;
  new_id uuid;
  parent_uuid uuid;
  id_map jsonb := '{}'::jsonb;
  inserted_count integer := 0;
  responsibility text;
  lead_id uuid;
begin
  if not public.is_manager() then raise exception 'Chỉ sếp được nạp tiến độ'; end if;
  if jsonb_typeof(plan_items) <> 'array' or jsonb_array_length(plan_items) = 0 then raise exception 'Không có dữ liệu hợp lệ để nạp'; end if;
  delete from public.work_items where project_id = target_project_id;

  for item in select value from jsonb_array_elements(plan_items) loop
    if nullif(trim(item->>'name'), '') is null then raise exception 'Tên hạng mục/công việc không được để trống'; end if;
    parent_uuid := null;
    if nullif(item->>'parent_client_id', '') is not null then
      parent_uuid := nullif(id_map->>(item->>'parent_client_id'), '')::uuid;
      if parent_uuid is null then raise exception 'Cấu trúc hạng mục không hợp lệ'; end if;
    end if;
    responsibility := nullif(trim(item->>'responsibility'), '');
    lead_id := public.resolve_department_reference(trim(split_part(split_part(responsibility, '/', 1), ',', 1)));

    insert into public.work_items(project_id, parent_id, wbs, name, source_responsibility_text, lead_department_id, start_date, end_date, status, sort_order)
    values (target_project_id, parent_uuid, item->>'wbs', trim(item->>'name'), responsibility, lead_id, nullif(item->>'start_date', '')::date, nullif(item->>'end_date', '')::date, 'not_started', (item->>'sort_order')::integer)
    returning id into new_id;

    insert into public.work_item_coordinating_departments(work_item_id, department_id)
    select new_id, public.resolve_department_reference(token.value)
    from regexp_split_to_table(responsibility, '\s*[/,]\s*') with ordinality token(value, position)
    where token.position > 1 and public.resolve_department_reference(token.value) is not null and public.resolve_department_reference(token.value) is distinct from lead_id
    on conflict do nothing;

    id_map := id_map || jsonb_build_object(item->>'client_id', new_id::text);
    inserted_count := inserted_count + 1;
  end loop;
  return inserted_count;
end;
$$;

grant execute on function public.import_project_plan(uuid, jsonb) to authenticated;
revoke execute on function public.resolve_department_reference(text) from public, anon;
grant execute on function public.resolve_department_reference(text) to authenticated;

commit;


-- ==========================================
-- Migration: 202609090012_user_account_management.sql
-- ==========================================
alter table public.profiles
  add constraint profiles_full_name_not_blank
  check (length(trim(full_name)) between 2 and 100) not valid;

alter table public.profiles validate constraint profiles_full_name_not_blank;

create or replace function public.protect_profile_account_fields()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.username <> old.username then
    raise exception 'Không được thay đổi tên tài khoản';
  end if;

  if old.username = 'admin' and (new.role <> 'manager' or not new.active) then
    raise exception 'Không được hạ quyền hoặc khóa tài khoản admin gốc';
  end if;

  if auth.uid() = old.id and (new.role <> old.role or new.active <> old.active) then
    raise exception 'Không được tự thay đổi vai trò hoặc trạng thái tài khoản';
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_protect_account_fields on public.profiles;
create trigger profiles_protect_account_fields
before update on public.profiles
for each row execute function public.protect_profile_account_fields();

drop trigger if exists profiles_audit on public.profiles;
create trigger profiles_audit
after update on public.profiles
for each row execute function public.audit_row_change();

create or replace function public.is_active_user()
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active);
$$;

create or replace function public.is_work_item_participant(target_work_item_id uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select public.is_active_user() and exists (
    select 1 from public.work_item_participants
    where work_item_id = target_work_item_id and user_id = auth.uid()
  );
$$;

drop policy if exists departments_read on public.departments;
create policy departments_read on public.departments for select to authenticated using (public.is_active_user());
drop policy if exists department_aliases_read on public.department_aliases;
create policy department_aliases_read on public.department_aliases for select to authenticated using (public.is_active_user());
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using (id = auth.uid() or public.is_active_user());

drop policy if exists projects_read on public.projects;
create policy projects_read on public.projects for select to authenticated
using (public.is_active_user() and (deleted_at is null or public.is_manager()));

drop policy if exists work_items_read on public.work_items;
create policy work_items_read on public.work_items for select to authenticated
using (public.is_active_user() and (public.is_manager() or exists (
  select 1 from public.projects project where project.id = work_items.project_id and project.deleted_at is null
)));

drop policy if exists participants_read on public.work_item_participants;
create policy participants_read on public.work_item_participants for select to authenticated
using (public.is_active_user() and (public.is_manager() or exists (
  select 1 from public.work_items item join public.projects project on project.id = item.project_id
  where item.id = work_item_participants.work_item_id and project.deleted_at is null
)));

drop policy if exists progress_updates_read on public.progress_updates;
create policy progress_updates_read on public.progress_updates for select to authenticated
using (public.is_active_user() and (public.is_manager() or exists (
  select 1 from public.work_items item join public.projects project on project.id = item.project_id
  where item.id = progress_updates.work_item_id and project.deleted_at is null
)));

drop policy if exists completion_requests_read on public.completion_requests;
create policy completion_requests_read on public.completion_requests for select to authenticated
using (public.is_active_user() and (public.is_manager() or exists (
  select 1 from public.work_items item join public.projects project on project.id = item.project_id
  where item.id = completion_requests.work_item_id and project.deleted_at is null
)));

drop policy if exists milestones_read on public.milestones;
create policy milestones_read on public.milestones for select to authenticated
using (public.is_active_user() and (public.is_manager() or exists (
  select 1 from public.projects project where project.id = milestones.project_id and project.deleted_at is null
)));

drop policy if exists attachments_read on public.attachments;
create policy attachments_read on public.attachments for select to authenticated
using (public.is_active_user() and (public.is_manager() or exists (
  select 1 from public.work_items item join public.projects project on project.id = item.project_id
  where item.id = attachments.work_item_id and project.deleted_at is null
)));

drop policy if exists coordinating_departments_read on public.work_item_coordinating_departments;
create policy coordinating_departments_read on public.work_item_coordinating_departments
for select to authenticated using (public.is_active_user());

drop policy if exists activity_reads_read_own on public.work_item_activity_reads;
create policy activity_reads_read_own on public.work_item_activity_reads
for select to authenticated using (public.is_active_user() and user_id = auth.uid());
drop policy if exists activity_reads_insert_own on public.work_item_activity_reads;
create policy activity_reads_insert_own on public.work_item_activity_reads
for insert to authenticated with check (public.is_active_user() and user_id = auth.uid());
drop policy if exists activity_reads_update_own on public.work_item_activity_reads;
create policy activity_reads_update_own on public.work_item_activity_reads
for update to authenticated using (public.is_active_user() and user_id = auth.uid())
with check (public.is_active_user() and user_id = auth.uid());

drop policy if exists evidence_read_authenticated on storage.objects;
create policy evidence_read_authenticated on storage.objects
for select to authenticated using (bucket_id = 'evidence' and public.is_active_user());


-- ==========================================
-- Migration: 202609090013_fix_completion_review.sql
-- ==========================================
create or replace function public.review_completion_request(
  target_request_id uuid,
  decision public.completion_request_status,
  manager_note text default null
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  target_work_item_id uuid;
begin
  if not public.is_manager() then
    raise exception 'Chỉ quản trị viên được duyệt công việc';
  end if;

  if decision not in ('approved', 'rejected') then
    raise exception 'Kết quả duyệt không hợp lệ';
  end if;

  if decision = 'rejected' and nullif(trim(manager_note), '') is null then
    raise exception 'Từ chối phải nhập lý do';
  end if;

  update public.completion_requests
  set status = decision,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      review_note = nullif(trim(manager_note), '')
  where id = target_request_id and status = 'pending'
  returning work_item_id into target_work_item_id;

  if target_work_item_id is null then
    raise exception 'Yêu cầu không còn ở trạng thái chờ duyệt';
  end if;

  update public.work_items
  set status = case
        when decision = 'approved' then 'completed'::public.work_item_status
        else 'in_progress'::public.work_item_status
      end,
      updated_by = auth.uid(),
      version = version + 1
  where id = target_work_item_id;
end;
$$;

grant execute on function public.review_completion_request(uuid, public.completion_request_status, text) to authenticated;
revoke execute on function public.review_completion_request(uuid, public.completion_request_status, text) from public, anon;


-- ==========================================
-- Migration: 202609100014_protect_root_admin.sql
-- ==========================================
create or replace function public.protect_profile_account_fields()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if old.username = 'admin' and new is distinct from old then
    raise exception 'Tài khoản admin gốc được bảo vệ và không thể chỉnh sửa';
  end if;

  if new.username <> old.username then
    raise exception 'Không được thay đổi tên tài khoản';
  end if;

  if auth.uid() = old.id and (new.role <> old.role or new.active <> old.active) then
    raise exception 'Không được tự thay đổi vai trò hoặc trạng thái tài khoản';
  end if;

  return new;
end;
$$;


-- ==========================================
-- Migration: 202609100015_lock_submitted_work_items_and_evidence.sql
-- ==========================================
begin;

-- Hồ sơ đã gửi duyệt phải giữ nguyên. Chỉ cho phép RPC xét duyệt chuyển
-- pending_approval -> completed hoặc pending_approval -> in_progress.
create or replace function public.protect_locked_work_item()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'completed' then
    raise exception 'Công việc đã hoàn thành và không thể chỉnh sửa hoặc xóa';
  end if;

  if old.status = 'pending_approval' then
    if tg_op = 'DELETE' then
      raise exception 'Công việc đang chờ duyệt và không thể xóa';
    end if;

    if new.status not in ('completed', 'in_progress')
      or new.project_id is distinct from old.project_id
      or new.parent_id is distinct from old.parent_id
      or new.wbs is distinct from old.wbs
      or new.name is distinct from old.name
      or new.source_responsibility_text is distinct from old.source_responsibility_text
      or new.lead_department_id is distinct from old.lead_department_id
      or new.start_date is distinct from old.start_date
      or new.end_date is distinct from old.end_date
      or new.sort_order is distinct from old.sort_order
      or new.created_by is distinct from old.created_by
      or new.created_at is distinct from old.created_at then
      raise exception 'Công việc đang chờ duyệt; chỉ được duyệt hoặc từ chối yêu cầu';
    end if;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists work_items_00_protect_locked on public.work_items;
create trigger work_items_00_protect_locked
before update or delete on public.work_items
for each row execute function public.protect_locked_work_item();

-- Khóa các quan hệ cũng là một phần thông tin của công việc.
create or replace function public.protect_locked_work_item_relation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_work_item_id uuid;
begin
  target_work_item_id := case when tg_op = 'DELETE' then old.work_item_id else new.work_item_id end;

  if exists (
    select 1
    from public.work_items item
    where item.id = target_work_item_id
      and item.status in ('pending_approval', 'completed')
  ) then
    raise exception 'Công việc đang chờ duyệt hoặc đã hoàn thành; dữ liệu đã được khóa';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists participants_00_protect_locked on public.work_item_participants;
create trigger participants_00_protect_locked
before insert or update or delete on public.work_item_participants
for each row execute function public.protect_locked_work_item_relation();

drop trigger if exists coordinating_departments_00_protect_locked on public.work_item_coordinating_departments;
create trigger coordinating_departments_00_protect_locked
before insert or update or delete on public.work_item_coordinating_departments
for each row execute function public.protect_locked_work_item_relation();

drop trigger if exists attachments_00_protect_locked on public.attachments;
create trigger attachments_00_protect_locked
before insert or update or delete on public.attachments
for each row execute function public.protect_locked_work_item_relation();

-- RLS kiểm tra trạng thái trước khi ghi metadata bằng chứng.
drop policy if exists attachments_add_participant on public.attachments;
create policy attachments_add_participant on public.attachments
for insert to authenticated
with check (
  uploaded_by = auth.uid()
  and (public.is_manager() or public.is_work_item_participant(work_item_id))
  and exists (
    select 1 from public.work_items item
    where item.id = work_item_id
      and item.status not in ('pending_approval', 'completed')
      and not exists (select 1 from public.work_items child where child.parent_id = item.id)
  )
);

drop policy if exists attachments_delete_participant on public.attachments;
create policy attachments_delete_participant on public.attachments
for delete to authenticated
using (
  (public.is_manager() or public.is_work_item_participant(work_item_id))
  and exists (
    select 1 from public.work_items item
    where item.id = work_item_id
      and item.status not in ('pending_approval', 'completed')
  )
);

-- Storage cũng phải khóa; nếu chỉ khóa bảng attachments thì vẫn có thể xóa file vật lý.
drop policy if exists evidence_upload_participant on storage.objects;
create policy evidence_upload_participant on storage.objects
for insert to authenticated
with check (
  bucket_id = 'evidence'
  and exists (
    select 1 from public.work_items item
    where item.id = ((storage.foldername(name))[1])::uuid
      and item.status not in ('pending_approval', 'completed')
      and not exists (select 1 from public.work_items child where child.parent_id = item.id)
      and (public.is_manager() or public.is_work_item_participant(item.id))
  )
);

drop policy if exists evidence_delete_participant on storage.objects;
create policy evidence_delete_participant on storage.objects
for delete to authenticated
using (
  bucket_id = 'evidence'
  and exists (
    select 1 from public.work_items item
    where item.id = ((storage.foldername(name))[1])::uuid
      and item.status not in ('pending_approval', 'completed')
      and (public.is_manager() or public.is_work_item_participant(item.id))
  )
);

commit;


-- ==========================================
-- Migration: 202609100016_preserve_unlocked_work_item_delete.sql
-- ==========================================
-- Bản 015 đã được áp dụng trước khi phát hiện nhánh DELETE cần trả OLD.
-- Giữ bản vá riêng để database đang chạy và lần dựng mới đều có cùng hành vi.
create or replace function public.protect_locked_work_item()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'completed' then
    raise exception 'Công việc đã hoàn thành và không thể chỉnh sửa hoặc xóa';
  end if;

  if old.status = 'pending_approval' then
    if tg_op = 'DELETE' then
      raise exception 'Công việc đang chờ duyệt và không thể xóa';
    end if;

    if new.status not in ('completed', 'in_progress')
      or new.project_id is distinct from old.project_id
      or new.parent_id is distinct from old.parent_id
      or new.wbs is distinct from old.wbs
      or new.name is distinct from old.name
      or new.source_responsibility_text is distinct from old.source_responsibility_text
      or new.lead_department_id is distinct from old.lead_department_id
      or new.start_date is distinct from old.start_date
      or new.end_date is distinct from old.end_date
      or new.sort_order is distinct from old.sort_order
      or new.created_by is distinct from old.created_by
      or new.created_at is distinct from old.created_at then
      raise exception 'Công việc đang chờ duyệt; chỉ được duyệt hoặc từ chối yêu cầu';
    end if;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;


-- ==========================================
-- Migration: 202609100017_safe_evidence_storage_path_policies.sql
-- ==========================================
begin;

-- Dữ liệu Storage cũ có thể dùng tên công việc làm thư mục đầu tiên.
-- Không ép phần này sang uuid vì PostgreSQL có thể đánh giá policy trên cả
-- các object cũ và làm lỗi thao tác hợp lệ với đường dẫn UUID mới.
drop policy if exists evidence_upload_participant on storage.objects;
create policy evidence_upload_participant on storage.objects
for insert to authenticated
with check (
  bucket_id = 'evidence'
  and exists (
    select 1 from public.work_items item
    where item.id::text = split_part(storage.objects.name, '/', 1)
      and item.status not in ('pending_approval', 'completed')
      and not exists (select 1 from public.work_items child where child.parent_id = item.id)
      and (public.is_manager() or public.is_work_item_participant(item.id))
  )
);

drop policy if exists evidence_delete_participant on storage.objects;
create policy evidence_delete_participant on storage.objects
for delete to authenticated
using (
  bucket_id = 'evidence'
  and exists (
    select 1 from public.work_items item
    where item.id::text = split_part(storage.objects.name, '/', 1)
      and item.status not in ('pending_approval', 'completed')
      and (public.is_manager() or public.is_work_item_participant(item.id))
  )
);

commit;


-- ==========================================
-- Migration: 202609100018_qualify_evidence_storage_object_name.sql
-- ==========================================
begin;

-- `work_items` cũng có cột name. Phải định danh đầy đủ storage.objects.name
-- để policy đọc thư mục UUID của file thay vì đọc nhầm tên công việc.
drop policy if exists evidence_upload_participant on storage.objects;
create policy evidence_upload_participant on storage.objects
for insert to authenticated
with check (
  bucket_id = 'evidence'
  and exists (
    select 1 from public.work_items item
    where item.id::text = split_part(storage.objects.name, '/', 1)
      and item.status not in ('pending_approval', 'completed')
      and not exists (select 1 from public.work_items child where child.parent_id = item.id)
      and (public.is_manager() or public.is_work_item_participant(item.id))
  )
);

drop policy if exists evidence_delete_participant on storage.objects;
create policy evidence_delete_participant on storage.objects
for delete to authenticated
using (
  bucket_id = 'evidence'
  and exists (
    select 1 from public.work_items item
    where item.id::text = split_part(storage.objects.name, '/', 1)
      and item.status not in ('pending_approval', 'completed')
      and (public.is_manager() or public.is_work_item_participant(item.id))
  )
);

commit;


-- ==========================================
-- Migration: 202609100019_grant_attachment_delete.sql
-- ==========================================
-- RLS quyết định người nào được xóa và trạng thái nào được xóa; quyền bảng là
-- điều kiện bắt buộc để câu lệnh DELETE có thể đi tới bước kiểm tra policy.
grant delete on public.attachments to authenticated;


-- ==========================================
-- Migration: 202609100020_unlock_work_items_keep_evidence_locked.sql
-- ==========================================
begin;

-- Chỉ bằng chứng đã nộp bị khóa. Công việc vẫn được sửa, phân công và thêm
-- công việc con dù đang chờ duyệt hoặc đã hoàn thành.
drop trigger if exists work_items_00_protect_locked on public.work_items;
drop trigger if exists participants_00_protect_locked on public.work_item_participants;
drop trigger if exists coordinating_departments_00_protect_locked on public.work_item_coordinating_departments;
drop function if exists public.protect_locked_work_item();

-- Không cho xóa cả công việc nếu thao tác đó sẽ xóa theo một bằng chứng đã
-- nộp. Đây là bảo vệ bằng chứng, không khóa việc sửa hoặc thêm nhánh con.
create or replace function public.protect_submitted_evidence_on_work_item_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status in ('pending_approval', 'completed')
    and exists (select 1 from public.attachments attachment where attachment.work_item_id = old.id) then
    raise exception 'Không thể xóa công việc vì có bằng chứng đã nộp đang được khóa';
  end if;
  return old;
end;
$$;

drop trigger if exists work_items_00_protect_submitted_evidence on public.work_items;
create trigger work_items_00_protect_submitted_evidence
before delete on public.work_items
for each row execute function public.protect_submitted_evidence_on_work_item_delete();

-- Nhật ký diễn biến là thông tin bổ sung, không phải tệp bằng chứng nên vẫn
-- được cập nhật ở mọi trạng thái nếu người dùng có quyền trên công việc.
drop policy if exists progress_updates_add_participant on public.progress_updates;
create policy progress_updates_add_participant on public.progress_updates
for insert to authenticated
with check (
  created_by = auth.uid()
  and (public.is_manager() or public.is_work_item_participant(work_item_id))
);

commit;


-- ==========================================
-- Migration: 202609100021_scoped_roles_and_department_visibility.sql
-- ==========================================
begin;

alter table public.profiles
  add column if not exists department_id uuid references public.departments(id),
  add column if not exists is_department_admin boolean not null default false;

create table if not exists public.project_administrators (
  project_id uuid not null references public.projects(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  assigned_by uuid not null default auth.uid() references public.profiles(id),
  assigned_at timestamptz not null default now(),
  primary key (project_id, user_id)
);

create index if not exists project_administrators_user_idx
  on public.project_administrators(user_id, project_id);

alter table public.project_administrators enable row level security;
grant select, insert, update, delete on public.project_administrators to authenticated;

create or replace function public.is_project_admin(target_project_id uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select public.is_manager() or exists (
    select 1 from public.project_administrators administrator
    join public.profiles profile on profile.id = administrator.user_id
    where administrator.project_id = target_project_id
      and administrator.user_id = auth.uid()
      and profile.active
  );
$$;

create or replace function public.can_manage_project(target_project_id uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$ select public.is_project_admin(target_project_id); $$;

create or replace function public.can_view_work_item(target_work_item_id uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  with recursive branch as (
    select child.id, child.lead_department_id
    from public.work_items child where child.id = target_work_item_id
    union all
    select child.id, child.lead_department_id
    from public.work_items child join branch parent on child.parent_id = parent.id
  ), current_profile as (
    select id, department_id from public.profiles where id = auth.uid() and active
  )
  select exists (
    select 1 from public.work_items target, current_profile profile
    where target.id = target_work_item_id
      and (
        public.is_project_admin(target.project_id)
        or exists (
          select 1 from branch item
          where item.lead_department_id = profile.department_id
            or exists (
              select 1 from public.work_item_coordinating_departments coordinator
              where coordinator.work_item_id = item.id and coordinator.department_id = profile.department_id
            )
            or exists (
              select 1 from public.work_item_participants participant
              where participant.work_item_id = item.id and participant.user_id = profile.id
            )
        )
      )
  );
$$;

create or replace function public.can_review_work_item(target_work_item_id uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1
    from public.work_items item
    join public.profiles profile on profile.id = auth.uid() and profile.active
    where item.id = target_work_item_id
      and (
        public.is_project_admin(item.project_id)
        or (profile.is_department_admin and profile.department_id = item.lead_department_id)
      )
  );
$$;

drop policy if exists project_administrators_read on public.project_administrators;
create policy project_administrators_read on public.project_administrators
for select to authenticated using (public.is_active_user());
drop policy if exists project_administrators_manage on public.project_administrators;
create policy project_administrators_manage on public.project_administrators
for all to authenticated using (public.is_manager()) with check (public.is_manager());

drop policy if exists projects_read on public.projects;
create policy projects_read on public.projects for select to authenticated using (
  public.is_active_user()
  and (deleted_at is null or public.is_manager())
  and (
    public.is_project_admin(id)
    or exists (select 1 from public.work_items item where item.project_id = projects.id and public.can_view_work_item(item.id))
  )
);

drop policy if exists work_items_read on public.work_items;
create policy work_items_read on public.work_items for select to authenticated
using (public.can_view_work_item(id));

drop policy if exists participants_read on public.work_item_participants;
create policy participants_read on public.work_item_participants for select to authenticated
using (public.can_view_work_item(work_item_id));

drop policy if exists progress_updates_read on public.progress_updates;
create policy progress_updates_read on public.progress_updates for select to authenticated
using (public.can_view_work_item(work_item_id));

drop policy if exists attachments_read on public.attachments;
create policy attachments_read on public.attachments for select to authenticated
using (public.can_view_work_item(work_item_id));

drop policy if exists completion_requests_read on public.completion_requests;
create policy completion_requests_read on public.completion_requests for select to authenticated
using (
  submitted_by = auth.uid()
  or public.can_review_work_item(work_item_id)
);

drop policy if exists milestones_read on public.milestones;
create policy milestones_read on public.milestones for select to authenticated
using (exists (select 1 from public.projects project where project.id = milestones.project_id));

drop policy if exists work_items_manage_manager on public.work_items;
create policy work_items_manage_project_admin on public.work_items for all to authenticated
using (public.can_manage_project(project_id)) with check (public.can_manage_project(project_id));

drop policy if exists participants_manage_manager on public.work_item_participants;
create policy participants_manage_project_admin on public.work_item_participants for all to authenticated
using (exists (select 1 from public.work_items item where item.id = work_item_id and public.can_manage_project(item.project_id)))
with check (exists (select 1 from public.work_items item where item.id = work_item_id and public.can_manage_project(item.project_id)));

drop policy if exists coordinating_departments_manage_manager on public.work_item_coordinating_departments;
create policy coordinating_departments_manage_project_admin on public.work_item_coordinating_departments for all to authenticated
using (exists (select 1 from public.work_items item where item.id = work_item_id and public.can_manage_project(item.project_id)))
with check (exists (select 1 from public.work_items item where item.id = work_item_id and public.can_manage_project(item.project_id)));

drop policy if exists milestones_manage_manager on public.milestones;
create policy milestones_manage_project_admin on public.milestones for all to authenticated
using (public.can_manage_project(project_id)) with check (public.can_manage_project(project_id));

drop policy if exists projects_manage_project_admin on public.projects;
create policy projects_manage_project_admin on public.projects for update to authenticated
using (public.can_manage_project(id)) with check (public.can_manage_project(id));

drop policy if exists progress_updates_add_participant on public.progress_updates;
create policy progress_updates_add_participant on public.progress_updates for insert to authenticated with check (
  created_by = auth.uid()
  and (
    public.is_work_item_participant(work_item_id)
    or exists (select 1 from public.work_items item where item.id = work_item_id and public.can_manage_project(item.project_id))
  )
);

drop policy if exists attachments_add_participant on public.attachments;
create policy attachments_add_participant on public.attachments for insert to authenticated with check (
  uploaded_by = auth.uid()
  and (
    public.is_work_item_participant(work_item_id)
    or exists (select 1 from public.work_items item where item.id = work_item_id and public.can_manage_project(item.project_id))
  )
  and not exists (select 1 from public.attachments existing where existing.work_item_id = attachments.work_item_id)
  and exists (select 1 from public.work_items item where item.id = work_item_id and item.status not in ('pending_approval', 'completed'))
);

drop policy if exists attachments_delete_participant on public.attachments;
create policy attachments_delete_participant on public.attachments for delete to authenticated using (
  exists (
    select 1 from public.work_items item
    where item.id = work_item_id
      and item.status not in ('pending_approval', 'completed')
      and (public.is_work_item_participant(item.id) or public.can_manage_project(item.project_id))
  )
);

drop policy if exists evidence_upload_participant on storage.objects;
create policy evidence_upload_participant on storage.objects for insert to authenticated with check (
  bucket_id = 'evidence'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and (
    public.is_work_item_participant(((storage.foldername(name))[1])::uuid)
    or exists (
      select 1 from public.work_items item
      where item.id = ((storage.foldername(name))[1])::uuid and public.can_manage_project(item.project_id)
    )
  )
  and exists (
    select 1 from public.work_items item
    where item.id = ((storage.foldername(name))[1])::uuid and item.status not in ('pending_approval', 'completed')
  )
);

drop policy if exists evidence_delete_participant on storage.objects;
create policy evidence_delete_participant on storage.objects for delete to authenticated using (
  bucket_id = 'evidence'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and exists (
    select 1 from public.work_items item
    where item.id = ((storage.foldername(name))[1])::uuid
      and item.status not in ('pending_approval', 'completed')
      and (public.is_work_item_participant(item.id) or public.can_manage_project(item.project_id))
  )
);

-- Các RPC cũ là SECURITY DEFINER nên phải thay chính điều kiện quyền bên trong,
-- không chỉ dựa vào RLS của bảng.
do $$
declare
  definition text;
begin
  select pg_get_functiondef('public.set_project_deleted(uuid,boolean)'::regprocedure) into definition;
  definition := regexp_replace(definition, 'if not public\.is_manager\(\) then', 'if not public.can_manage_project(target_project_id) then', 'i');
  execute definition;

  select pg_get_functiondef('public.create_work_item(uuid,uuid,text,text,uuid,uuid[],date,date,public.work_item_status,uuid[])'::regprocedure) into definition;
  definition := regexp_replace(definition, 'if not public\.is_manager\(\) then', 'if not public.can_manage_project(target_project_id) then', 'i');
  execute definition;

  select pg_get_functiondef('public.update_work_item_details(uuid,integer,text,uuid,uuid[],date,date,public.work_item_status,uuid[])'::regprocedure) into definition;
  definition := regexp_replace(
    definition,
    'if not public\.is_manager\(\) then',
    'if not exists (select 1 from public.work_items scoped_item where scoped_item.id = target_work_item_id and public.can_manage_project(scoped_item.project_id)) then',
    'i'
  );
  execute definition;

  select pg_get_functiondef('public.import_project_plan(uuid,jsonb)'::regprocedure) into definition;
  definition := regexp_replace(definition, 'if not public\.is_manager\(\) then', 'if not public.can_manage_project(target_project_id) then', 'i');
  execute definition;

  select pg_get_functiondef('public.save_project_milestones(uuid,jsonb)'::regprocedure) into definition;
  definition := regexp_replace(definition, 'if not public\.is_manager\(\) then', 'if not public.can_manage_project(target_project_id) then', 'i');
  execute definition;
end;
$$;

create or replace function public.submit_work_item_completion(target_work_item_id uuid, submission_note text default null)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  request_id uuid;
  next_attempt integer;
  target_project_id uuid;
  direct_completion boolean;
begin
  select project_id into target_project_id from public.work_items where id = target_work_item_id;
  if target_project_id is null then raise exception 'Không tìm thấy công việc'; end if;
  if exists (select 1 from public.work_items where parent_id = target_work_item_id) then raise exception 'Chỉ công việc cuối nhánh mới được gửi hoàn thành'; end if;
  if not public.is_work_item_participant(target_work_item_id) and not public.can_manage_project(target_project_id) then
    raise exception 'Bạn không được phân công công việc này';
  end if;
  if (select count(*) from public.attachments where work_item_id = target_work_item_id) <> 1 then
    raise exception 'Cần đúng 1 tài liệu bằng chứng trước khi gửi hoàn thành';
  end if;
  if exists (select 1 from public.completion_requests where work_item_id = target_work_item_id and status = 'pending') then
    raise exception 'Công việc đã có yêu cầu chờ duyệt';
  end if;

  direct_completion := public.can_manage_project(target_project_id);
  select coalesce(max(attempt_no), 0) + 1 into next_attempt from public.completion_requests where work_item_id = target_work_item_id;
  insert into public.completion_requests (
    work_item_id, attempt_no, note, status, submitted_by, reviewed_by, reviewed_at, review_note
  ) values (
    target_work_item_id, next_attempt, nullif(trim(submission_note), ''),
    case when direct_completion then 'approved'::public.completion_request_status else 'pending'::public.completion_request_status end,
    auth.uid(), case when direct_completion then auth.uid() else null end,
    case when direct_completion then now() else null end,
    case when direct_completion then 'Quản trị dự án tự xác nhận sau khi nộp bằng chứng' else null end
  ) returning id into request_id;

  update public.work_items
  set status = case when direct_completion then 'completed'::public.work_item_status else 'pending_approval'::public.work_item_status end,
      updated_by = auth.uid(), version = version + 1
  where id = target_work_item_id and status <> 'completed';
  if not found then raise exception 'Không thể gửi công việc đã hoàn thành'; end if;
  return request_id;
end;
$$;

create or replace function public.review_completion_request(
  target_request_id uuid,
  decision public.completion_request_status,
  manager_note text default null
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  target_work_item_id uuid;
  request_submitter uuid;
begin
  if decision not in ('approved', 'rejected') then raise exception 'Kết quả duyệt không hợp lệ'; end if;
  if decision = 'rejected' and nullif(trim(manager_note), '') is null then raise exception 'Từ chối phải nhập lý do'; end if;

  select work_item_id, submitted_by into target_work_item_id, request_submitter
  from public.completion_requests where id = target_request_id and status = 'pending';
  if target_work_item_id is null then raise exception 'Yêu cầu không còn ở trạng thái chờ duyệt'; end if;
  if request_submitter = auth.uid() then raise exception 'Người gửi không được tự duyệt yêu cầu của mình'; end if;
  if not public.can_review_work_item(target_work_item_id) then raise exception 'Bạn không có quyền duyệt công việc này'; end if;

  update public.completion_requests
  set status = decision, reviewed_by = auth.uid(), reviewed_at = now(), review_note = nullif(trim(manager_note), '')
  where id = target_request_id and status = 'pending';
  if not found then raise exception 'Yêu cầu vừa được người khác xử lý'; end if;

  update public.work_items
  set status = case when decision = 'approved' then 'completed'::public.work_item_status else 'in_progress'::public.work_item_status end,
      updated_by = auth.uid(), version = version + 1
  where id = target_work_item_id;
end;
$$;

grant execute on function public.is_project_admin(uuid), public.can_manage_project(uuid), public.can_view_work_item(uuid), public.can_review_work_item(uuid) to authenticated;
grant execute on function public.submit_work_item_completion(uuid, text), public.review_completion_request(uuid, public.completion_request_status, text) to authenticated;

commit;


-- ==========================================
-- Migration: 202609100022_optimize_scoped_visibility.sql
-- ==========================================
begin;

create or replace function public.can_view_project(target_project_id uuid)
returns boolean
language plpgsql
stable
security definer set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  current_department_id uuid;
begin
  if not public.is_active_user() then return false; end if;
  if public.is_project_admin(target_project_id) then return true; end if;
  select department_id into current_department_id from public.profiles where id = current_user_id;

  return exists (
    select 1 from public.work_items item
    where item.project_id = target_project_id
      and (
        item.lead_department_id = current_department_id
        or exists (
          select 1 from public.work_item_coordinating_departments coordinator
          where coordinator.work_item_id = item.id and coordinator.department_id = current_department_id
        )
        or exists (
          select 1 from public.work_item_participants participant
          where participant.work_item_id = item.id and participant.user_id = current_user_id
        )
      )
  );
end;
$$;

create or replace function public.can_view_work_item(target_work_item_id uuid)
returns boolean
language plpgsql
stable
security definer set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  current_department_id uuid;
  target_project_id uuid;
begin
  if not public.is_active_user() then return false; end if;
  select project_id into target_project_id from public.work_items where id = target_work_item_id;
  if target_project_id is null then return false; end if;
  if public.is_project_admin(target_project_id) then return true; end if;
  select department_id into current_department_id from public.profiles where id = current_user_id;

  return exists (
    with recursive branch as (
      select child.id, child.lead_department_id
      from public.work_items child where child.id = target_work_item_id
      union all
      select child.id, child.lead_department_id
      from public.work_items child join branch parent on child.parent_id = parent.id
    )
    select 1 from branch item
    where item.lead_department_id = current_department_id
      or exists (
        select 1 from public.work_item_coordinating_departments coordinator
        where coordinator.work_item_id = item.id and coordinator.department_id = current_department_id
      )
      or exists (
        select 1 from public.work_item_participants participant
        where participant.work_item_id = item.id and participant.user_id = current_user_id
      )
  );
end;
$$;

drop policy if exists projects_read on public.projects;
create policy projects_read on public.projects for select to authenticated using (
  (deleted_at is null or public.is_manager()) and public.can_view_project(id)
);

grant execute on function public.can_view_project(uuid), public.can_view_work_item(uuid) to authenticated;

commit;


-- ==========================================
-- Migration: 202609100023_fast_system_admin_reads.sql
-- ==========================================
begin;

drop policy if exists work_items_read on public.work_items;
create policy work_items_read on public.work_items for select to authenticated
using (public.is_manager() or public.can_view_work_item(id));

drop policy if exists participants_read on public.work_item_participants;
create policy participants_read on public.work_item_participants for select to authenticated
using (public.is_manager() or public.can_view_work_item(work_item_id));

drop policy if exists progress_updates_read on public.progress_updates;
create policy progress_updates_read on public.progress_updates for select to authenticated
using (public.is_manager() or public.can_view_work_item(work_item_id));

drop policy if exists attachments_read on public.attachments;
create policy attachments_read on public.attachments for select to authenticated
using (public.is_manager() or public.can_view_work_item(work_item_id));

drop policy if exists completion_requests_read on public.completion_requests;
create policy completion_requests_read on public.completion_requests for select to authenticated
using (public.is_manager() or submitted_by = auth.uid() or public.can_review_work_item(work_item_id));

commit;


-- ==========================================
-- Migration: 202609100024_department_admin_work_item_management.sql
-- ==========================================
begin;

-- Quản trị phòng/ban sở hữu một nhánh khi chính công việc hoặc một mục cha
-- trong nhánh có đơn vị chủ trì trùng với phòng/ban của họ.
create or replace function public.department_admin_owns_work_branch(target_work_item_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with recursive lineage as (
    select item.id, item.parent_id, item.lead_department_id
    from public.work_items item
    where item.id = target_work_item_id
    union all
    select parent.id, parent.parent_id, parent.lead_department_id
    from public.work_items parent
    join lineage child on child.parent_id = parent.id
  )
  select exists (
    select 1
    from public.profiles profile
    join lineage item on item.lead_department_id = profile.department_id
    where profile.id = auth.uid()
      and profile.active
      and profile.is_department_admin
      and profile.department_id is not null
  );
$$;

create or replace function public.can_manage_work_item_structure(target_work_item_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.work_items item
    where item.id = target_work_item_id
      and (
        public.can_manage_project(item.project_id)
        or (
          item.parent_id is not null
          and public.department_admin_owns_work_branch(item.id)
        )
      )
  );
$$;

create or replace function public.can_create_child_work_item(target_project_id uuid, target_parent_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_manage_project(target_project_id)
    or (
      target_parent_id is not null
      and exists (
        select 1
        from public.work_items parent
        where parent.id = target_parent_id
          and parent.project_id = target_project_id
          and public.department_admin_owns_work_branch(parent.id)
      )
    );
$$;

-- Xóa đi qua RLS vì frontend xóa trực tiếp trên bảng work_items.
drop policy if exists work_items_delete_department_admin on public.work_items;
create policy work_items_delete_department_admin on public.work_items
for delete to authenticated
using (public.can_manage_work_item_structure(id));

-- Hai RPC này là SECURITY DEFINER, do đó phải kiểm tra quyền ngay trong hàm.
do $$
declare
  definition text;
  updated_definition text;
begin
  select pg_get_functiondef('public.create_work_item(uuid,uuid,text,text,uuid,uuid[],date,date,public.work_item_status,uuid[])'::regprocedure)
  into definition;
  updated_definition := replace(
    definition,
    'if not public.can_manage_project(target_project_id) then',
    'if not public.can_create_child_work_item(target_project_id, target_parent_id) then'
  );
  if updated_definition = definition then
    raise exception 'Không tìm thấy điều kiện quyền trong create_work_item';
  end if;
  execute updated_definition;

  select pg_get_functiondef('public.update_work_item_details(uuid,integer,text,uuid,uuid[],date,date,public.work_item_status,uuid[])'::regprocedure)
  into definition;
  updated_definition := replace(
    definition,
    'if not exists (select 1 from public.work_items scoped_item where scoped_item.id = target_work_item_id and public.can_manage_project(scoped_item.project_id)) then',
    'if not public.can_manage_work_item_structure(target_work_item_id) then'
  );
  if updated_definition = definition then
    raise exception 'Không tìm thấy điều kiện quyền trong update_work_item_details';
  end if;
  execute updated_definition;
end;
$$;

grant execute on function public.department_admin_owns_work_branch(uuid) to authenticated;
grant execute on function public.can_manage_work_item_structure(uuid) to authenticated;
grant execute on function public.can_create_child_work_item(uuid, uuid) to authenticated;

commit;


-- ==========================================
-- Migration: 202609110001_qualify_scoped_evidence_storage_path.sql
-- ==========================================
begin;

-- `work_items` cũng có cột `name`. Luôn định danh `storage.objects.name`
-- để policy lấy đúng thư mục UUID ở đầu đường dẫn tệp bằng chứng.
drop policy if exists evidence_upload_participant on storage.objects;
create policy evidence_upload_participant on storage.objects
for insert to authenticated
with check (
  bucket_id = 'evidence'
  and split_part(storage.objects.name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and (
    public.is_work_item_participant(split_part(storage.objects.name, '/', 1)::uuid)
    or exists (
      select 1
      from public.work_items item
      where item.id = split_part(storage.objects.name, '/', 1)::uuid
        and public.can_manage_project(item.project_id)
    )
  )
  and exists (
    select 1
    from public.work_items item
    where item.id = split_part(storage.objects.name, '/', 1)::uuid
      and item.status not in ('pending_approval', 'completed')
      and not exists (
        select 1 from public.work_items child where child.parent_id = item.id
      )
  )
);

drop policy if exists evidence_delete_participant on storage.objects;
create policy evidence_delete_participant on storage.objects
for delete to authenticated
using (
  bucket_id = 'evidence'
  and split_part(storage.objects.name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and exists (
    select 1
    from public.work_items item
    where item.id = split_part(storage.objects.name, '/', 1)::uuid
      and item.status not in ('pending_approval', 'completed')
      and (
        public.is_work_item_participant(item.id)
        or public.can_manage_project(item.project_id)
      )
  )
);

commit;


-- ==========================================
-- Migration: 202609110002_restrict_participants_to_work_item_departments.sql
-- ==========================================
begin;

create or replace function public.validate_work_item_participant_department()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.profiles profile
    join public.work_items item on item.id = new.work_item_id
    where profile.id = new.user_id
      and profile.active
      and profile.department_id is not null
      and (
        profile.department_id = item.lead_department_id
        or exists (
          select 1
          from public.work_item_coordinating_departments coordinator
          where coordinator.work_item_id = item.id
            and coordinator.department_id = profile.department_id
        )
      )
  ) then
    raise exception 'Người tham gia phải thuộc đơn vị chủ trì hoặc đơn vị phối hợp của công việc';
  end if;

  return new;
end;
$$;

drop trigger if exists participants_10_validate_department on public.work_item_participants;
create trigger participants_10_validate_department
before insert or update on public.work_item_participants
for each row execute function public.validate_work_item_participant_department();

revoke execute on function public.validate_work_item_participant_department() from public, anon, authenticated;

commit;


-- ==========================================
-- Migration: 202609110003_lead_department_admin_direct_completion.sql
-- ==========================================
begin;

create or replace function public.submit_work_item_completion(target_work_item_id uuid, submission_note text default null)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  request_id uuid;
  next_attempt integer;
  target_project_id uuid;
  direct_completion boolean;
  direct_completion_reason text;
begin
  select project_id into target_project_id from public.work_items where id = target_work_item_id;
  if target_project_id is null then raise exception 'Không tìm thấy công việc'; end if;
  if exists (select 1 from public.work_items where parent_id = target_work_item_id) then raise exception 'Chỉ công việc cuối nhánh mới được gửi hoàn thành'; end if;
  if not public.is_work_item_participant(target_work_item_id) and not public.can_manage_project(target_project_id) then
    raise exception 'Bạn không được phân công công việc này';
  end if;
  if (select count(*) from public.attachments where work_item_id = target_work_item_id) <> 1 then
    raise exception 'Cần đúng 1 tài liệu bằng chứng trước khi gửi hoàn thành';
  end if;
  if exists (select 1 from public.completion_requests where work_item_id = target_work_item_id and status = 'pending') then
    raise exception 'Công việc đã có yêu cầu chờ duyệt';
  end if;

  direct_completion := public.can_manage_project(target_project_id) or exists (
    select 1
    from public.work_items item
    join public.profiles profile on profile.id = auth.uid() and profile.active
    where item.id = target_work_item_id
      and profile.is_department_admin
      and profile.department_id = item.lead_department_id
  );
  direct_completion_reason := case
    when public.can_manage_project(target_project_id) then 'Tự xác nhận theo quyền quản trị dự án sau khi nộp bằng chứng'
    when direct_completion then 'Tự xác nhận theo quyền Quản trị phòng/ban chủ trì sau khi nộp bằng chứng'
    else null
  end;

  select coalesce(max(attempt_no), 0) + 1 into next_attempt from public.completion_requests where work_item_id = target_work_item_id;
  insert into public.completion_requests (
    work_item_id, attempt_no, note, status, submitted_by, reviewed_by, reviewed_at, review_note
  ) values (
    target_work_item_id, next_attempt, nullif(trim(submission_note), ''),
    case when direct_completion then 'approved'::public.completion_request_status else 'pending'::public.completion_request_status end,
    auth.uid(), case when direct_completion then auth.uid() else null end,
    case when direct_completion then now() else null end,
    direct_completion_reason
  ) returning id into request_id;

  update public.work_items
  set status = case when direct_completion then 'completed'::public.work_item_status else 'pending_approval'::public.work_item_status end,
      updated_by = auth.uid(), version = version + 1
  where id = target_work_item_id and status <> 'completed';
  if not found then raise exception 'Không thể gửi công việc đã hoàn thành'; end if;
  return request_id;
end;
$$;

grant execute on function public.submit_work_item_completion(uuid, text) to authenticated;

commit;


-- ==========================================
-- Migration: 202609110004_department_admin_global_progress.sql
-- ==========================================
begin;

-- Detailed business data remains scoped to the user's project, department or assignment.
create or replace function public.can_view_work_item_detail(target_work_item_id uuid)
returns boolean
language plpgsql
stable
security definer set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  current_department_id uuid;
  current_is_department_admin boolean := false;
  target_project_id uuid;
begin
  if not public.is_active_user() then return false; end if;

  select project_id into target_project_id
  from public.work_items
  where id = target_work_item_id;
  if target_project_id is null then return false; end if;
  if public.is_project_admin(target_project_id) then return true; end if;

  select department_id, is_department_admin
  into current_department_id, current_is_department_admin
  from public.profiles
  where id = current_user_id and active;

  if current_is_department_admin
    and public.department_admin_owns_work_branch(target_work_item_id)
  then return true;
  end if;

  return exists (
    with recursive branch as (
      select child.id, child.lead_department_id
      from public.work_items child
      where child.id = target_work_item_id
      union all
      select child.id, child.lead_department_id
      from public.work_items child
      join branch parent on child.parent_id = parent.id
    )
    select 1
    from branch item
    where item.lead_department_id = current_department_id
      or exists (
        select 1
        from public.work_item_coordinating_departments coordinator
        where coordinator.work_item_id = item.id
          and coordinator.department_id = current_department_id
      )
      or exists (
        select 1
        from public.work_item_participants participant
        where participant.work_item_id = item.id
          and participant.user_id = current_user_id
      )
  );
end;
$$;

-- Department administrators may see every row needed to render progress/Gantt.
-- Employees keep the existing scoped visibility.
create or replace function public.can_view_work_item(target_work_item_id uuid)
returns boolean
language plpgsql
stable
security definer set search_path = public
as $$
declare
  target_project_id uuid;
  project_is_active boolean;
  current_is_department_admin boolean := false;
begin
  if not public.is_active_user() then return false; end if;

  select item.project_id, project.deleted_at is null
  into target_project_id, project_is_active
  from public.work_items item
  join public.projects project on project.id = item.project_id
  where item.id = target_work_item_id;
  if target_project_id is null then return false; end if;
  if not project_is_active and not public.is_manager() then return false; end if;
  if public.is_project_admin(target_project_id) then return true; end if;

  select is_department_admin into current_is_department_admin
  from public.profiles
  where id = auth.uid() and active;

  return current_is_department_admin or public.can_view_work_item_detail(target_work_item_id);
end;
$$;

create or replace function public.can_view_project(target_project_id uuid)
returns boolean
language plpgsql
stable
security definer set search_path = public
as $$
declare
  current_is_department_admin boolean := false;
begin
  if not public.is_active_user() then return false; end if;
  if public.is_project_admin(target_project_id) then return true; end if;

  select is_department_admin into current_is_department_admin
  from public.profiles
  where id = auth.uid() and active;
  if current_is_department_admin then return true; end if;

  return exists (
    select 1
    from public.work_items item
    where item.project_id = target_project_id
      and public.can_view_work_item_detail(item.id)
  );
end;
$$;

drop policy if exists projects_read on public.projects;
create policy projects_read on public.projects for select to authenticated using (
  (deleted_at is null or public.is_manager()) and public.can_view_project(id)
);

drop policy if exists work_items_read on public.work_items;
create policy work_items_read on public.work_items for select to authenticated
using (public.is_manager() or public.can_view_work_item(id));

drop policy if exists participants_read on public.work_item_participants;
create policy participants_read on public.work_item_participants for select to authenticated
using (public.is_manager() or public.can_view_work_item_detail(work_item_id));

drop policy if exists coordinating_departments_read on public.work_item_coordinating_departments;
create policy coordinating_departments_read on public.work_item_coordinating_departments for select to authenticated
using (public.is_manager() or public.can_view_work_item_detail(work_item_id));

drop policy if exists progress_updates_read on public.progress_updates;
create policy progress_updates_read on public.progress_updates for select to authenticated
using (public.is_manager() or public.can_view_work_item_detail(work_item_id));

drop policy if exists attachments_read on public.attachments;
create policy attachments_read on public.attachments for select to authenticated
using (public.is_manager() or public.can_view_work_item_detail(work_item_id));

drop policy if exists evidence_read_authenticated on storage.objects;
drop policy if exists evidence_read_scoped on storage.objects;
create policy evidence_read_scoped on storage.objects
for select to authenticated using (
  bucket_id = 'evidence'
  and split_part(storage.objects.name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and public.can_view_work_item_detail(split_part(storage.objects.name, '/', 1)::uuid)
);

grant execute on function public.can_view_project(uuid), public.can_view_work_item(uuid), public.can_view_work_item_detail(uuid) to authenticated;

commit;


-- ==========================================
-- Migration: 202609120001_project_work_item_delete_audit.sql
-- ==========================================
begin;

-- Quản trị dự án chỉ được đọc log xóa đầu mục trong đúng dự án mình quản lý.
-- Quản trị hệ thống tiếp tục đọc được toàn bộ audit log.
drop policy if exists audit_logs_read_manager on public.audit_logs;
drop policy if exists audit_logs_read_project_admin on public.audit_logs;
create policy audit_logs_read_project_admin on public.audit_logs
for select to authenticated
using (
  public.is_manager()
  or (
    entity_type = 'work_items'
    and action = 'delete'
    and before_data ? 'project_id'
    and public.can_manage_project((before_data ->> 'project_id')::uuid)
  )
);

create index if not exists audit_logs_work_item_delete_project_idx
  on public.audit_logs ((before_data ->> 'project_id'), created_at desc)
  where entity_type = 'work_items' and action = 'delete';

commit;


-- ==========================================
-- Migration: 202609120002_lock_approved_project_plan.sql
-- ==========================================
begin;

-- Kế hoạch đã được TGĐ phê duyệt trước khi nạp vào hệ thống. Từ thời điểm
-- nạp, chỉ Quản trị hệ thống hoặc Quản trị dự án được thay đổi cấu trúc.
create or replace function public.can_manage_work_item_structure(target_work_item_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.work_items item
    where item.id = target_work_item_id
      and public.can_manage_project(item.project_id)
  );
$$;

create or replace function public.can_create_child_work_item(target_project_id uuid, target_parent_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_manage_project(target_project_id);
$$;

-- Bỏ quyền xóa theo nhánh của Quản trị phòng/ban. Chính sách quản trị dự án
-- hiện có tiếp tục cho phép Quản trị hệ thống/Quản trị dự án xóa đầu mục.
drop policy if exists work_items_delete_department_admin on public.work_items;

grant execute on function public.can_manage_work_item_structure(uuid) to authenticated;
grant execute on function public.can_create_child_work_item(uuid, uuid) to authenticated;

commit;


-- ==========================================
-- Migration: 202609120003_department_admin_participant_assignment.sql
-- ==========================================
begin;

create or replace function public.update_work_item_participants(
  target_work_item_id uuid,
  expected_version integer,
  participant_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  target_project_id uuid;
  target_lead_department_id uuid;
  current_department_id uuid;
  current_is_department_admin boolean := false;
  current_active boolean := false;
  management_scope text := 'none';
  requested_participant_ids uuid[] := coalesce(participant_ids, '{}'::uuid[]);
  next_version integer;
begin
  select item.project_id, item.lead_department_id
  into target_project_id, target_lead_department_id
  from public.work_items item
  where item.id = target_work_item_id;

  if target_project_id is null then
    raise exception 'Không tìm thấy công việc';
  end if;

  if exists (select 1 from public.work_items child where child.parent_id = target_work_item_id) then
    raise exception 'Chỉ phân công người tham gia cho công việc cuối nhánh';
  end if;

  select profile.department_id, profile.is_department_admin, profile.active
  into current_department_id, current_is_department_admin, current_active
  from public.profiles profile
  where profile.id = auth.uid();

  if public.can_manage_project(target_project_id) then
    management_scope := 'all_related_departments';
  elsif current_active and current_is_department_admin and current_department_id is not null then
    if current_department_id = target_lead_department_id then
      management_scope := 'all_related_departments';
    elsif exists (
      select 1
      from public.work_item_coordinating_departments coordinator
      where coordinator.work_item_id = target_work_item_id
        and coordinator.department_id = current_department_id
    ) then
      management_scope := 'own_department';
    end if;
  end if;

  if management_scope = 'none' then
    raise exception 'Bạn không có quyền phân công người tham gia cho công việc này';
  end if;

  if exists (
    select 1
    from unnest(requested_participant_ids) requested(user_id)
    left join public.profiles profile on profile.id = requested.user_id
    where profile.id is null
      or not profile.active
      or profile.department_id is null
      or not (
        profile.department_id = target_lead_department_id
        or exists (
          select 1
          from public.work_item_coordinating_departments coordinator
          where coordinator.work_item_id = target_work_item_id
            and coordinator.department_id = profile.department_id
        )
      )
  ) then
    raise exception 'Người tham gia phải thuộc đơn vị chủ trì hoặc đơn vị phối hợp của công việc';
  end if;

  if management_scope = 'own_department' and (
    exists (
      select current_participant.user_id
      from public.work_item_participants current_participant
      join public.profiles profile on profile.id = current_participant.user_id
      where current_participant.work_item_id = target_work_item_id
        and profile.department_id is distinct from current_department_id
      except
      select requested.user_id
      from unnest(requested_participant_ids) requested(user_id)
      join public.profiles profile on profile.id = requested.user_id
      where profile.department_id is distinct from current_department_id
    )
    or exists (
      select requested.user_id
      from unnest(requested_participant_ids) requested(user_id)
      join public.profiles profile on profile.id = requested.user_id
      where profile.department_id is distinct from current_department_id
      except
      select current_participant.user_id
      from public.work_item_participants current_participant
      join public.profiles profile on profile.id = current_participant.user_id
      where current_participant.work_item_id = target_work_item_id
        and profile.department_id is distinct from current_department_id
    )
  ) then
    raise exception 'Quản trị đơn vị phối hợp chỉ được thay đổi nhân sự thuộc phòng/ban của mình';
  end if;

  update public.work_items
  set version = version + 1
  where id = target_work_item_id
    and version = expected_version
  returning version into next_version;

  if next_version is null then
    raise exception 'Công việc vừa được người khác cập nhật. Hãy tải lại rồi thử lại.';
  end if;

  delete from public.work_item_participants
  where work_item_id = target_work_item_id;

  insert into public.work_item_participants(work_item_id, user_id)
  select target_work_item_id, requested.user_id
  from unnest(requested_participant_ids) requested(user_id);

  return next_version;
end;
$$;

grant execute on function public.update_work_item_participants(uuid, integer, uuid[]) to authenticated;
revoke execute on function public.update_work_item_participants(uuid, integer, uuid[]) from public, anon;

commit;


-- ==========================================
-- Migration: 202609130001_validate_completion_state_transitions.sql
-- ==========================================
begin;

-- Không chỉ ẩn lựa chọn trên giao diện: mọi đường ghi dữ liệu đều phải
-- có lượt nộp và bằng chứng hợp lệ trước khi vào Chờ duyệt/Hoàn thành.
create or replace function public.validate_work_item_completion_transition()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  latest_request_status public.completion_request_status;
begin
  if tg_op = 'UPDATE' then
    if new.status is not distinct from old.status then return new; end if;
  end if;

  select request.status into latest_request_status
  from public.completion_requests request
  where request.work_item_id = new.id
  order by request.attempt_no desc
  limit 1;

  if new.status in ('pending_approval', 'completed') then
    if (select count(*) from public.attachments attachment where attachment.work_item_id = new.id) <> 1 then
      raise exception 'Phải tải đúng một bằng chứng và bấm nộp trước khi hoàn thành công việc';
    end if;
    if new.status = 'pending_approval' and latest_request_status is distinct from 'pending'::public.completion_request_status then
      raise exception 'Phải bấm nộp để gửi công việc cho quản trị viên duyệt';
    end if;
    if new.status = 'completed' and latest_request_status is distinct from 'approved'::public.completion_request_status then
      raise exception 'Công việc chỉ hoàn thành sau khi nộp và được duyệt hợp lệ';
    end if;
  elsif tg_op = 'UPDATE' then
    if old.status in ('pending_approval', 'completed')
      and latest_request_status is distinct from 'rejected'::public.completion_request_status then
      raise exception 'Không đổi trực tiếp trạng thái đã nộp; bằng chứng vẫn được khóa. Việc chờ duyệt phải được xét duyệt hoặc từ chối';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists work_items_01_validate_completion_transition on public.work_items;
create trigger work_items_01_validate_completion_transition
before insert or update on public.work_items
for each row execute function public.validate_work_item_completion_transition();

revoke execute on function public.validate_work_item_completion_transition() from public, anon, authenticated;

commit;


-- ==========================================
-- Migration: 202609140001_multi_branch_multi_department.sql
-- ==========================================
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


