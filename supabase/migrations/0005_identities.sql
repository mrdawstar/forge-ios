-- Who somebody says they are becoming.
--
-- The eighth table, and the first one that is not about what happened. Every
-- other syncable table here records a fact — a day, a completion, a blade — and
-- this one records an *intention*: a sentence the user wrote about the person
-- they are working toward. Nothing on the server reads it, ranks it or reasons
-- about it. It is stored so that losing a phone is not losing the sentence.
--
-- Two columns are worth explaining because they look like they could be merged
-- and must not be:
--
--   retired_at   somebody stopped pursuing this. The identity stays, and so
--                does every day of history tagged to it — an identity pursued
--                for eight months explains eight months of somebody's record,
--                and dropping the row would leave all of it pointing at
--                nothing.
--   is_deleted   somebody threw it away. A tombstone rather than a DELETE, for
--                the reason `activities.is_deleted` is one: an identity that is
--                merely absent is indistinguishable from one the other device
--                has not sent yet, so a real delete gets handed straight back
--                by the next sync.
--
-- Retiring is the ordinary end and is what the app offers; deleting is the
-- deliberate one. See `Identity.retiredAt` on the device.

create table if not exists public.identities (
    user_id    uuid        not null references auth.users on delete cascade,
    -- 'identity.<uuid>', minted on the device and never derived from the
    -- statement — which the user rewrites, and which must not orphan the
    -- evidence behind it when they do.
    id         text        not null,
    statement  text        not null default '',
    symbol     text        not null default '',
    -- `PathAccent.rawValue`. Deliberately unconstrained: the palette is a closed
    -- set on the device with a review attached, and a check constraint here
    -- would mean adding a colour required a migration before the build that
    -- uses it could sync — the exact trap 0004 had to dig `activities` out of.
    -- An unrecognised value reads as Forge's own accent on the way in, which
    -- costs a tint and never a fact.
    accent     text        not null default '',
    created_at timestamptz not null default now(),
    retired_at timestamptz,
    is_deleted boolean     not null default false,
    updated_at timestamptz not null default now(),
    synced_at  timestamptz not null default now(),
    primary key (user_id, id)
);

create index if not exists identities_user_synced_idx
    on public.identities (user_id, synced_at);

-- The server's own arrival stamp, exactly as every other syncable table gets
-- it. See `touch_synced_at` in 0001 for why this never touches updated_at.
drop trigger if exists identities_touch_synced_at on public.identities;
create trigger identities_touch_synced_at
    before insert or update on public.identities
    for each row execute function public.touch_synced_at();

-- Same grants and the same policy shape as every other per-user table.
grant all on public.identities to authenticated, service_role;
revoke all on public.identities from anon;

alter table public.identities enable row level security;

drop policy if exists "identities are their owner's" on public.identities;
create policy "identities are their owner's"
    on public.identities for all to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Activities gain a tag
-- ---------------------------------------------------------------------------
--
-- The spine: which identity an activity is evidence for. Nullable, and null is
-- the ordinary case — every activity on every phone is untagged until somebody
-- says otherwise, and an untagged day is a complete and earnable day forever.
--
-- Deliberately **not** a foreign key to identities(user_id, id). Two reasons,
-- and the second is the one that matters. A device may push a tagged activity
-- in the same pass as the identity it names, and while the app sends identities
-- first, a constraint would turn any ordering surprise into a failed batch —
-- and a failed batch is permanent, because a schema error is not retryable. The
-- second: an identity that is deleted leaves its tag behind on purpose. The tag
-- then resolves to nothing, which the app already reads as untagged, and that is
-- a better outcome than the cascade quietly editing somebody's day.
alter table public.activities
    add column if not exists identity_id text;
