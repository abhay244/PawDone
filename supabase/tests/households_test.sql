-- Household tests: invite codes, joining, membership status and photo proof in Storage.
-- Run with supabase/tests/run.sh.
--
-- Users: A = "Asha", owner with Premium (…0a), B = "Sam", helper (…0b),
--        C = outsider (…0c), D = "Dev", owner on the Free plan (…0d)

\set ON_ERROR_STOP on
\o /dev/null

insert into auth.users (id, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', '{"full_name": "Asha"}'),
  ('00000000-0000-0000-0000-00000000000b', '{"full_name": "Sam"}'),
  ('00000000-0000-0000-0000-00000000000c', '{}'),
  ('00000000-0000-0000-0000-00000000000d', '{"full_name": "Dev"}');

insert into public.entitlements (user_id, is_premium, expires_at)
values ('00000000-0000-0000-0000-00000000000a', true, now() + interval '30 days');

insert into public.pets (owner_id, name, species, timezone) values
  ('00000000-0000-0000-0000-00000000000a', 'Bruno', 'dog', 'UTC'),
  ('00000000-0000-0000-0000-00000000000d', 'Milo', 'cat', 'UTC');

insert into tests.vars
select lower(name), id::text from public.pets;

-- ─── Invite codes ───────────────────────────────────────────────────────────

do $$
declare
  codes text[] := array(select public.new_invite_code() from generate_series(1, 200));
begin
  assert (select bool_and(code ~ '^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{8}$') from unnest(codes) code),
    'codes are 8 characters without look-alikes';
  assert (select count(distinct code) from unnest(codes) code) = 200, 'codes are random';
end $$;

select tests.login('00000000-0000-0000-0000-00000000000a', null);
set role authenticated;
insert into tests.vars select 'code1', token from public.create_invite();
insert into tests.vars select 'code2', token from public.create_invite();
\echo 'ok - invite codes are short and readable'

-- ─── Preview and joining ────────────────────────────────────────────────────

reset role;
select tests.login('00000000-0000-0000-0000-00000000000b', null);
set role authenticated;
do $$
declare
  -- Typed casually: lower case with a space in the middle.
  typed text := lower(left(tests.var('code1'), 4) || ' ' || right(tests.var('code1'), 4));
begin
  assert (select owner_name || ' / ' || pet_name || ' / ' || pet_species from public.invite_details(typed))
       = 'Asha / Bruno / dog', 'preview names the owner and pet';
  assert (select count(*) from public.invite_details('NOTACODE')) = 0, 'unknown codes show nothing';
  assert public.accept_invite(typed) = '00000000-0000-0000-0000-00000000000a', 'joins with a casually typed code';
  assert (select count(*) from public.invite_details(tests.var('code1'))) = 0, 'used codes show nothing';
end $$;
select tests.expect_error(
  format('select public.accept_invite(%L)', tests.var('code2')),
  'You''re already in this household');

reset role;
select set_config('request.jwt.claims', '', false);
set role anon;
select tests.expect_error(
  format('select * from public.invite_details(%L)', tests.var('code2')),
  'permission denied for function invite_details');
\echo 'ok - preview before joining, codes ignore case and spaces'

-- ─── Membership status ──────────────────────────────────────────────────────

reset role;
select tests.login('00000000-0000-0000-0000-00000000000b', null);
set role authenticated;
do $$ begin
  assert (select owner_name || ' / ' || pet_name || ' / ' || active from public.my_households())
       = 'Asha / Bruno / true', 'helper sees the household';
  assert public.pet_has_premium(tests.var('bruno')::uuid), 'helper sees Premium on the shared pet';
  assert not public.pet_has_premium(tests.var('milo')::uuid), 'nothing about pets they can''t see';
end $$;

reset role;
select tests.login('00000000-0000-0000-0000-00000000000d', null);
set role authenticated;
do $$ begin
  assert not public.pet_has_premium(tests.var('milo')::uuid), 'Free plan';
  assert (select count(*) from public.my_households()) = 0, 'no households';
end $$;

reset role;
update public.entitlements set expires_at = now() - interval '1 day';
select tests.login('00000000-0000-0000-0000-00000000000b', null);
set role authenticated;
do $$ begin
  assert (select pet_name || ' / ' || active from public.my_households()) = 'Bruno / false',
    'paused households still show their pet''s name';
  assert (select count(*) from public.pets) = 0, 'but the pet itself is hidden';
end $$;
reset role;
update public.entitlements set expires_at = now() + interval '30 days';
\echo 'ok - helpers see their households, paused when Premium ends'

-- ─── Photo proof in Storage ─────────────────────────────────────────────────

-- B (helper, Premium household) uploads a photo for Bruno.
select tests.login('00000000-0000-0000-0000-00000000000b', null);
set role authenticated;
insert into storage.objects (bucket_id, name)
select 'proof-photos', tests.var('bruno') || '/11111111-1111-1111-1111-111111111111.jpg';

reset role;
select tests.login('00000000-0000-0000-0000-00000000000a', null);
set role authenticated;
do $$ begin
  assert (select count(*) from storage.objects) = 1, 'the owner sees the helper''s photo';
  delete from storage.objects;
  assert (select count(*) from storage.objects) = 1, 'only the uploader can delete it';
end $$;

reset role;
select tests.login('00000000-0000-0000-0000-00000000000c', null);
set role authenticated;
do $$ begin
  assert (select count(*) from storage.objects) = 0, 'outsiders can''t see it';
end $$;
select tests.expect_error(
  format($$insert into storage.objects (bucket_id, name) values ('proof-photos', %L)$$, tests.var('bruno') || '/x.jpg'),
  'new row violates row-level security policy%');

reset role;
select tests.login('00000000-0000-0000-0000-00000000000d', null);
set role authenticated;
select tests.expect_error(
  format($$insert into storage.objects (bucket_id, name) values ('proof-photos', %L)$$, tests.var('milo') || '/x.jpg'),
  'new row violates row-level security policy%');
select tests.expect_error(
  $$insert into storage.objects (bucket_id, name) values ('proof-photos', 'not-a-pet/x.jpg')$$,
  'new row violates row-level security policy%');

-- Premium ends: the helper loses the photos, the owner keeps them.
reset role;
update public.entitlements set expires_at = now() - interval '1 day';
select tests.login('00000000-0000-0000-0000-00000000000b', null);
set role authenticated;
do $$ begin
  assert (select count(*) from storage.objects) = 0, 'helpers lose photos when Premium ends';
end $$;
reset role;
select tests.login('00000000-0000-0000-0000-00000000000a', null);
set role authenticated;
do $$ begin
  assert (select count(*) from storage.objects) = 1, 'the owner keeps them';
end $$;

reset role;
update public.entitlements set expires_at = now() + interval '30 days';
select tests.login('00000000-0000-0000-0000-00000000000b', null);
set role authenticated;
do $$ begin
  delete from storage.objects;
  assert (select count(*) from storage.objects) = 0, 'the uploader can delete their photo';
end $$;
\echo 'ok - photo proof shared within Premium households only'

\echo 'All household tests passed'
