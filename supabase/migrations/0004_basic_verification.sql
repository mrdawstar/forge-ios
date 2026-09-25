-- Let an activity be confirmed by a plain checkbox.
--
-- `VerificationMethod` gained a third case, `basic`, and `0001` wrote the two
-- it had at the time into a check constraint:
--
--     verification text check (verification in ('health', 'honor'))
--
-- That constraint is the only thing standing between the feature and a silent
-- data-loss bug, and it is worth being precise about which one. Nothing on the
-- device breaks without this: the app is local-first, the new value round-trips
-- through `UserDefaults` perfectly well, and somebody who never signs in never
-- meets any of it. What breaks is the **push** for somebody who has — the
-- insert for that one row comes back `23514 new row violates check
-- constraint`, and since a sync pushes activities as a batch, one activity
-- marked Basic Check is enough to fail the whole upload. The account would then
-- be permanently one failed request behind, and the failure is a schema error
-- rather than a network one, which the sync engine treats as permanent.
--
-- So this has to be applied *before* a build carrying `basic` is shipped, not
-- alongside it. The order is the safe one either way round for existing
-- clients: an old build never writes 'basic' and is unaffected by a wider
-- constraint, so there is no window in which the two disagree destructively.
--
-- Completions are unaffected and deliberately so. Those live in `mornings.rituals`
-- as jsonb — see the shape documented above that column in `0001` — and jsonb
-- has no enum to widen. A day ticked off with Basic Check already syncs.

alter table public.activities
    drop constraint if exists activities_verification_check;

alter table public.activities
    add constraint activities_verification_check
    check (verification in ('health', 'honor', 'basic'));
