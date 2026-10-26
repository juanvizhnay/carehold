-- CareHold core schema: patients and clinicians linked by a care relationship.
--
-- Security model:
--   * Every table has RLS. Policies only target `authenticated`; `anon` has no privileges.
--   * A patient sees only their own rows. A clinician sees only rows of patients linked to them.
--   * Rows that belong to a care relationship reference `care_links (clinician_id, patient_id)`
--     with a composite foreign key, so nobody can attach data to a pair that is not linked
--     (foreign keys ignore RLS, the composite key closes that gap).
--   * Update grants are column-level: ids, owners and timestamps are immutable.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role text not null check (role in ('patient', 'clinician')),
  full_name text not null default '' check (char_length(full_name) <= 120),
  -- Clinicians only: the practice name shown to patients and the code patients type to join.
  clinic_name text check (char_length(clinic_name) <= 120),
  clinician_code text unique check (clinician_code ~ '^[A-Z2-9]{6}$'),
  phone text check (char_length(phone) <= 40),
  created_at timestamptz not null default now(),
  check ((role = 'clinician') = (clinician_code is not null))
);

create table public.care_links (
  clinician_id uuid not null references public.profiles (id) on delete cascade,
  patient_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (clinician_id, patient_id),
  check (clinician_id <> patient_id)
);
create index care_links_patient_idx on public.care_links (patient_id);

-- Six characters without look-alikes (no 0/O, 1/I/L) so it can be read aloud or from paper.
create function private.new_clinician_code()
returns text
language plpgsql
set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  code text;
begin
  loop
    code := '';
    for i in 1..6 loop
      code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.profiles where clinician_code = code);
  end loop;
  return code;
end;
$$;

-- Creates the profile when an auth user is created. The role comes from sign-up metadata.
-- Demo only: in production clinicians must be verified before getting the clinician role.
create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_role text := coalesce(new.raw_user_meta_data ->> 'role', 'patient');
begin
  if requested_role not in ('patient', 'clinician') then
    requested_role := 'patient';
  end if;
  insert into public.profiles (id, role, full_name, clinic_name, clinician_code)
  values (
    new.id,
    requested_role,
    left(coalesce(new.raw_user_meta_data ->> 'full_name', ''), 120),
    case when requested_role = 'clinician' then left(new.raw_user_meta_data ->> 'clinic_name', 120) end,
    case when requested_role = 'clinician' then private.new_clinician_code() end
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- True when the calling user is either side of the link.
create function private.in_care_link(p_clinician uuid, p_patient uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) in (p_clinician, p_patient)
    and exists (
      select 1 from public.care_links
      where clinician_id = p_clinician and patient_id = p_patient
    );
$$;

-- True when the calling user shares a care link with `p_other`.
create function private.shares_care_link(p_other uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.care_links
    where (clinician_id = (select auth.uid()) and patient_id = p_other)
       or (patient_id = (select auth.uid()) and clinician_id = p_other)
  );
$$;

create function private.is_clinician()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles where id = (select auth.uid()) and role = 'clinician'
  );
$$;

grant usage on schema private to authenticated;
revoke execute on all functions in schema private from public, anon;
grant execute on function private.in_care_link(uuid, uuid) to authenticated;
grant execute on function private.shares_care_link(uuid) to authenticated;
grant execute on function private.is_clinician() to authenticated;

-- A patient joins a clinician by typing the clinician's code. Returns the clinician's id.
create function public.join_clinician(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := (select auth.uid());
  found uuid;
begin
  if caller is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles where id = caller and role = 'patient') then
    raise exception 'only patients can join a clinician' using errcode = '42501';
  end if;
  select id into found
  from public.profiles
  where role = 'clinician' and clinician_code = upper(regexp_replace(p_code, '\s', '', 'g'));
  if found is null then
    raise exception 'code not found' using errcode = 'P0002';
  end if;
  insert into public.care_links (clinician_id, patient_id)
  values (found, caller)
  on conflict do nothing;
  return found;
end;
$$;
revoke execute on function public.join_clinician(text) from public, anon;
grant execute on function public.join_clinician(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Appointments
-- ---------------------------------------------------------------------------

create table public.appointments (
  id uuid primary key,
  clinician_id uuid not null,
  patient_id uuid not null,
  starts_at timestamptz not null,
  duration_minutes int not null default 45 check (duration_minutes between 5 and 480),
  title text not null check (char_length(title) between 1 and 120),
  location text check (char_length(location) <= 200),
  -- requested: the patient asked for it and the clinician has not set a time yet.
  status text not null default 'scheduled'
    check (status in ('requested', 'scheduled', 'completed', 'cancelled')),
  -- What the clinician wrote after the visit, shown to the patient under past visits.
  visit_summary text check (char_length(visit_summary) <= 4000),
  -- What the patient wrote when requesting it ("my knee hurts more").
  patient_note text check (char_length(patient_note) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, patient_id),
  foreign key (clinician_id, patient_id)
    references public.care_links (clinician_id, patient_id) on delete cascade
);
create index appointments_patient_idx on public.appointments (patient_id, starts_at);
create index appointments_clinician_idx on public.appointments (clinician_id, starts_at);

-- ---------------------------------------------------------------------------
-- Care plan: medications, exercises and instructions in one list
-- ---------------------------------------------------------------------------

create table public.plan_items (
  id uuid primary key,
  clinician_id uuid not null,
  patient_id uuid not null,
  kind text not null check (kind in ('medication', 'exercise', 'instruction')),
  title text not null check (char_length(title) between 1 and 120),
  -- "400 mg, 1 tablet" or "3 sets of 10".
  dosage text check (char_length(dosage) <= 120),
  instructions text check (char_length(instructions) <= 2000),
  -- Local wall-clock times when it is due. Empty: anytime during the day.
  times time[] not null default '{}' check (cardinality(times) <= 8),
  -- ISO weekdays 1 (Mon) .. 7 (Sun). Empty: every day.
  weekdays smallint[] not null default '{}'
    check (cardinality(weekdays) <= 7 and weekdays <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[]),
  start_date date not null default current_date,
  end_date date,
  -- The visit where it was prescribed, if any ("prescriptions from past visits").
  appointment_id uuid,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  unique (id, patient_id),
  check (end_date is null or end_date >= start_date),
  foreign key (clinician_id, patient_id)
    references public.care_links (clinician_id, patient_id) on delete cascade,
  foreign key (appointment_id, patient_id)
    references public.appointments (id, patient_id) on delete set null (appointment_id)
);
create index plan_items_patient_idx on public.plan_items (patient_id) where archived_at is null;
create index plan_items_clinician_idx on public.plan_items (clinician_id);
create index plan_items_appointment_idx on public.plan_items (appointment_id);

-- One row each time the patient marks a dose or exercise as done.
create table public.plan_logs (
  id uuid primary key,
  item_id uuid not null,
  patient_id uuid not null,
  due_on date not null,
  -- The scheduled time it answers; null for "anytime" items.
  slot time,
  done_at timestamptz not null default now(),
  unique nulls not distinct (item_id, due_on, slot),
  foreign key (item_id, patient_id)
    references public.plan_items (id, patient_id) on delete cascade
);
create index plan_logs_patient_idx on public.plan_logs (patient_id, due_on);

-- ---------------------------------------------------------------------------
-- Messages (and clinician reminders)
-- ---------------------------------------------------------------------------

create table public.messages (
  id uuid primary key,
  clinician_id uuid not null,
  patient_id uuid not null,
  sender_id uuid not null,
  kind text not null default 'message' check (kind in ('message', 'reminder')),
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  check (sender_id in (clinician_id, patient_id)),
  check (kind = 'message' or sender_id = clinician_id),
  foreign key (clinician_id, patient_id)
    references public.care_links (clinician_id, patient_id) on delete cascade
);
create index messages_thread_idx on public.messages (clinician_id, patient_id, created_at);
create index messages_patient_idx on public.messages (patient_id, created_at);

-- ---------------------------------------------------------------------------
-- Timestamps
-- ---------------------------------------------------------------------------

create function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger appointments_touch
  before update on public.appointments
  for each row execute function private.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------

revoke all on public.profiles, public.care_links, public.appointments, public.plan_items,
  public.plan_logs, public.messages from anon, authenticated;

grant select on public.profiles to authenticated;
grant update (full_name, clinic_name, phone) on public.profiles to authenticated;

grant select, delete on public.care_links to authenticated;

grant select, insert, delete on public.appointments to authenticated;
grant update (starts_at, duration_minutes, title, location, status, visit_summary)
  on public.appointments to authenticated;

grant select, insert, delete on public.plan_items to authenticated;
grant update (kind, title, dosage, instructions, times, weekdays, start_date, end_date,
  appointment_id, archived_at) on public.plan_items to authenticated;

grant select, insert, delete on public.plan_logs to authenticated;

grant select, insert on public.messages to authenticated;
grant update (read_at) on public.messages to authenticated;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.care_links enable row level security;
alter table public.appointments enable row level security;
alter table public.plan_items enable row level security;
alter table public.plan_logs enable row level security;
alter table public.messages enable row level security;

-- profiles: yourself, plus the people you share a care link with.
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select private.shares_care_link(id)));
create policy profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- care_links: rows are created only by join_clinician(); either side can end the link.
create policy care_links_select on public.care_links for select to authenticated
  using ((select auth.uid()) in (clinician_id, patient_id));
create policy care_links_delete on public.care_links for delete to authenticated
  using ((select auth.uid()) in (clinician_id, patient_id));

-- appointments: clinicians manage them; patients may only request one.
create policy appointments_select on public.appointments for select to authenticated
  using ((select auth.uid()) in (clinician_id, patient_id));
create policy appointments_insert on public.appointments for insert to authenticated
  with check (
    (select private.in_care_link(clinician_id, patient_id))
    and (
      clinician_id = (select auth.uid())
      or (patient_id = (select auth.uid()) and status = 'requested' and visit_summary is null)
    )
  );
create policy appointments_update on public.appointments for update to authenticated
  using (clinician_id = (select auth.uid()))
  with check (clinician_id = (select auth.uid()));
create policy appointments_delete on public.appointments for delete to authenticated
  using (
    clinician_id = (select auth.uid())
    or (patient_id = (select auth.uid()) and status = 'requested')
  );

-- plan_items: written by the clinician, read by both.
create policy plan_items_select on public.plan_items for select to authenticated
  using ((select auth.uid()) in (clinician_id, patient_id));
create policy plan_items_insert on public.plan_items for insert to authenticated
  with check (
    clinician_id = (select auth.uid()) and (select private.in_care_link(clinician_id, patient_id))
  );
create policy plan_items_update on public.plan_items for update to authenticated
  using (clinician_id = (select auth.uid()))
  with check (clinician_id = (select auth.uid()));
create policy plan_items_delete on public.plan_items for delete to authenticated
  using (clinician_id = (select auth.uid()));

-- plan_logs: the patient checks items off; their clinicians can see adherence.
create policy plan_logs_select on public.plan_logs for select to authenticated
  using (
    patient_id = (select auth.uid())
    or exists (
      select 1 from public.plan_items i
      where i.id = item_id and i.clinician_id = (select auth.uid())
    )
  );
create policy plan_logs_insert on public.plan_logs for insert to authenticated
  with check (patient_id = (select auth.uid()));
create policy plan_logs_delete on public.plan_logs for delete to authenticated
  using (patient_id = (select auth.uid()));

-- messages: both sides of a link write as themselves; only the recipient marks it read.
create policy messages_select on public.messages for select to authenticated
  using ((select auth.uid()) in (clinician_id, patient_id));
create policy messages_insert on public.messages for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and read_at is null
    and (select private.in_care_link(clinician_id, patient_id))
  );
create policy messages_update on public.messages for update to authenticated
  using ((select auth.uid()) in (clinician_id, patient_id) and sender_id <> (select auth.uid()))
  with check ((select auth.uid()) in (clinician_id, patient_id) and sender_id <> (select auth.uid()));

-- Live chat while the app is open.
alter publication supabase_realtime add table public.messages;
