-- Account deletion tests. Run with supabase/tests/run.sh.
--
-- Users: A = owner of Bruno with Premium, also helps in D's household (…0a)
--        B = helper in A's household (…0b)
--        D = owner of Milo with Premium (…0d)
-- Deleting A must remove A and everything A owns, and leave B and D intact.

\set ON_ERROR_STOP on
\o /dev/null

insert into auth.users (id) values
  ('00000000-0000-0000-0000-00000000000a'),
  ('00000000-0000-0000-0000-00000000000b'),
  ('00000000-0000-0000-0000-00000000000d');

insert into public.entitlements (user_id, is_premium, expires_at) values
  ('00000000-0000-0000-0000-00000000000a', true, now() + interval '30 days'),
  ('00000000-0000-0000-0000-00000000000d', true, now() + interval '30 days');

insert into public.pets (owner_id, name, species, timezone) values
  ('00000000-0000-0000-0000-00000000000a', 'Bruno', 'dog', 'UTC'),
  ('00000000-0000-0000-0000-00000000000d', 'Milo', 'cat', 'UTC');
insert into tests.vars select lower(name), id::text from public.pets;

insert into public.household_members (owner_id, member_id) values
  ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b'),
  ('00000000-0000-0000-0000-00000000000d', '00000000-0000-0000-0000-00000000000a');

insert into public.invites (owner_id) values ('00000000-0000-0000-0000-00000000000a');
insert into public.devices (user_id, device_id) values
  ('00000000-0000-0000-0000-00000000000a', 'phone-a-0001'),
  ('00000000-0000-0000-0000-00000000000b', 'phone-b-0001');
insert into public.notification_prefs (user_id, pet_id, reminders_enabled)
select '00000000-0000-0000-0000-00000000000a', id, false from public.pets;

insert into public.tasks (pet_id, title, category, time_of_day)
select id, 'Dinner', 'food', '23:59:59' from public.pets;

-- Today's Dinner: Bruno's done by B (helper) with a photo, Milo's done by A (as helper) with a photo.
update public.task_occurrences o
set status = 'done', completed_at = now(), photo_path = p.id || '/' || o.id || '.jpg',
    completed_by = case when p.name = 'Bruno' then '00000000-0000-0000-0000-00000000000b'::uuid
                        else '00000000-0000-0000-0000-00000000000a'::uuid end
from public.pets p
where p.id = o.pet_id and o.date = (now() at time zone 'UTC')::date;

insert into storage.buckets (id, name) values ('proof-photos', 'proof-photos') on conflict do nothing;
insert into storage.objects (bucket_id, name, owner_id)
select 'proof-photos', o.photo_path, o.completed_by::text
from public.task_occurrences o where o.photo_path is not null;
-- A photo in an unrelated folder, uploaded by D.
insert into storage.objects (bucket_id, name, owner_id)
values ('proof-photos', tests.var('milo') || '/other.jpg', '00000000-0000-0000-0000-00000000000d');

-- ─── Permissions ────────────────────────────────────────────────────────────

select tests.login('00000000-0000-0000-0000-00000000000a', null);
set role authenticated;
select tests.expect_error(
  $$select * from public.prepare_account_deletion('00000000-0000-0000-0000-00000000000a')$$,
  'permission denied for function prepare_account_deletion');
reset role;
\echo 'ok - only the server can prepare a deletion'

-- ─── Photos ─────────────────────────────────────────────────────────────────

set role service_role;
create temporary table paths as
select * from public.prepare_account_deletion('00000000-0000-0000-0000-00000000000a') as path;
reset role;

do $$ begin
  assert (select count(*) from paths) = 2, 'two photos to delete';
  assert exists (select 1 from paths where path like tests.var('bruno') || '/%'),
    'the photo the helper took of A''s pet';
  assert exists (
    select 1 from paths join public.task_occurrences o on o.id::text || '.jpg' = split_part(path, '/', 2)
    where o.pet_id = tests.var('milo')::uuid
  ), 'the photo A took in D''s household';
  assert not exists (select 1 from paths where path like '%/other.jpg'), 'not other people''s photos';

  assert (select photo_path from public.task_occurrences
          where pet_id = tests.var('milo')::uuid and status = 'done') is null,
    'D''s check-off loses the photo reference';
  assert (select status from public.task_occurrences
          where pet_id = tests.var('milo')::uuid and completed_by is not null) = 'done',
    'but keeps the check-off';
end $$;
\echo 'ok - finds A''s photos and detaches them from other households'

-- ─── Deleting the user ──────────────────────────────────────────────────────

delete from auth.users where id = '00000000-0000-0000-0000-00000000000a';

do $$
declare
  a constant uuid := '00000000-0000-0000-0000-00000000000a';
begin
  assert not exists (select 1 from public.profiles where id = a), 'profile';
  assert not exists (select 1 from public.devices where user_id = a), 'devices';
  assert not exists (select 1 from public.entitlements where user_id = a), 'entitlement';
  assert not exists (select 1 from public.pets where owner_id = a), 'owned pet';
  assert not exists (select 1 from public.tasks where pet_id = tests.var('bruno')::uuid), 'its tasks';
  assert not exists (select 1 from public.task_occurrences where pet_id = tests.var('bruno')::uuid), 'its history';
  assert not exists (select 1 from public.household_members where a in (owner_id, member_id)), 'memberships';
  assert not exists (select 1 from public.invites where owner_id = a), 'invites';
  assert not exists (select 1 from public.notification_prefs where user_id = a), 'notification settings';

  assert exists (select 1 from public.pets where name = 'Milo'), 'D''s pet stays';
  assert (select completed_by from public.task_occurrences
          where pet_id = tests.var('milo')::uuid and status = 'done') is null,
    'D''s history stays, without A''s name';
  assert exists (select 1 from public.profiles where id = '00000000-0000-0000-0000-00000000000b'), 'B stays';
  assert exists (select 1 from public.devices where user_id = '00000000-0000-0000-0000-00000000000b'), 'B''s device stays';
end $$;
\echo 'ok - deleting the user removes everything they own, others keep theirs'

\echo 'All account deletion tests passed'
