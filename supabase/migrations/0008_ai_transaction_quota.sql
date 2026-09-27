-- ---------------------------------------------------------------------------
-- 0008 — a daily quota per Premium purchase, on top of the one per user
-- ---------------------------------------------------------------------------
--
-- # Why a second key
--
-- The app has no visible account (FORGE_CONTEXT §2n). It reaches `forge-ai`
-- with an invisible *anonymous* Supabase user, and anybody can mint as many of
-- those as they like. So 0007's per-user cap, on its own, no longer bounds
-- anything: one Premium purchase could drive any number of fresh identities,
-- each with a full allowance.
--
-- The thing that cannot be multiplied is the purchase. `forge-ai` verifies the
-- StoreKit 2 transaction the app sends (offline, against Apple Root CA G3 —
-- see `supabase/functions/forge-ai/storekit.ts`) and reads its
-- `originalTransactionId` **from the verified payload**. That id is stable
-- across renewals and restores, so it names the purchase rather than the
-- device or the install, and it is the key here. Nothing a client writes is
-- ever used as this key.
--
-- Both caps apply to every call. `claim_ai_entitled_call` takes the per-user
-- slot through 0007's `claim_ai_call`, then the per-purchase slot, in one
-- transaction.
--
-- # The same shape as 0007, deliberately
--
--   * Service role only: RLS on, no policies, revoked from every client role
--     *and from PUBLIC* (see the fix at the end of this file).
--   * Counted before the model is called, so a crash costs a slot rather than
--     an uncounted call.
--   * One row per purchase per UTC day, holding a count and nothing else — no
--     timestamps, so this cannot become a log of when somebody uses the app.
--
-- # Concurrency
--
-- `insert … on conflict do update … returning` takes a row lock on the
-- (key, day) row, so two concurrent requests serialise on it and each sees
-- the other's increment. There is no read-then-write window in which both can
-- decide they are under the limit.

create table if not exists public.ai_usage_by_transaction (
    original_transaction_id text    not null
        check (char_length(original_transaction_id) between 1 and 64),
    day                     date    not null default (now() at time zone 'utc')::date,
    calls                   integer not null default 0,
    primary key (original_transaction_id, day)
);

alter table public.ai_usage_by_transaction enable row level security;

-- Deliberately no policies. Service role only.

revoke all on public.ai_usage_by_transaction from public, anon, authenticated;
grant all on public.ai_usage_by_transaction to service_role;

-- ---------------------------------------------------------------------------
-- The one operation the function performs
-- ---------------------------------------------------------------------------
--
-- Returns 'ok', 'user_limit' or 'transaction_limit'.
--
-- Both parameters that name somebody come from verified sources inside the
-- edge function: `p_user` from `auth.getUser()` on the caller's JWT, and
-- `p_original_transaction_id` from the Apple-signed transaction. The limits
-- are the function's constants, not the client's.
--
-- If the per-user cap is already spent, the purchase's count is not touched:
-- a request refused for one reason should not also spend the other allowance.

create or replace function public.claim_ai_entitled_call(
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
        raise exception 'claim_ai_entitled_call: invalid arguments';
    end if;

    if not public.claim_ai_call(p_user, p_user_limit) then
        return 'user_limit';
    end if;

    insert into public.ai_usage_by_transaction (original_transaction_id, day, calls)
    values (p_original_transaction_id, (now() at time zone 'utc')::date, 1)
    on conflict (original_transaction_id, day)
        do update set calls = public.ai_usage_by_transaction.calls + 1
    returning calls into used;

    if used > p_transaction_limit then
        return 'transaction_limit';
    end if;
    return 'ok';
end;
$$;

revoke all on function public.claim_ai_entitled_call(uuid, integer, text, integer)
    from public, anon, authenticated;
grant execute on function public.claim_ai_entitled_call(uuid, integer, text, integer)
    to service_role;

-- ---------------------------------------------------------------------------
-- Housekeeping, now covering both tables
-- ---------------------------------------------------------------------------

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
$$;

-- ---------------------------------------------------------------------------
-- A fix to 0007
-- ---------------------------------------------------------------------------
--
-- Postgres grants EXECUTE on every new function to PUBLIC, and 0007 revoked it
-- only from `anon` and `authenticated` — which are members of PUBLIC, so the
-- grant still reached them. A client could therefore call `claim_ai_call` over
-- `/rest/v1/rpc` with somebody else's user id and spend their allowance. It
-- could never *raise* anybody's allowance, so this was never a spend leak; it
-- is closed here all the same.

revoke all on function public.claim_ai_call(uuid, integer) from public, anon, authenticated;
grant execute on function public.claim_ai_call(uuid, integer) to service_role;

revoke all on function public.prune_ai_usage() from public, anon, authenticated;
grant execute on function public.prune_ai_usage() to service_role;
