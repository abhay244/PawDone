-- Account deletion (App Store guideline 5.1.1(v)). The delete-account Edge Function
-- calls prepare_account_deletion(), removes the returned photos through the Storage
-- API (Storage files can't be deleted with SQL), then deletes the auth user. Every
-- table references auth.users with on delete cascade or set null, so that removes the
-- rest: profile, devices, entitlement, owned pets with their schedules and history,
-- household memberships, invites and notification settings.

-- Proof photos to delete for an account: everything in the folders of pets the user
-- owns (including photos helpers took), and every photo the user took for other
-- households. For the latter, the occurrences in those households keep their
-- check-off but lose the photo reference.
create function public.prepare_account_deletion(p_user_id uuid)
returns setof text
language plpgsql security definer set search_path = ''
as $$
begin
  update public.task_occurrences o
  set photo_path = null
  from public.pets p
  where p.id = o.pet_id
    and o.completed_by = p_user_id
    and o.photo_path is not null
    and p.owner_id <> p_user_id;

  return query
  select o.name
  from storage.objects o
  where o.bucket_id = 'proof-photos'
    and (
      o.owner_id = p_user_id::text
      or public.proof_photo_pet_id(o.name) in (select id from public.pets where owner_id = p_user_id)
    );
end;
$$;

revoke execute on function public.prepare_account_deletion(uuid) from public, anon, authenticated;
grant execute on function public.prepare_account_deletion(uuid) to service_role;
