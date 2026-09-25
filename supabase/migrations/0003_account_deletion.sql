-- Deleting an account, from inside the app.
--
-- App Store Review Guideline 5.1.1(v): an app that lets somebody create an
-- account has to let them delete it from inside the app, in about as many taps
-- as it took to make one. Forge had no such path at all — Settings offered
-- "Sign Out" and nothing else — which is a rejection rather than an oversight,
-- and no amount of client code fixes it, because deleting a row of `auth.users`
-- is not something `authenticated` may do.
--
-- Nor should it be. A grant that let a client delete from `auth.users` would
-- let it delete from `auth.users`, full stop — everybody's, not just its own.
-- So this is the only `security definer` function in the schema besides the
-- signup trigger, and it is written to deserve that:
--
--   * It takes no arguments. There is nothing to pass, and therefore nothing to
--     pass wrongly, and no id a caller can substitute for somebody else's.
--   * The one id it will ever delete is `auth.uid()`, which is read out of the
--     JWT that PostgREST has already verified. A client cannot forge it; it is
--     the same value every RLS policy in `0001` is built on.
--   * `set search_path = ''` and fully-qualified names throughout, so nothing
--     it calls can be shadowed by a schema somebody else can write to. That is
--     the standard way a definer function gets hijacked, and it is closed here.
--
-- Everything else follows from the foreign keys rather than from a list. All
-- seven tables reference `auth.users on delete cascade`, so one delete takes
-- the profile, the devices, the activities, the rituals, the mornings, the
-- blades and the premium row with it. Spelling them out here would be a second
-- list to keep in step with the first, and the day it fell behind would be the
-- day somebody's mornings survived their account.

create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller uuid := auth.uid();
begin
    -- Raised rather than returned quietly. `delete ... where id = null` matches
    -- no row and succeeds, which would tell an unauthenticated caller that
    -- their account had been deleted.
    if caller is null then
        raise exception 'delete_account requires an authenticated caller'
            using errcode = '28000';
    end if;

    delete from auth.users where id = caller;
end;
$$;

-- The definer's rights are the entire privilege here, so the function must not
-- be reachable by anybody who is not carrying a verified token. `public` is
-- revoked as well as `anon`: a function is executable by `public` by default,
-- and leaving that in place would undo the line below it.
revoke all on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;

-- Definer functions run as their owner, and the owner has to be a role that may
-- delete from `auth.users`. Tables created by `supabase db push` come out owned
-- by the CLI's migration role rather than by `postgres` — that is the whole
-- reason `0002` exists — so the owner is set explicitly instead of inherited.
--
-- If this line fails when the migration is pushed, that is the useful outcome
-- rather than the bad one: a function that cannot be reassigned is one that
-- would not have worked, and finding out here beats finding out from the first
-- person who tried to delete their account. Run it once from the SQL editor,
-- which connects as an admin role.
alter function public.delete_account() owner to postgres;
