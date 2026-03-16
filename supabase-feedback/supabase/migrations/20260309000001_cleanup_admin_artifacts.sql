-- Cleanup migration for the hackathon project.
-- Removes legacy admin artifacts if they were ever applied remotely.

DROP FUNCTION IF EXISTS public.get_cron_jobs();
DROP FUNCTION IF EXISTS public.get_cron_failures();
DROP FUNCTION IF EXISTS public.get_cron_runs();
DROP TABLE IF EXISTS public.admin_passkeys;
DROP TABLE IF EXISTS public.admin_users;
