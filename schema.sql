-- ============================================================
-- Employee Time Tracker — Supabase schema
-- Paste this into: Supabase Dashboard → SQL Editor → New query → Run
-- ============================================================

-- ---------- Tables ----------

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default 'Employee',
  department text default 'General',
  is_admin boolean not null default false,
  pto_hours numeric not null default 120,
  email text
);

create table if not exists cost_codes (
  id uuid primary key default gen_random_uuid(),
  job text not null,
  phase text not null,
  name text default '',
  unique(job, phase)
);

create table if not exists time_entries (
  id uuid primary key default gen_random_uuid(),
  emp_id uuid not null references profiles(id) on delete cascade,
  clock_in timestamptz not null default now(),
  clock_out timestamptz,
  cost_code text,
  work_description text
);

create table if not exists breaks (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references time_entries(id) on delete cascade,
  break_start timestamptz not null default now(),
  break_end timestamptz
);

create table if not exists task_segments (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references time_entries(id) on delete cascade,
  start_time timestamptz not null default now(),
  end_time timestamptz,
  cost_code text,
  work_description text
);

create table if not exists tasks (
  id uuid primary key default gen_random_uuid(),
  emp_id uuid not null references profiles(id) on delete cascade,
  title text not null,
  completed boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists pto_requests (
  id uuid primary key default gen_random_uuid(),
  emp_id uuid not null references profiles(id) on delete cascade,
  start_date date not null,
  end_date date not null,
  hours numeric not null default 8,
  pto_type text not null default 'vacation',
  reason text default '',
  status text not null default 'pending',
  created_at timestamptz not null default now()
);

-- ---------- Indexes ----------
create index if not exists idx_entries_emp on time_entries(emp_id);
create index if not exists idx_entries_in on time_entries(clock_in);
create index if not exists idx_breaks_entry on breaks(entry_id);
create index if not exists idx_segments_entry on task_segments(entry_id);
create index if not exists idx_tasks_emp on tasks(emp_id);
create index if not exists idx_pto_emp on pto_requests(emp_id);
create index if not exists idx_profiles_admin on profiles(is_admin);

-- ---------- Helper: is the current user an admin? ----------
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from profiles where id = auth.uid()), false);
$$;

-- ---------- Auto-create a profile on signup ----------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, department, is_admin, pto_hours, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)), 'General', false, 120, new.email)
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================
-- Row Level Security (RLS)
-- ============================================================
alter table profiles enable row level security;
alter table time_entries enable row level security;
alter table breaks enable row level security;
alter table task_segments enable row level security;
alter table tasks enable row level security;
alter table pto_requests enable row level security;
alter table cost_codes enable row level security;

-- ---------- profiles ----------
drop policy if exists "profiles_select" on profiles;
create policy "profiles_select" on profiles for select
  using (auth.uid() = id or public.is_admin());

drop policy if exists "profiles_update_self" on profiles;
create policy "profiles_update_self" on profiles for update
  using (auth.uid() = id or public.is_admin());

drop policy if exists "profiles_admin_insert" on profiles;
create policy "profiles_admin_insert" on profiles for insert
  with check (public.is_admin());

-- ---------- cost_codes (any authenticated user can read; admin can write) ----------
drop policy if exists "cost_codes_select" on cost_codes;
create policy "cost_codes_select" on cost_codes for select
  using (auth.role() = 'authenticated');

drop policy if exists "cost_codes_admin_all" on cost_codes;
create policy "cost_codes_admin_all" on cost_codes for all
  using (public.is_admin()) with check (public.is_admin());

-- ---------- time_entries ----------
drop policy if exists "entries_select" on time_entries;
create policy "entries_select" on time_entries for select
  using (emp_id = auth.uid() or public.is_admin());

drop policy if exists "entries_insert_self" on time_entries;
create policy "entries_insert_self" on time_entries for insert
  with check (emp_id = auth.uid() or public.is_admin());

drop policy if exists "entries_update_self" on time_entries;
create policy "entries_update_self" on time_entries for update
  using (emp_id = auth.uid() or public.is_admin());

drop policy if exists "entries_delete_admin" on time_entries;
create policy "entries_delete_admin" on time_entries for delete
  using (public.is_admin() or emp_id = auth.uid());

-- ---------- breaks ----------
drop policy if exists "breaks_select" on breaks;
create policy "breaks_select" on breaks for select
  using (exists (select 1 from time_entries te where te.id = breaks.entry_id and (te.emp_id = auth.uid() or public.is_admin())));

drop policy if exists "breaks_insert" on breaks;
create policy "breaks_insert" on breaks for insert
  with check (exists (select 1 from time_entries te where te.id = breaks.entry_id and (te.emp_id = auth.uid() or public.is_admin())));

drop policy if exists "breaks_update" on breaks;
create policy "breaks_update" on breaks for update
  using (exists (select 1 from time_entries te where te.id = breaks.entry_id and (te.emp_id = auth.uid() or public.is_admin())));

drop policy if exists "breaks_delete" on breaks;
create policy "breaks_delete" on breaks for delete
  using (exists (select 1 from time_entries te where te.id = breaks.entry_id and (te.emp_id = auth.uid() or public.is_admin())));

-- ---------- task_segments ----------
drop policy if exists "segments_select" on task_segments;
create policy "segments_select" on task_segments for select
  using (exists (select 1 from time_entries te where te.id = task_segments.entry_id and (te.emp_id = auth.uid() or public.is_admin())));

drop policy if exists "segments_insert" on task_segments;
create policy "segments_insert" on task_segments for insert
  with check (exists (select 1 from time_entries te where te.id = task_segments.entry_id and (te.emp_id = auth.uid() or public.is_admin())));

drop policy if exists "segments_update" on task_segments;
create policy "segments_update" on task_segments for update
  using (exists (select 1 from time_entries te where te.id = task_segments.entry_id and (te.emp_id = auth.uid() or public.is_admin())));

drop policy if exists "segments_delete" on task_segments;
create policy "segments_delete" on task_segments for delete
  using (exists (select 1 from time_entries te where te.id = task_segments.entry_id and (te.emp_id = auth.uid() or public.is_admin())));

-- ---------- tasks (personal to-do list) ----------
drop policy if exists "tasks_select" on tasks;
create policy "tasks_select" on tasks for select
  using (emp_id = auth.uid() or public.is_admin());

drop policy if exists "tasks_insert_self" on tasks;
create policy "tasks_insert_self" on tasks for insert
  with check (emp_id = auth.uid());

drop policy if exists "tasks_update_self" on tasks;
create policy "tasks_update_self" on tasks for update
  using (emp_id = auth.uid() or public.is_admin());

drop policy if exists "tasks_delete_self" on tasks;
create policy "tasks_delete_self" on tasks for delete
  using (emp_id = auth.uid() or public.is_admin());

-- ---------- pto_requests ----------
drop policy if exists "pto_select" on pto_requests;
create policy "pto_select" on pto_requests for select
  using (emp_id = auth.uid() or public.is_admin());

drop policy if exists "pto_insert_self" on pto_requests;
create policy "pto_insert_self" on pto_requests for insert
  with check (emp_id = auth.uid());

drop policy if exists "pto_update_admin" on pto_requests;
create policy "pto_update_admin" on pto_requests for update
  using (public.is_admin());

drop policy if exists "pto_delete" on pto_requests;
create policy "pto_delete" on pto_requests for delete
  using (emp_id = auth.uid() or public.is_admin());

-- ---------- Seed sample cost codes (idempotent — safe to re-run) ----------
insert into cost_codes (job, phase, name)
select * from (values
  ('1552','200004','K196-Lilly Chiller'),
  ('1562','200004','B358 PEL'),
  ('2265-1','160009','PP1'),
  ('2265-2','160009','SS1'),
  ('1560','200003','K153'),
  ('1563','200005','PDC'),
  ('3016','200001','Lilly PFS3')
) as v(job, phase, name)
where not exists (select 1 from cost_codes c where c.job = v.job and c.phase = v.phase);

-- ---------- Migration: add work_description (idempotent) ----------
alter table time_entries add column if not exists work_description text;

-- ---------- Migration: add email to profiles + backfill (idempotent) ----------
alter table profiles add column if not exists email text;
update profiles p set email = u.email from auth.users u where u.id = p.id and p.email is null;

-- ---------- Realtime (idempotent — safe to re-run) ----------
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'time_entries') then
    alter publication supabase_realtime add table time_entries;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'pto_requests') then
    alter publication supabase_realtime add table pto_requests;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'task_segments') then
    alter publication supabase_realtime add table task_segments;
  end if;
end $$;
