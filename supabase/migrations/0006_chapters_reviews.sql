-- Chapters and weekly reviews.
--
-- The return loop's two stores. Both are practice data in the same sense the
-- identities are: what somebody named a stretch of their life, and the two
-- sentences they wrote about a week. Neither is recoverable from the days, so
-- a restore without them brings back the record and loses the meaning that was
-- put on it.
--
-- Same shape as `identities` in every respect that matters — user-scoped, RLS
-- on the owner, `updated_at` for last-writer-wins, `synced_at` written by the
-- server so the pull cursor is the server's clock rather than a phone's.

create table if not exists public.chapters (
    user_id      uuid        not null references auth.users (id) on delete cascade,
    id           text        not null,
    name         text        not null default '',
    -- Identity ids, never statements. The join is done on the phone, which is
    -- the same call `activities.identity_id` made.
    identity_ids text[]      not null default '{}',
    intention    text        not null default '',
    opened_at    timestamptz not null,
    -- Null while it is the one being lived in. Unioned on merge, earliest
    -- wins: closing is a fact about a moment and cannot un-happen.
    closed_at    timestamptz,
    updated_at   timestamptz not null,
    synced_at    timestamptz not null default now(),
    primary key (user_id, id)
);

create table if not exists public.reviews (
    user_id       uuid        not null references auth.users (id) on delete cascade,
    -- The week is the key. There cannot be two reviews of one week, which is a
    -- property of the thing rather than a constraint added to the table.
    week_start    date        not null,
    what_happened text        not null default '',
    what_next     text        not null default '',
    -- Set when the week was dealt with, answered or declined. A dismissed week
    -- is a row with no answers rather than an absent row, so "I skipped that
    -- one" and "that one has not been offered yet" stay different facts.
    completed_at  timestamptz,
    updated_at    timestamptz not null,
    synced_at     timestamptz not null default now(),
    primary key (user_id, week_start)
);

create index if not exists chapters_synced_at_idx on public.chapters (user_id, synced_at);
create index if not exists reviews_synced_at_idx  on public.reviews  (user_id, synced_at);

alter table public.chapters enable row level security;
alter table public.reviews  enable row level security;

do $$
begin
    if not exists (
        select 1 from pg_policies
        where schemaname = 'public' and tablename = 'chapters' and policyname = 'chapters_owner'
    ) then
        create policy chapters_owner on public.chapters
            for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
    end if;

    if not exists (
        select 1 from pg_policies
        where schemaname = 'public' and tablename = 'reviews' and policyname = 'reviews_owner'
    ) then
        create policy reviews_owner on public.reviews
            for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
    end if;
end
$$;

-- The server stamps arrival, so a phone with a wrong clock cannot make its rows
-- invisible to its own next pull. `touch_synced_at` is the one defined in 0001
-- and is deliberately not redefined here — see the note there for why it never
-- touches `updated_at`.
drop trigger if exists chapters_touch_synced_at on public.chapters;
create trigger chapters_touch_synced_at
    before insert or update on public.chapters
    for each row execute function public.touch_synced_at();

drop trigger if exists reviews_touch_synced_at on public.reviews;
create trigger reviews_touch_synced_at
    before insert or update on public.reviews
    for each row execute function public.touch_synced_at();

grant select, insert, update, delete on public.chapters to authenticated;
grant select, insert, update, delete on public.reviews  to authenticated;
