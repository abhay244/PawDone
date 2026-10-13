-- Scheduled jobs. Needs the pg_cron extension (Supabase dashboard → Integrations → Cron).

create extension if not exists pg_cron;

-- Keep two days of occurrences ready ahead of time in every timezone.
select cron.schedule('pawdone-generate-occurrences', '5 * * * *', $$select public.generate_occurrences()$$);

-- Every 15 minutes, so 30- and 45-minute timezone offsets are covered soon after midnight.
select cron.schedule('pawdone-mark-missed', '*/15 * * * *', $$select public.mark_missed_occurrences()$$);
