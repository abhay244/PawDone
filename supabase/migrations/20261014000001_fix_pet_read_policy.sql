-- Creating a pet failed with "new row violates row-level security policy for table pets".
-- The app inserts and reads the pet back in one statement (insert … returning). The read
-- policy called can_access_pet(id), which looks the pet up in the same table and can't see
-- a row inserted by the statement that's running. Check the row's own columns instead.

drop policy "Read accessible pets" on public.pets;

create policy "Read accessible pets" on public.pets
  for select to authenticated
  using (
    owner_id = (select auth.uid())
    or (public.is_member_of(owner_id) and public.is_premium(owner_id))
  );
