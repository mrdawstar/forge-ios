-- ---------------------------------------------------------------------------
-- 0009 — Ask Forge's own daily allowance, per user and per purchase
-- ---------------------------------------------------------------------------
--
-- # Why a separate bucket
--
-- Ask Forge (`coach`, FORGE_CONTEXT §17.6) is a conversation: somebody can ask
-- several things in a row. 0008's allowance — ten calls a day, shared by the
-- weekly reading and Plan in your own words — was sized for two features that
-- are used a few times a week. Spending it on chat would leave somebody's
-- Sunday reading refused because they asked five questions on Saturday; raising
-- it would loosen the cap on the expensive reading model too.
--
-- So the coach counts here, and only here: **30 messages a day per purchase**
-- and 30 per anonymous user, keyed exactly as 0008 keys its own:
--
--   * `p_user` from `auth.getUser()` on the caller's own JWT;
--   * `p_original_transaction_id` from the Apple-signed transaction, verified
--     offline in the edge function — never from the body or a header.
--
-- The limits are the function's constants (`DAILY_COACH_*` in handler.ts),
-- not the client's. A coach message answered by the safety screen — the 988
-- reply, or a declined topic — calls no model and claims nothing.
--
-- # The same shape as 0007 and 0008, deliberately
--
--   * Service role only: RLS on, no policies, everything revoked from PUBLIC,
--     `anon` and `authenticated` (PUBLIC included: see the fix at the end of
--     0008 for why naming only the two roles is not enough).
--   * Counted before the model is called, so a crash costs a slot rather than
--     an uncounted call.
--   * One row per key per UTC day holding a count and nothing else — no
--     timestamps, no message text, so neither table can become a log of when
--     or what somebody asked.
--   * Fails closed: invalid arguments raise, and the edge function answers a
--     raised error with 503 and no model call.
--
-- # Concurrency
--
-- Each `insert … on conflict do update … returning` takes a row lock on its
-- (key, day) row, so two concurrent messages serialise on it and each sees the
-- other's increment. There is no read-then-write window in which both can
-- decide they are under the limit. As in 0008, a request refused for the user
-- does not touch the purchase's count.

create table if not exists public.ai_coach_usage (
    user_id  uuid    not null references auth.users on delete cascade,
    day      date    not null default (now() at time zone 'utc')::date,
    calls    integer not null default 0,
    primary key (user_id, day)
);

create table if not exists public.ai_coach_usage_by_transaction (
    original_transaction_id text    not null
        check (char_length(original_transaction_id) between 1 and 64),
    day                     date    not null default (now() at time zone 'utc')::date,
    calls                   integer not null default 0,
    primary key (original_transaction_id, day)
);

alter table public.ai_coach_usage enable row level security;
alter table public.ai_coach_usage_by_transaction enable row level security;

-- Deliberately no policies. Service role only.

revoke all on public.ai_coach_usage from public, anon, authenticated;
revoke all on public.ai_coach_usage_by_transaction from public, anon, authenticated;
grant all on public.ai_coach_usage to service_role;
grant all on public.ai_coach_usage_by_transaction to service_role;

-- ---------------------------------------------------------------------------
-- The one operation the function performs for the coach
-- ---------------------------------------------------------------------------
--
-- Returns 'ok', 'user_limit' or 'transaction_limit' — the same answers as
-- `claim_ai_entitled_call`, so the edge function reads both the same way.

create or replace function public.claim_ai_coach_call(
    p_user                     uuid,
    p_user_limit               integer,
    p_original_transaction_id  text,
    p_transaction_limit        integer
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    used integer;
begin
    if p_user is null
       or p_original_transaction_id is null
       or char_length(p_original_transaction_id) not between 1 and 64
       or p_user_limit is null or p_user_limit < 0
       or p_transaction_limit is null or p_transaction_limit < 0 then
        raise exception 'claim_ai_coach_call: invalid arguments';
    end if;

    insert into public.ai_coach_usage (user_id, day, calls)
    values (p_user, (now() at time zone 'utc')::date, 1)
    on conflict (user_id, day)
        do update set calls = public.ai_coach_usage.calls + 1
    returning calls into used;

    if used > p_user_limit then
        return 'user_limit';
    end if;

    insert into public.ai_coach_usage_by_transaction (original_transaction_id, day, calls)
    values (p_original_transaction_id, (now() at time zone 'utc')::date, 1)
    on conflict (original_transaction_id, day)
        do update set calls = public.ai_coach_usage_by_transaction.calls + 1
    returning calls into used;

    if used > p_transaction_limit then
        return 'transaction_limit';
    end if;
    return 'ok';
end;
$$;

revoke all on function public.claim_ai_coach_call(uuid, integer, text, integer)
    from public, anon, authenticated;
grant execute on function public.claim_ai_coach_call(uuid, integer, text, integer)
    to service_role;

-- ---------------------------------------------------------------------------
-- Housekeeping, now covering all four tables
-- ---------------------------------------------------------------------------
--
-- `create or replace` keeps the grants 0008 set on this function (service role
-- only); they are restated below all the same, so this file alone says who may
-- run it.

create or replace function public.prune_ai_usage()
returns void
language sql
security definer
set search_path = public
as $$
    delete from public.ai_usage
     where day < (now() at time zone 'utc')::date - interval '14 days';
    delete from public.ai_usage_by_transaction
     where day < (now() at time zone 'utc')::date - interval '14 days';
    delete from public.ai_coach_usage
     where day < (now() at time zone 'utc')::date - interval '14 days';
    delete from public.ai_coach_usage_by_transaction
     where day < (now() at time zone 'utc')::date - interval '14 days';
$$;

revoke all on function public.prune_ai_usage() from public, anon, authenticated;
grant execute on function public.prune_ai_usage() to service_role;
