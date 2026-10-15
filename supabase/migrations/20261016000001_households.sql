-- Households: short invite codes, previews before joining, membership status, and shared
-- photo proof in Storage for Premium households.

-- ─── Invite codes ───────────────────────────────────────────────────────────

-- 8 characters from 32 without look-alikes (no 0/O or 1/I), e.g. K7P2QX9M.
-- 40 random bits; invites are single-use and expire after 7 days.
create function public.new_invite_code()
returns text
language plpgsql volatile set search_path = ''
as $$
declare
  alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  -- Fully random bytes of a v4 UUID (6 and 8 carry version and variant bits).
  positions constant integer[] := array[0, 1, 2, 3, 4, 5, 9, 10];
  bytes bytea := uuid_send(gen_random_uuid());
  code text := '';
  position integer;
begin
  foreach position in array positions loop
    code := code || substr(alphabet, (get_byte(bytes, position) % 32) + 1, 1);
  end loop;
  return code;
end;
$$;

alter table public.invites alter column token set default public.new_invite_code();

-- Codes are typed by people: ignore case, spaces and dashes.
create function public.normalize_invite_code(p_code text)
returns text
language sql immutable set search_path = ''
as $$
  select upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
$$;

create or replace function public.accept_invite(p_token text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_invite  public.invites;
begin
  if v_user_id is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;

  select * into v_invite from public.invites
  where upper(token) = public.normalize_invite_code(p_token)
  for update;
  if not found or v_invite.accepted_at is not null or v_invite.expires_at <= now() then
    raise exception 'This invite code is invalid or has expired' using errcode = 'P0001';
  end if;
  if v_invite.owner_id = v_user_id then
    raise exception 'You can''t join your own household' using errcode = 'P0001';
  end if;
  if not public.is_premium(v_invite.owner_id) then
    raise exception 'This invite is no longer active' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.household_members where owner_id = v_invite.owner_id and member_id = v_user_id) then
    raise exception 'You''re already in this household' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('household:' || v_invite.owner_id::text, 0));

  if (select count(*) from public.household_members where owner_id = v_invite.owner_id) >= 2 then
    raise exception 'This household is full' using errcode = 'P0001';
  end if;

  insert into public.household_members (owner_id, member_id) values (v_invite.owner_id, v_user_id);
  update public.invites set accepted_by = v_user_id, accepted_at = now() where id = v_invite.id;
  return v_invite.owner_id;
end;
$$;

-- What an invite code is for, shown before joining. Empty when the code can't be used.
create function public.invite_details(p_code text)
returns table (owner_name text, pet_name text, pet_species public.pet_species)
language sql stable security definer set search_path = ''
as $$
  select coalesce(nullif(pr.name, ''), 'Someone'), p.name, p.species
  from public.invites i
  join public.profiles pr on pr.id = i.owner_id
  left join public.pets p on p.owner_id = i.owner_id
  where upper(i.token) = public.normalize_invite_code(p_code)
    and i.accepted_at is null
    and i.expires_at > now()
    and public.is_premium(i.owner_id)
    and auth.uid() is not null;
$$;

-- ─── Membership status ──────────────────────────────────────────────────────

-- Households the user helps in. `active` is false while the owner has no Premium; the pet
-- is then hidden by row level security, so its name comes from here.
create function public.my_households()
returns table (owner_id uuid, owner_name text, pet_id uuid, pet_name text, active boolean)
language sql stable security definer set search_path = ''
as $$
  select hm.owner_id, coalesce(nullif(pr.name, ''), 'Someone'), p.id, p.name, public.is_premium(hm.owner_id)
  from public.household_members hm
  join public.profiles pr on pr.id = hm.owner_id
  left join public.pets p on p.owner_id = hm.owner_id
  where hm.member_id = auth.uid()
  order by hm.joined_at;
$$;

-- Whether the pet's household has Premium (sharing and cloud photos). False when the
-- user can't see the pet.
create function public.pet_has_premium(p_pet_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.can_access_pet(p_pet_id)
     and public.is_premium((select owner_id from public.pets where id = p_pet_id));
$$;

-- ─── Photo proof in Storage (Premium) ───────────────────────────────────────

-- Objects are stored as <pet_id>/<occurrence_id>.jpg. Free plans keep photos on the phone.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('proof-photos', 'proof-photos', false, 5242880, array['image/jpeg'])
on conflict (id) do nothing;

-- The pet an object path belongs to, or null for anything else.
create function public.proof_photo_pet_id(p_name text)
returns uuid
language sql immutable set search_path = ''
as $$
  select case
    when split_part(p_name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then split_part(p_name, '/', 1)::uuid
  end;
$$;

create policy "Household reads proof photos" on storage.objects
  for select to authenticated
  using (bucket_id = 'proof-photos' and public.can_access_pet(public.proof_photo_pet_id(name)));

create policy "Premium household uploads proof photos" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'proof-photos' and public.pet_has_premium(public.proof_photo_pet_id(name)));

-- Retaking a photo overwrites it.
create policy "Uploader replaces own proof photos" on storage.objects
  for update to authenticated
  using (bucket_id = 'proof-photos' and owner_id = (select auth.uid()::text))
  with check (bucket_id = 'proof-photos' and public.pet_has_premium(public.proof_photo_pet_id(name)));

-- Undoing a check-off deletes its photo.
create policy "Uploader deletes own proof photos" on storage.objects
  for delete to authenticated
  using (bucket_id = 'proof-photos' and owner_id = (select auth.uid()::text));

-- ─── Function permissions ───────────────────────────────────────────────────

revoke execute on function
  public.invite_details(text),
  public.my_households(),
  public.pet_has_premium(uuid)
from public, anon;

grant execute on function
  public.invite_details(text),
  public.my_households(),
  public.pet_has_premium(uuid)
to authenticated;

revoke execute on function public.new_invite_code() from public, anon, authenticated;
