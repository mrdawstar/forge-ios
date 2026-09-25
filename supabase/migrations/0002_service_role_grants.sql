-- Give service_role access to the app's tables.
--
-- Found against the live project rather than by reading anything: an admin
-- request for a profile row came back `42501 permission denied for table
-- profiles`, with Postgres helpfully suggesting the exact grant missing.
--
-- The cause is worth writing down, because it is not obvious and it very nearly
-- took the app with it. Supabase's default privileges — the ones that quietly
-- grant `anon`, `authenticated` and `service_role` access to everything in
-- `public` — are attached to the `postgres` role. Tables created by
-- `supabase db push` are owned by the temporary migration role the CLI creates,
-- so none of those defaults applied and every one of these seven tables came up
-- reachable by nobody at all.
--
-- `0001` grants `authenticated` explicitly, which is the only reason the app
-- works; without it every sync would have returned 403, which Forge classifies
-- as its own bug rather than a condition to wait out, so it would have failed
-- permanently and never retried. It missed `service_role`, which is what the
-- Dashboard's table editor, the admin API and any future Edge Function run as.
--
-- `0001` now grants both. This migration exists because that project was
-- already migrated, and an applied migration does not run again. Both are
-- idempotent, so a fresh project running 0001 then 0002 simply grants twice.

do $$
declare
    t text;
begin
    foreach t in array array[
        'profiles', 'devices', 'activities', 'rituals',
        'mornings', 'blades', 'premium_status'
    ] loop
        execute format('grant all on public.%I to service_role', t);
    end loop;
end;
$$;

grant usage on schema public to service_role;
