-- Push notification tests. Run with supabase/tests/run.sh.
--
-- Users: A = owner with Premium (…0a), B = member "Sam" (…0b), C = someone else (…0c)
-- The pet's timezone is UTC.

\set ON_ERROR_STOP on
\o /dev/null

insert into auth.users (id, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', '{"full_name": "Asha"}'),
  ('00000000-0000-0000-0000-00000000000b', '{"full_name": "Sam"}'),
  ('00000000-0000-0000-0000-00000000000c', '{}');

insert into auth.sessions (id, user_id) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000b'),
  ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000c');

insert into public.entitlements (user_id, is_premium, expires_at)
values ('00000000-0000-0000-0000-00000000000a', true, now() + interval '30 days');

insert into public.household_members (owner_id, member_id)
values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b');

-- ─── Push tokens ────────────────────────────────────────────────────────────

select tests.login('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001');
set role authenticated;
do $$ begin
  assert public.register_device('phone-a-0001') = 'ok';
  perform public.set_push_token('phone-a-0001', 'token-a', 'sandbox');
end $$;
select tests.expect_error($$select public.set_push_token('phone-a-0001', 'token-a', 'staging')$$, 'Invalid environment');

reset role;
select tests.login('00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000002');
set role authenticated;
do $$ begin
  assert public.register_device('phone-b-0001') = 'ok';
  perform public.set_push_token('phone-b-0001', 'token-b');
end $$;

reset role;
do $$ begin
  assert (select apns_environment from public.devices where apns_token = 'token-a') = 'sandbox', 'stores the environment';
  assert (select apns_environment from public.devices where apns_token = 'token-b') = 'production', 'defaults to production';
end $$;
\echo 'ok - push tokens saved per phone'

-- ─── Reminders ──────────────────────────────────────────────────────────────

select tests.login('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001');
set role authenticated;
insert into public.pets (owner_id, name, species, timezone)
values ('00000000-0000-0000-0000-00000000000a', 'Bruno', 'dog', 'UTC');
insert into public.tasks (pet_id, title, category, time_of_day)
select id, 'Lunch', 'food', '12:00' from public.pets;
insert into public.tasks (pet_id, title, category, time_of_day, reminder_enabled)
select id, 'Quiet task', 'other', '12:00', false from public.pets;

-- Make today's occurrences due a minute ago (the generator skips times already past).
reset role;
insert into public.task_occurrences (task_id, pet_id, date, scheduled_at, title, category)
select t.id, t.pet_id, (now() at time zone 'UTC')::date, now() - interval '1 minute', t.title, t.category
from public.tasks t
on conflict (task_id, date) do update set scheduled_at = excluded.scheduled_at, status = 'pending', reminder_sent_at = null;
-- Keep only today's, so "where title = …" below means one row.
delete from public.task_occurrences where date > (now() at time zone 'UTC')::date;

set role service_role;
create temporary table claimed as select * from public.claim_push_notifications();
do $$ begin
  assert (select count(*) from claimed) = 2, 'one reminder per phone in the household';
  assert (select array_agg(token order by token) from claimed) = array['token-a', 'token-b'];
  assert (select bool_and(kind = 'reminder' and title = 'Bruno' and body = 'Lunch is due now.') from claimed),
    'reminder text names the pet and task';
  assert (select count(*) from public.claim_push_notifications()) = 0, 'each reminder is sent once';
end $$;
\echo 'ok - due reminders go to every phone in the household, once'

-- Reminders older than 10 minutes are skipped, and done tasks get none.
reset role;
update public.task_occurrences
set scheduled_at = now() - interval '20 minutes', reminder_sent_at = null
where title = 'Lunch';
set role service_role;
do $$ begin
  assert (select count(*) from public.claim_push_notifications()) = 0, 'late reminders are skipped';
end $$;

-- B mutes reminders for the pet.
reset role;
update public.task_occurrences
set scheduled_at = now() - interval '1 minute', reminder_sent_at = null
where title = 'Lunch';
select tests.login('00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000002');
set role authenticated;
-- Upsert twice, like the app's toggle: the first inserts, the second updates.
insert into public.notification_prefs (user_id, pet_id, reminders_enabled)
select '00000000-0000-0000-0000-00000000000b', id, true from public.pets
on conflict (user_id, pet_id) do update set reminders_enabled = excluded.reminders_enabled;
insert into public.notification_prefs (user_id, pet_id, reminders_enabled)
select '00000000-0000-0000-0000-00000000000b', id, false from public.pets
on conflict (user_id, pet_id) do update set reminders_enabled = excluded.reminders_enabled;
reset role;
set role service_role;
do $$ begin
  assert (select array_agg(token) from public.claim_push_notifications()) = array['token-a'],
    'people who muted reminders for the pet are left out';
end $$;
\echo 'ok - late, unreminded and muted reminders are not sent'

-- ─── Task done alerts ───────────────────────────────────────────────────────

reset role;
select tests.login('00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000002');
set role authenticated;
do $$ begin
  perform public.complete_occurrence((select id from public.task_occurrences where title = 'Lunch'));
end $$;

reset role;
set role service_role;
drop table claimed;
create temporary table claimed as select * from public.claim_push_notifications();
do $$ begin
  assert (select count(*) from claimed) = 1, 'everyone except the person who did it';
  assert (select token from claimed) = 'token-a';
  assert (select body from claimed) = 'Sam marked Lunch as done.', 'names who did it';
  assert (select kind from claimed) = 'completed';
  assert (select count(*) from public.claim_push_notifications()) = 0, 'each alert is sent once';
end $$;

-- Undone before the alert went out: nothing is sent.
reset role;
select tests.login('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001');
set role authenticated;
do $$ begin
  perform public.complete_occurrence((select id from public.task_occurrences where title = 'Quiet task'));
  perform public.undo_occurrence((select id from public.task_occurrences where title = 'Quiet task'));
end $$;
reset role;
set role service_role;
do $$ begin
  assert (select count(*) from public.claim_push_notifications()) = 0, 'undone tasks send no alert';
end $$;
\echo 'ok - done alerts go to everyone else, once, and not after an undo'

-- ─── Premium ending ─────────────────────────────────────────────────────────

reset role;
update public.entitlements set expires_at = now() - interval '1 day';
update public.task_occurrences
set status = 'pending', completed_by = null, completed_at = null,
    scheduled_at = now() - interval '1 minute', reminder_sent_at = null
where title = 'Lunch';
delete from public.notification_prefs;
set role service_role;
do $$ begin
  assert (select array_agg(token) from public.claim_push_notifications()) = array['token-a'],
    'members get nothing while the owner has no Premium';
end $$;
\echo 'ok - members get no notifications when Premium ends'

-- ─── Token clean-up ─────────────────────────────────────────────────────────

-- C signs in on A's old phone: the token moves to C.
reset role;
select tests.login('00000000-0000-0000-0000-00000000000c', '10000000-0000-0000-0000-000000000003');
set role authenticated;
do $$ begin
  assert public.register_device('phone-a-0001') = 'ok';
  perform public.set_push_token('phone-a-0001', 'token-a', 'sandbox');
end $$;

reset role;
do $$ begin
  assert (select count(*) from public.devices where apns_token = 'token-a') = 1, 'a token belongs to one account';
  assert (select user_id from public.devices where apns_token = 'token-a') = '00000000-0000-0000-0000-00000000000c';
end $$;

set role service_role;
select public.forget_push_tokens(array['token-b']);
reset role;
do $$ begin
  assert not exists (select 1 from public.devices where apns_token = 'token-b'), 'dead tokens are forgotten';
end $$;

-- Signing out clears the token.
select tests.login('00000000-0000-0000-0000-00000000000c', '10000000-0000-0000-0000-000000000003');
set role authenticated;
select public.set_push_token('phone-a-0001', null, 'sandbox');
reset role;
do $$ begin
  assert not exists (select 1 from public.devices where apns_token = 'token-a'), 'a null token clears it';
end $$;
\echo 'ok - tokens move between accounts, dead ones are dropped'

-- ─── Permissions ────────────────────────────────────────────────────────────

select tests.login('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.expect_error('select * from public.claim_push_notifications()', 'permission denied for function claim_push_notifications');
select tests.expect_error($$select public.forget_push_tokens(array['x'])$$, 'permission denied for function forget_push_tokens');
select tests.expect_error('select * from public.push_outbox', 'permission denied for table push_outbox');
\echo 'ok - only the server can send or read notifications'

\echo 'All push tests passed'
