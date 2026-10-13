-- Behaviour tests for the PawDone schema. Run with supabase/tests/run.sh.
--
-- Users:    A = owner (…0a), B = member (…0b), C = outsider, later a member (…0c)
-- Sessions: …01 and …02 = A's two phones, …03 = B, …04 = C
-- The pet's timezone is Asia/Kolkata; "today" below means today there.

\set ON_ERROR_STOP on
\o /dev/null

-- ─── Helpers ────────────────────────────────────────────────────────────────

create schema tests;
grant usage on schema tests to anon, authenticated;

create table tests.vars (key text primary key, value text not null);
grant all on tests.vars to authenticated;

create function tests.var(p_key text) returns text language sql stable as $$
  select value from tests.vars where key = p_key;
$$;

create function tests.login(p_user uuid, p_session uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'session_id', p_session, 'role', 'authenticated')::text, false);
$$;

-- Runs p_sql and fails unless it raises an error whose message matches p_message_like.
create function tests.expect_error(p_sql text, p_message_like text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm not like p_message_like then
      raise exception 'Expected error like "%" but got "%"', p_message_like, sqlerrm;
    end if;
    return;
  end;
  raise exception 'Expected error like "%" but it succeeded: %', p_message_like, p_sql;
end;
$$;

grant execute on all functions in schema tests to anon, authenticated;

-- ─── Sign-up ────────────────────────────────────────────────────────────────

insert into auth.users (id, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', '{"full_name": "Asha"}'),
  ('00000000-0000-0000-0000-00000000000b', '{}'),
  ('00000000-0000-0000-0000-00000000000c', '{}');

insert into auth.sessions (id, user_id) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a'),
  ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000b'),
  ('10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-00000000000c');

do $$ begin
  assert (select count(*) from public.profiles) = 3, 'a profile is created for each new user';
  assert (select name from public.profiles where id = '00000000-0000-0000-0000-00000000000a') = 'Asha',
    'profile name comes from sign-up details';
end $$;
\echo 'ok - profile created on sign-up'

-- ─── One phone per account ──────────────────────────────────────────────────

select tests.login('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001');
set role authenticated;
do $$ begin
  assert public.register_device('phone-one-0001') = 'ok', 'first phone registers';
  assert public.device_status('phone-one-0001') = 'active', 'first phone is active';
end $$;

-- A signs in on a second phone.
reset role;
insert into auth.sessions (id, user_id)
values ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a');
select tests.login('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000002');
set role authenticated;
do $$ begin
  assert public.device_status('phone-two-0002') = 'unknown', 'a new phone starts unknown';
  assert public.register_device('phone-two-0002') = 'conflict', 'Free: a second phone gets a conflict';
  assert public.register_device('phone-two-0002', true) = 'ok', 'Free: the second phone can take over';
  assert public.device_status('phone-two-0002') = 'active', 'the second phone is active';
  assert public.device_status('phone-one-0001') = 'inactive', 'the first phone is now inactive';
end $$;

reset role;
do $$ begin
  assert (select array_agg(id) from auth.sessions where user_id = '00000000-0000-0000-0000-00000000000a')
       = array['10000000-0000-0000-0000-000000000002'::uuid],
    'taking over revokes the other phone''s sessions';
end $$;

insert into public.entitlements (user_id, is_premium, expires_at)
values ('00000000-0000-0000-0000-00000000000a', true, now() + interval '30 days');

select tests.login('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000002');
set role authenticated;
do $$ begin
  assert public.register_device('phone-three-03') = 'ok', 'Premium: another phone registers without a conflict';
  assert public.device_status('phone-two-0002') = 'active', 'Premium: other phones stay active';
end $$;
\echo 'ok - one phone per account (Free), no limit on Premium'

-- ─── Pets ───────────────────────────────────────────────────────────────────

insert into public.pets (owner_id, name, species, timezone)
values ('00000000-0000-0000-0000-00000000000a', 'Bruno', 'dog', 'Asia/Kolkata');

select tests.expect_error(
  $$insert into public.pets (owner_id, name, species) values ('00000000-0000-0000-0000-00000000000a', 'Milo', 'cat')$$,
  'duplicate key value violates unique constraint "pets_one_per_owner"');
select tests.expect_error(
  $$update public.pets set timezone = 'Mars/Olympus_Mons'$$,
  'Unknown timezone%');
select tests.expect_error(
  $$insert into public.pets (owner_id, name, species) values ('00000000-0000-0000-0000-00000000000b', 'Fake', 'cat')$$,
  'new row violates row-level security policy%');

reset role;
insert into tests.vars select 'pet', id::text from public.pets;
\echo 'ok - one pet per owner, valid timezones only'

-- ─── Schedule and daily occurrences ─────────────────────────────────────────

select tests.login('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000002');
set role authenticated;

insert into public.tasks (pet_id, title, category, time_of_day)
select id, 'Dinner', 'food', '23:59:59' from public.pets;

insert into public.tasks (pet_id, title, category, time_of_day)
select id, 'Morning walk', 'walk', '00:00' from public.pets;

-- Repeats only on tomorrow's weekday.
insert into public.tasks (pet_id, title, category, time_of_day, weekdays)
select id, 'Bath', 'grooming', '12:00',
       1 << (extract(isodow from (now() at time zone 'Asia/Kolkata')::date + 1)::integer - 1)
from public.pets;

do $$
declare
  today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  assert (select array_agg(o.date order by o.date) from public.task_occurrences o
          join public.tasks t on t.id = o.task_id where t.title = 'Dinner')
       = array[today, today + 1, today + 2],
    'a daily task gets today and the next two days';
  assert (select o.scheduled_at from public.task_occurrences o
          join public.tasks t on t.id = o.task_id where t.title = 'Dinner' and o.date = today)
       = (today + time '23:59:59') at time zone 'Asia/Kolkata',
    'scheduled time is in the pet''s timezone';
  assert (select array_agg(o.date order by o.date) from public.task_occurrences o
          join public.tasks t on t.id = o.task_id where t.title = 'Morning walk')
       = array[today + 1, today + 2],
    'a task added after its time today starts tomorrow';
  assert (select array_agg(o.date) from public.task_occurrences o
          join public.tasks t on t.id = o.task_id where t.title = 'Bath')
       = array[today + 1],
    'a weekday task only appears on its days';
end $$;

reset role;
insert into tests.vars
select 'dinner_' || case when o.date = (now() at time zone 'Asia/Kolkata')::date then 'today' else 'tomorrow' end, o.id::text
from public.task_occurrences o
join public.tasks t on t.id = o.task_id
where t.title = 'Dinner' and o.date <= (now() at time zone 'Asia/Kolkata')::date + 1;

select tests.login('00000000-0000-0000-0000-00000000000c', '10000000-0000-0000-0000-000000000004');
set role authenticated;
do $$ begin
  assert (select count(*) from public.pets) = 0, 'outsiders can''t see the pet';
  assert (select count(*) from public.task_occurrences) = 0, 'outsiders can''t see occurrences';
end $$;
select tests.expect_error(
  format($$insert into public.tasks (pet_id, title, category, time_of_day) values (%L, 'Hack', 'food', '10:00')$$, tests.var('pet')),
  'new row violates row-level security policy%');
\echo 'ok - occurrences generated in the pet''s timezone'

-- ─── Invites and household ──────────────────────────────────────────────────

reset role;
select tests.login('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000002');
set role authenticated;
insert into tests.vars select 'invite1', token from public.create_invite();
insert into tests.vars select 'invite2', token from public.create_invite();
select tests.expect_error('select public.create_invite()', 'You can invite up to 2 people');

reset role;
select tests.login('00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000003');
set role authenticated;
do $$ begin
  assert (select count(*) from public.pets) = 0, 'not visible before joining';
  assert public.accept_invite(tests.var('invite1')) = '00000000-0000-0000-0000-00000000000a',
    'accepting an invite returns the owner';
  assert (select count(*) from public.pets) = 1, 'a member sees the pet';
  assert (select count(*) from public.task_occurrences) > 0, 'a member sees the daily tasks';
  assert (select count(*) from public.profiles) = 2, 'a member sees their own and the owner''s profile';
end $$;
select tests.expect_error(
  format('select public.accept_invite(%L)', tests.var('invite1')),
  'This invite link is invalid or has expired');
select tests.expect_error(
  format($$insert into public.tasks (pet_id, title, category, time_of_day) values (%L, 'Extra', 'food', '10:00')$$, tests.var('pet')),
  'new row violates row-level security policy%');
do $$ begin
  update public.tasks set title = 'Hacked';
  assert not exists (select 1 from public.tasks where title = 'Hacked'), 'members can''t edit the schedule';
end $$;
\echo 'ok - invites, max 2 people, members can''t edit the schedule'

-- ─── Marking tasks done ─────────────────────────────────────────────────────

do $$
declare
  v public.task_occurrences;
begin
  v := public.complete_occurrence(tests.var('dinner_today')::uuid, '  Half a cup  ');
  assert v.status = 'done', 'a member can mark today''s task done';
  assert v.completed_by = '00000000-0000-0000-0000-00000000000b', 'records who did it';
  assert v.note = 'Half a cup', 'note is trimmed';
end $$;
select tests.expect_error(
  format('select public.complete_occurrence(%L)', tests.var('dinner_today')),
  'This task is already marked');
select tests.expect_error(
  format('select public.complete_occurrence(%L)', tests.var('dinner_tomorrow')),
  'Tasks can only be marked on their own day');

reset role;
select tests.login('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.expect_error(
  format('select public.undo_occurrence(%L)', tests.var('dinner_today')),
  'Only the person who marked this task can undo it');

reset role;
select tests.login('00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000003');
set role authenticated;
do $$ begin
  assert (public.undo_occurrence(tests.var('dinner_today')::uuid)).status = 'pending',
    'you can undo your own check-off';
end $$;

reset role;
select tests.login('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000002');
set role authenticated;
do $$ begin
  assert (public.complete_occurrence(tests.var('dinner_today')::uuid)).completed_by = '00000000-0000-0000-0000-00000000000a',
    'the owner can mark a task done';
end $$;

reset role;
select tests.login('00000000-0000-0000-0000-00000000000c', '10000000-0000-0000-0000-000000000004');
set role authenticated;
select tests.expect_error(
  format('select public.complete_occurrence(%L)', tests.var('dinner_tomorrow')),
  'Task not found');
\echo 'ok - mark done, same day only, undo own check-off only'

-- ─── Premium ending ─────────────────────────────────────────────────────────

reset role;
update public.entitlements set expires_at = now() - interval '1 day'
where user_id = '00000000-0000-0000-0000-00000000000a';

select tests.login('00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000003');
set role authenticated;
do $$ begin
  assert (select count(*) from public.pets) = 0, 'members lose access when Premium ends';
end $$;

reset role;
select tests.login('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000002');
set role authenticated;
do $$ begin
  assert (select count(*) from public.pets) = 1, 'the owner keeps access';
end $$;
select tests.expect_error('select public.create_invite()', 'Inviting people needs Premium');

reset role;
select tests.login('00000000-0000-0000-0000-00000000000c', '10000000-0000-0000-0000-000000000004');
set role authenticated;
select tests.expect_error(
  format('select public.accept_invite(%L)', tests.var('invite2')),
  'This invite is no longer active');

reset role;
update public.entitlements set expires_at = now() + interval '30 days'
where user_id = '00000000-0000-0000-0000-00000000000a';

select tests.login('00000000-0000-0000-0000-00000000000c', '10000000-0000-0000-0000-000000000004');
set role authenticated;
do $$ begin
  perform public.accept_invite(tests.var('invite2'));
  assert (select count(*) from public.pets) = 1, 'the second member joins after Premium is back';
  assert (select count(*) from public.profiles) = 3, 'members see each other';
end $$;
\echo 'ok - members paused when Premium ends, back when it returns'

-- ─── Editing and archiving tasks ────────────────────────────────────────────

reset role;
select tests.login('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000002');
set role authenticated;

update public.tasks set title = 'Supper' where title = 'Dinner';
update public.tasks set time_of_day = '13:00' where title = 'Bath';
update public.tasks set archived_at = now() where title = 'Morning walk';

do $$
declare
  today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  assert (select title from public.task_occurrences where id = tests.var('dinner_today')::uuid) = 'Dinner',
    'a done occurrence keeps its original title';
  assert (select array_agg(o.title order by o.date) from public.task_occurrences o
          join public.tasks t on t.id = o.task_id where t.title = 'Supper')
       = array['Dinner', 'Supper', 'Supper'],
    'pending occurrences take the new title, without duplicates';
  assert (select o.scheduled_at from public.task_occurrences o
          join public.tasks t on t.id = o.task_id where t.title = 'Bath')
       = (today + 1 + time '13:00') at time zone 'Asia/Kolkata',
    'a time change moves upcoming occurrences';
  assert not exists (select 1 from public.task_occurrences o
                     join public.tasks t on t.id = o.task_id where t.title = 'Morning walk'),
    'archiving a task removes its upcoming occurrences';
end $$;
\echo 'ok - edits change today''s pending and future tasks only'

-- ─── End of day ─────────────────────────────────────────────────────────────

reset role;
insert into public.task_occurrences (task_id, pet_id, date, scheduled_at, title, category)
select t.id, t.pet_id, (now() at time zone 'Asia/Kolkata')::date - 1, now() - interval '1 day', t.title, t.category
from public.tasks t where t.title = 'Supper';

do $$ begin
  assert public.mark_missed_occurrences() = 1, 'only past days are marked missed';
  assert (select count(*) from public.task_occurrences where status = 'missed') = 1, 'yesterday''s pending task is missed';
end $$;
\echo 'ok - unmarked tasks become missed after midnight'

-- ─── Permissions ────────────────────────────────────────────────────────────

select tests.login('00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000003');
set role authenticated;
select tests.expect_error('select public.generate_occurrences()', 'permission denied for function generate_occurrences');
select tests.expect_error('select public.mark_missed_occurrences()', 'permission denied for function mark_missed_occurrences');
select tests.expect_error($$insert into public.task_occurrences (task_id, pet_id, date, scheduled_at, title, category)
  select task_id, pet_id, date + 10, scheduled_at, title, category from public.task_occurrences limit 1$$,
  'new row violates row-level security policy%');

reset role;
select set_config('request.jwt.claims', '', false);
set role anon;
do $$ begin
  assert (select count(*) from public.pets) = 0, 'signed-out users see nothing';
end $$;
select tests.expect_error($$select public.register_device('anon-device-1')$$, 'permission denied for function register_device');
\echo 'ok - server-only functions and signed-out access are blocked'

-- ─── Leaving and deleting ───────────────────────────────────────────────────

reset role;
select tests.login('00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000003');
set role authenticated;
delete from public.household_members where member_id = '00000000-0000-0000-0000-00000000000b';
do $$ begin
  assert (select count(*) from public.pets) = 0, 'a member who leaves loses access';
end $$;

reset role;
select tests.login('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000002');
set role authenticated;
delete from public.pets;

reset role;
do $$ begin
  assert (select count(*) from public.tasks) = 0, 'deleting the pet deletes its tasks';
  assert (select count(*) from public.task_occurrences) = 0, 'deleting the pet deletes its history';
end $$;
\echo 'ok - leaving a household, deleting a pet'

\echo 'All schema tests passed'
