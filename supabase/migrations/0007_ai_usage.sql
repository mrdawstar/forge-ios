-- ---------------------------------------------------------------------------
-- 0007 — what the model cost, per account, per day
-- ---------------------------------------------------------------------------
--
-- # Why this table exists
--
-- `premium_status` (0001) carries a comment that is worth re-reading before
-- touching this file:
--
--     This row does not grant anything. [...] a row a client can write is not
--     evidence of a purchase, and treating it as one would mean the
--     entitlement could be granted by anybody who can send an HTTP request.
--
-- That is exactly right, and it is the reason `forge-ai` cannot gate spending
-- on `premium_status` alone. Row-level security lets an account write its own
-- premium row — as it must, because the device is the thing that reads
-- StoreKit — so an account that flips itself to 'lifetime' would then be able
-- to spend Forge's Anthropic budget without limit. The paywall is a product
-- boundary; it was never a spend boundary, and nothing in 0001 claimed it was.
--
-- So this table is the spend boundary, and it is built to be one:
--
--   * **No client policies at all.** RLS is on and there are zero policies,
--     which under Postgres means every authenticated and anonymous request is
--     refused. Only the service role — whose key exists solely inside the edge
--     function — can read or write it. An account cannot see its own row, let
--     alone reset it.
--   * **Counted before the call, not after.** The function increments first
--     and calls Anthropic second, so a crash mid-request costs a quota slot
--     rather than an uncounted call.
--   * **Per civil day in UTC.** Not a rolling window: a rolling window needs
--     the timestamps kept, and keeping a timestamp per model call would mean
--     this table quietly became a log of when somebody uses the app. A day
--     bucket answers "has this account had its allowance" and can answer
--     nothing else.
--
-- The real entitlement check — App Store Server API verification of the
-- transaction, server-side — is the correct long-term answer and is not built.
-- Until it is, this cap is what stands between a forged premium row and an
-- unbounded bill, and it is sized so that the honest premium user never sees
-- it while an abuser gets a few cents a day.

create table if not exists public.ai_usage (
    user_id  uuid        not null references auth.users on delete cascade,
    day      date        not null default (now() at time zone 'utc')::date,
    calls    integer     not null default 0,
    primary key (user_id, day)
);

alter table public.ai_usage enable row level security;

-- Deliberately no policies. See above: this table is service-role only, and
-- the absence of a policy is the mechanism rather than an omission.

revoke all on public.ai_usage from anon, authenticated;
grant all on public.ai_usage to service_role;

-- ---------------------------------------------------------------------------
-- The one operation the function performs
-- ---------------------------------------------------------------------------
--
-- Claim a slot, or refuse. Written as a function rather than as a read then a
-- write, so two requests arriving together cannot both see the same count and
-- both decide they are under the cap. The insert-on-conflict is atomic and the
-- returned boolean is the whole answer.
--
-- `security definer` so it runs as the owner; the grant below still means only
-- the service role may call it.
--
-- The user id is a **parameter rather than `auth.uid()`**, and that is not a
-- shortcut. This is invoked by the edge function through the service role,
-- where there is no authenticated user and `auth.uid()` is null — every call
-- would collide on one null-keyed row and the cap would apply to the whole
-- world at once. The function establishes who is asking by calling
-- `auth.getUser()` against the caller's own token first, and passes that id
-- here; nothing in the request body is trusted to say who somebody is.

create or replace function public.claim_ai_call(p_user uuid, p_limit integer)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    used integer;
begin
    insert into public.ai_usage (user_id, day, calls)
    values (p_user, (now() at time zone 'utc')::date, 1)
    on conflict (user_id, day)
        do update set calls = public.ai_usage.calls + 1
    returning calls into used;

    return used <= p_limit;
end;
$$;

revoke all on function public.claim_ai_call(uuid, integer) from anon, authenticated;
grant execute on function public.claim_ai_call(uuid, integer) to service_role;

-- ---------------------------------------------------------------------------
-- Housekeeping
-- ---------------------------------------------------------------------------
--
-- Nothing here is worth keeping for more than a fortnight. Run from a cron job
-- or by hand; the table is small enough that never running it is survivable.

create or replace function public.prune_ai_usage()
returns void
language sql
security definer
set search_path = public
as $$
    delete from public.ai_usage
     where day < (now() at time zone 'utc')::date - interval '14 days';
$$;

revoke all on function public.prune_ai_usage() from anon, authenticated;
grant execute on function public.prune_ai_usage() to service_role;
