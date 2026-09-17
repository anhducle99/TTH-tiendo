import fs from 'fs';
import path from 'path';

const dir = './supabase/migrations';
const files = fs.readdirSync(dir).filter(f => f.endsWith('.sql')).sort();
console.log('Found', files.length, 'migration files');

// Helper to seed root admin in auth.users if not exists
const rootAdminSeed = `
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
`;

let combinedSql = '';
for (const file of files) {
  const content = fs.readFileSync(path.join(dir, file), 'utf8');
  combinedSql += `-- ==========================================\n-- Migration: ${file}\n-- ==========================================\n` + content + '\n\n';
  
  // Insert root admin right after username_auth migration
  if (file.includes('202609090002_username_auth.sql')) {
    combinedSql += rootAdminSeed + '\n\n';
  }
}

fs.writeFileSync('./supabase_setup_all.sql', combinedSql, 'utf8');
console.log('Successfully generated ./supabase_setup_all.sql with size:', (combinedSql.length / 1024).toFixed(1), 'KB');
