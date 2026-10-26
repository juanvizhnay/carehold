begin;
create extension if not exists pgtap with schema extensions;
select plan(35);
set local search_path = public, extensions;

-- C1 clinician with patient P1. C2 clinician with patient P2. P3 is linked to nobody.
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
  ('c1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c1@example.test', '{"role":"clinician","full_name":"Dr One","clinic_name":"One PT"}'),
  ('c2000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c2@example.test', '{"role":"clinician","full_name":"Dr Two"}'),
  ('a1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p1@example.test', '{"role":"patient","full_name":"Pat One"}'),
  ('a2000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p2@example.test', '{"full_name":"Pat Two"}'),
  ('a3000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p3@example.test', '{"role":"admin"}');

select is((select role from profiles where id = 'c1000000-0000-0000-0000-000000000001'), 'clinician', 'trigger creates clinician profile');
select ok((select clinician_code from profiles where id = 'c1000000-0000-0000-0000-000000000001') ~ '^[A-Z2-9]{6}$', 'clinician gets a code');
select is((select role from profiles where id = 'a2000000-0000-0000-0000-000000000002'), 'patient', 'role defaults to patient');
select is((select role from profiles where id = 'a3000000-0000-0000-0000-000000000003'), 'patient', 'unknown role falls back to patient');
select is((select clinician_code from profiles where id = 'a1000000-0000-0000-0000-000000000001'), null, 'patients have no code');

-- P1 joins C1 using the code, P2 joins C2.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
reset role;
select set_config('test.c1_code', (select clinician_code from profiles where id = 'c1000000-0000-0000-0000-000000000001'), true);
select set_config('test.c2_code', (select clinician_code from profiles where id = 'c2000000-0000-0000-0000-000000000002'), true);
set local role authenticated;
select is(join_clinician(lower(current_setting('test.c1_code'))), 'c1000000-0000-0000-0000-000000000001'::uuid, 'patient joins with a lowercase code');
select throws_ok($$ select join_clinician('ZZZZZZ') $$, 'P0002', 'code not found', 'unknown code is rejected');
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select lives_ok($$ select join_clinician(current_setting('test.c2_code')) $$, 'P2 joins C2');
select set_config('request.jwt.claims', '{"sub":"c2000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select throws_ok($$ select join_clinician(current_setting('test.c1_code')) $$, '42501', 'only patients can join a clinician', 'clinicians cannot join');

-- C1 writes P1's plan.
select set_config('request.jwt.claims', '{"sub":"c1000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select lives_ok($$ insert into appointments (id, clinician_id, patient_id, starts_at, title) values ('00000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', now() + interval '1 day', 'Knee therapy') $$, 'clinician creates appointment for linked patient');
select lives_ok($$ insert into plan_items (id, clinician_id, patient_id, kind, title, times) values ('00000000-0000-0000-0000-0000000000b1', 'c1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'medication', 'Ibuprofen', '{08:00,20:00}') $$, 'clinician adds medication');
select lives_ok($$ insert into messages (id, clinician_id, patient_id, sender_id, kind, body) values ('00000000-0000-0000-0000-0000000000c1', 'c1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'reminder', 'Bring your shoes') $$, 'clinician sends reminder');
select throws_ok($$ insert into appointments (id, clinician_id, patient_id, starts_at, title) values ('00000000-0000-0000-0000-0000000000a9', 'c1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000003', now(), 'X') $$, '42501', null, 'clinician cannot create appointment for unlinked patient');
select throws_ok($$ insert into plan_items (id, clinician_id, patient_id, kind, title) values ('00000000-0000-0000-0000-0000000000b9', 'c1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000002', 'exercise', 'X') $$, '42501', null, 'clinician cannot add plan item for another clinician''s patient');
select is((select count(*) from profiles), 2::bigint, 'C1 sees own profile and P1 only');

-- C2 sees nothing of C1/P1.
select set_config('request.jwt.claims', '{"sub":"c2000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select is((select count(*) from appointments), 0::bigint, 'C2 cannot see C1 appointments');
select is((select count(*) from plan_items), 0::bigint, 'C2 cannot see C1 plan items');
select is((select count(*) from messages), 0::bigint, 'C2 cannot see C1 messages');
select is((select count(*) from profiles where id = 'a1000000-0000-0000-0000-000000000001'), 0::bigint, 'C2 cannot see P1 profile');
update appointments set title = 'hacked' where id = '00000000-0000-0000-0000-0000000000a1';
delete from plan_items where id = '00000000-0000-0000-0000-0000000000b1';
select throws_ok($$ insert into messages (id, clinician_id, patient_id, sender_id, body) values ('00000000-0000-0000-0000-0000000000c9', 'c1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000002', 'hi') $$, '42501', null, 'C2 cannot post into C1/P1 thread');

-- P1 reads, checks off, requests and messages; cannot rewrite the plan.
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select is((select title from appointments where id = '00000000-0000-0000-0000-0000000000a1'), 'Knee therapy', 'P1 sees appointment, C2 update had no effect');
select is((select count(*) from plan_items), 1::bigint, 'P1 sees plan item, C2 delete had no effect');
select lives_ok($$ insert into plan_logs (id, item_id, patient_id, due_on, slot) values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b1', 'a1000000-0000-0000-0000-000000000001', current_date, '08:00') $$, 'P1 checks off a dose');
select throws_ok($$ insert into plan_logs (id, item_id, patient_id, due_on, slot) values ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000b1', 'a1000000-0000-0000-0000-000000000001', current_date, '08:00') $$, '23505', null, 'same dose cannot be logged twice');
select lives_ok($$ insert into appointments (id, clinician_id, patient_id, starts_at, title, status, patient_note) values ('00000000-0000-0000-0000-0000000000a2', 'c1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', now() + interval '3 days', 'Visit request', 'requested', 'Knee hurts') $$, 'P1 requests an appointment');
select throws_ok($$ insert into appointments (id, clinician_id, patient_id, starts_at, title, status) values ('00000000-0000-0000-0000-0000000000a3', 'c1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', now(), 'X', 'scheduled') $$, '42501', null, 'P1 cannot schedule a confirmed appointment');
select throws_ok($$ insert into plan_items (id, clinician_id, patient_id, kind, title) values ('00000000-0000-0000-0000-0000000000b2', 'c1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'medication', 'X') $$, '42501', null, 'P1 cannot add plan items');
select throws_ok($$ insert into messages (id, clinician_id, patient_id, sender_id, kind, body) values ('00000000-0000-0000-0000-0000000000c2', 'c1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'reminder', 'x') $$, '23514', null, 'patients cannot send reminders');
select lives_ok($$ insert into messages (id, clinician_id, patient_id, sender_id, body) values ('00000000-0000-0000-0000-0000000000c3', 'c1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'Thanks') $$, 'P1 sends a message');
update messages set read_at = now() where id = '00000000-0000-0000-0000-0000000000c1';
select isnt((select read_at from messages where id = '00000000-0000-0000-0000-0000000000c1'), null, 'recipient marks reminder read');
update plan_items set title = 'changed' where id = '00000000-0000-0000-0000-0000000000b1';
select is((select title from plan_items where id = '00000000-0000-0000-0000-0000000000b1'), 'Ibuprofen', 'P1 cannot edit plan items');
select throws_ok($$ update profiles set role = 'clinician' where id = 'a1000000-0000-0000-0000-000000000001' $$, '42501', null, 'P1 cannot change own role');
select is((select count(*) from profiles), 2::bigint, 'P1 sees own profile and C1 only');

-- P3 (no link) sees nothing; anon has no access.
select set_config('request.jwt.claims', '{"sub":"a3000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
select is((select count(*) from appointments) + (select count(*) from plan_items) + (select count(*) from messages) + (select count(*) from plan_logs), 0::bigint, 'unlinked patient sees nothing');
reset role;
set local role anon;
select throws_ok($$ select * from profiles $$, '42501', null, 'anon cannot read profiles');

select * from finish();
rollback;
