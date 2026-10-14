-- Push notifications: task reminders and "task done" alerts.
-- The send-push Edge Function calls claim_push_notifications() every minute and delivers
-- the results through Apple Push Notification service (APNs).

-- Debug builds from Xcode get sandbox tokens; TestFlight and App Store builds get
-- production tokens. APNs has a separate endpoint for each.
alter table public.devices
  add column apns_environment text not null default 'production'
  check (apns_environment in ('sandbox', 'production'));

-- "Task done" alerts waiting to be sent. Filled by a trigger, emptied by
-- claim_push_notifications(). No policies: only the service role can read it.
create table public.push_outbox (
  id            bigint generated always as identity primary key,
  occurrence_id uuid not null references public.task_occurrences (id) on delete cascade,
  actor_id      uuid references auth.users (id) on delete set null,
  created_at    timestamptz not null default now(),
  sent_at       timestamptz
);

create index push_outbox_unsent on public.push_outbox (created_at) where sent_at is null;

alter table public.push_outbox enable row level security;
revoke all on public.push_outbox from anon, authenticated;

create function public.queue_completion_push()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.status = 'done' and old.status is distinct from 'done' then
    insert into public.push_outbox (occurrence_id, actor_id) values (new.id, new.completed_by);
  end if;
  return null;
end;
$$;

create trigger queue_completion_push
  after update of status on public.task_occurrences
  for each row execute function public.queue_completion_push();

-- Saves this phone's push token (or clears it with null).
create function public.set_push_token(p_device_id text, p_token text, p_environment text default 'production')
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  if p_environment not in ('sandbox', 'production') then
    raise exception 'Invalid environment' using errcode = '22023';
  end if;

  update public.devices
  set apns_token = p_token, apns_environment = p_environment
  where user_id = v_user_id and device_id = p_device_id and is_active;

  -- A token belongs to one phone and one account; drop it anywhere else (e.g. after
  -- someone else signs in on the same phone).
  if p_token is not null then
    update public.devices
    set apns_token = null
    where apns_token = p_token and not (user_id = v_user_id and device_id = p_device_id);
  end if;
end;
$$;

-- Phones that should hear about a pet: the owner's, plus household members' while the
-- owner has Premium. For reminders, people who turned reminders off for the pet are left out.
create function public.push_recipients(p_pet_id uuid, p_for_reminder boolean)
returns table (user_id uuid, token text, environment text)
language sql stable security definer set search_path = ''
as $$
  select d.user_id, d.apns_token, d.apns_environment
  from public.pets p
  cross join lateral (
    select p.owner_id as user_id
    union
    select hm.member_id
    from public.household_members hm
    where hm.owner_id = p.owner_id and public.is_premium(p.owner_id)
  ) people
  join public.devices d on d.user_id = people.user_id and d.is_active and d.apns_token is not null
  where p.id = p_pet_id
    and (
      not p_for_reminder
      or coalesce(
        (select np.reminders_enabled from public.notification_prefs np
         where np.user_id = people.user_id and np.pet_id = p.id),
        true
      )
    );
$$;

-- Returns the notifications to send now, and marks them so they're sent only once.
--   Reminders: pending tasks that came due in the last 10 minutes, with the task's
--     reminder on. Older ones are skipped rather than sent late.
--   Completions: everyone in the household except the person who did the task, if the
--     task is still done.
create function public.claim_push_notifications()
returns table (kind text, token text, environment text, title text, body text, thread_id text)
language plpgsql security definer set search_path = ''
as $$
begin
  return query
  with due as (
    update public.task_occurrences o
    set reminder_sent_at = now()
    from public.tasks t
    where t.id = o.task_id
      and t.reminder_enabled
      and o.status = 'pending'
      and o.reminder_sent_at is null
      and o.scheduled_at <= now()
      and o.scheduled_at > now() - interval '10 minutes'
    returning o.pet_id, o.title
  )
  select 'reminder', r.token, r.environment, p.name, due.title || ' is due now.', p.id::text
  from due
  join public.pets p on p.id = due.pet_id
  cross join lateral public.push_recipients(p.id, true) r;

  return query
  with sent as (
    update public.push_outbox b
    set sent_at = now()
    where b.sent_at is null and b.created_at > now() - interval '1 hour'
    returning b.occurrence_id, b.actor_id
  )
  select 'completed', r.token, r.environment, p.name,
         coalesce(nullif(pr.name, ''), 'Someone') || ' marked ' || o.title || ' as done.',
         p.id::text
  from sent
  join public.task_occurrences o on o.id = sent.occurrence_id and o.status = 'done'
  join public.pets p on p.id = o.pet_id
  left join public.profiles pr on pr.id = sent.actor_id
  cross join lateral public.push_recipients(p.id, false) r
  where r.user_id is distinct from sent.actor_id;
end;
$$;

-- Drops tokens APNs reports as no longer valid.
create function public.forget_push_tokens(p_tokens text[])
returns void
language sql security definer set search_path = ''
as $$
  update public.devices set apns_token = null where apns_token = any (p_tokens);
$$;

revoke execute on function public.set_push_token(text, text, text) from public, anon;
grant execute on function public.set_push_token(text, text, text) to authenticated;

-- Server-only: the trigger and the send-push function (service role).
revoke execute on function
  public.queue_completion_push(),
  public.push_recipients(uuid, boolean),
  public.claim_push_notifications(),
  public.forget_push_tokens(text[])
from public, anon, authenticated;

grant execute on function
  public.claim_push_notifications(),
  public.forget_push_tokens(text[])
to service_role;
