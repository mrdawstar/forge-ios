-- Tests for migration 0009 (Ask Forge's quota), run against a throwaway
-- Postgres with 0007, 0008 and 0009 applied — never against the project.
-- See supabase/README.md §2 for the runner. Every check raises on failure, so
-- `psql -v ON_ERROR_STOP=1` exits non-zero on the first one that does.

\set ON_ERROR_STOP 1

-- Fresh counts for this run.
truncate public.ai_coach_usage, public.ai_coach_usage_by_transaction,
         public.ai_usage, public.ai_usage_by_transaction;
delete from auth.users;
insert into auth.users (id) values
  ('00000000-0000-4000-8000-00000000000a'),
  ('00000000-0000-4000-8000-00000000000b'),
  ('00000000-0000-4000-8000-00000000000c');

do $$
declare
  a uuid := '00000000-0000-4000-8000-00000000000a';
  b uuid := '00000000-0000-4000-8000-00000000000b';
  c uuid := '00000000-0000-4000-8000-00000000000c';
  answer text;
  i integer;
  ok_count integer := 0;
begin
  -- 1. Thirty a day for one purchase, then transaction_limit.
  for i in 1..30 loop
    answer := public.claim_ai_coach_call(a, 30, 'otid-1', 30);
    if answer <> 'ok' then raise exception 'call % was %, expected ok', i, answer; end if;
  end loop;
  answer := public.claim_ai_coach_call(a, 30, 'otid-1', 30);
  -- The user's own count is now 31 > 30, so the user limit answers first.
  if answer <> 'user_limit' then raise exception '31st on one user was %, expected user_limit', answer; end if;

  -- 2. One purchase across many anonymous users is still thirty.
  answer := public.claim_ai_coach_call(b, 30, 'otid-1', 30);
  if answer <> 'transaction_limit' then raise exception 'a second user on a spent purchase got %', answer; end if;

  -- 3. A user refused for their own limit does not spend the purchase's.
  if (select calls from public.ai_coach_usage_by_transaction where original_transaction_id = 'otid-2') is not null then
    raise exception 'otid-2 should have no row yet';
  end if;
  answer := public.claim_ai_coach_call(a, 30, 'otid-2', 30);
  if answer <> 'user_limit' then raise exception 'spent user on a new purchase got %', answer; end if;
  if exists (select 1 from public.ai_coach_usage_by_transaction where original_transaction_id = 'otid-2') then
    raise exception 'a user_limit refusal spent the purchase''s allowance';
  end if;

  -- 4. The coach's bucket is separate from 0008's: none of the above touched it.
  if exists (select 1 from public.ai_usage) or exists (select 1 from public.ai_usage_by_transaction) then
    raise exception 'the coach spent the reading/plan allowance';
  end if;
  answer := public.claim_ai_entitled_call(a, 10, 'otid-1', 10);
  if answer <> 'ok' then raise exception 'the reading/plan allowance was refused after coach use: %', answer; end if;

  -- 5. And the other way round: a spent reading/plan allowance leaves the coach alone.
  for i in 1..10 loop perform public.claim_ai_entitled_call(c, 10, 'otid-3', 10); end loop;
  answer := public.claim_ai_coach_call(c, 30, 'otid-3', 30);
  if answer <> 'ok' then raise exception 'coach refused after the reading/plan allowance was spent: %', answer; end if;

  -- 6. Fails closed on bad arguments.
  begin perform public.claim_ai_coach_call(null, 30, 'otid-4', 30); raise exception 'null user accepted';
  exception when raise_exception then if sqlerrm not like 'claim_ai_coach_call: invalid arguments%' then raise; end if; end;
  begin perform public.claim_ai_coach_call(c, 30, '', 30); raise exception 'empty otid accepted';
  exception when raise_exception then if sqlerrm not like 'claim_ai_coach_call: invalid arguments%' then raise; end if; end;
  begin perform public.claim_ai_coach_call(c, 30, repeat('x', 65), 30); raise exception 'long otid accepted';
  exception when raise_exception then if sqlerrm not like 'claim_ai_coach_call: invalid arguments%' then raise; end if; end;
  begin perform public.claim_ai_coach_call(c, -1, 'otid-4', 30); raise exception 'negative limit accepted';
  exception when raise_exception then if sqlerrm not like 'claim_ai_coach_call: invalid arguments%' then raise; end if; end;
  begin perform public.claim_ai_coach_call(c, 30, 'otid-4', null); raise exception 'null limit accepted';
  exception when raise_exception then if sqlerrm not like 'claim_ai_coach_call: invalid arguments%' then raise; end if; end;

  -- 7. A zero limit refuses everything (what an unconfigured constant would do).
  answer := public.claim_ai_coach_call(c, 30, 'otid-5', 0);
  if answer <> 'transaction_limit' then raise exception 'zero limit answered %', answer; end if;
end $$;

-- 8. Service role only: nothing reaches a client role, PUBLIC included.
do $$
begin
  if has_function_privilege('anon', 'public.claim_ai_coach_call(uuid,integer,text,integer)', 'execute')
     or has_function_privilege('authenticated', 'public.claim_ai_coach_call(uuid,integer,text,integer)', 'execute')
     or has_function_privilege('public', 'public.claim_ai_coach_call(uuid,integer,text,integer)', 'execute') then
    raise exception 'claim_ai_coach_call is executable by a client role';
  end if;
  if not has_function_privilege('service_role', 'public.claim_ai_coach_call(uuid,integer,text,integer)', 'execute') then
    raise exception 'service_role cannot run claim_ai_coach_call';
  end if;
  if has_function_privilege('anon', 'public.prune_ai_usage()', 'execute')
     or has_function_privilege('public', 'public.prune_ai_usage()', 'execute') then
    raise exception 'prune_ai_usage is executable by a client role';
  end if;
  if has_table_privilege('anon', 'public.ai_coach_usage', 'select')
     or has_table_privilege('authenticated', 'public.ai_coach_usage', 'select')
     or has_table_privilege('authenticated', 'public.ai_coach_usage_by_transaction', 'insert')
     or has_table_privilege('anon', 'public.ai_coach_usage_by_transaction', 'update') then
    raise exception 'a client role can reach a coach usage table';
  end if;
  if exists (select 1 from pg_tables where schemaname = 'public'
             and tablename in ('ai_coach_usage', 'ai_coach_usage_by_transaction') and not rowsecurity) then
    raise exception 'RLS is off on a coach usage table';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public'
             and tablename in ('ai_coach_usage', 'ai_coach_usage_by_transaction')) then
    raise exception 'a coach usage table has a policy';
  end if;
end $$;

-- 9. Housekeeping prunes all four tables.
insert into public.ai_coach_usage (user_id, day, calls)
  values ('00000000-0000-4000-8000-00000000000b', current_date - 30, 3);
insert into public.ai_coach_usage_by_transaction (original_transaction_id, day, calls)
  values ('old', current_date - 30, 3);
select public.prune_ai_usage();
do $$
begin
  if exists (select 1 from public.ai_coach_usage where day < current_date - 14)
     or exists (select 1 from public.ai_coach_usage_by_transaction where day < current_date - 14) then
    raise exception 'prune_ai_usage left old coach rows';
  end if;
end $$;

select 'ai_coach_quota tests passed' as result;
