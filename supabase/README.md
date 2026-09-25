# Forge — backend setup

Forge works with none of this done. An unconfigured build makes no requests, the
Account section is absent, and the app is exactly the local-only one it was.
Everything here is what turns the cloud half on.

## 0. Where to run the CLI

From `Forge/` — the directory holding `Forge.xcodeproj`, which is also the git
repository root. The CLI finds its project by looking for a `supabase` directory
under the working directory, and this one lives at `Forge/supabase`.

Running it from the folder *above* (the one with the spec and the design PDF)
makes `supabase link` create a second, empty `supabase/` there, and `db push`
then reports no migrations because it is looking in the wrong place. If that
happens, delete the stray directory rather than moving anything into it: these
migrations belong in the repository, and that folder is not in one.

```bash
cd path/to/Forge && supabase migration list
```

## 1. Apply the schema

```bash
supabase db push
```

> The app now speaks of **days** rather than mornings, but the schema does not.
> The table is still `mornings` and the one ritual row is still `'morning'`,
> because both are deployed with real data behind them and neither has ever been
> shown to a user. `SupabaseDataAPI.Table.days` and `RitualRow.dayRitualID` pin
> the old spellings deliberately — see the comments there before changing either.

Or paste `migrations/0001_forge_schema.sql` into the SQL editor. It is
idempotent — every statement is `if not exists`, `or replace`, or a
`drop … ; create …` pair — so re-running it is safe.

Verify RLS afterwards. Every one of the seven tables must show it enabled:

```sql
select tablename, rowsecurity from pg_tables where schemaname = 'public';
```

## 2. Providers

**Apple** — Authentication → Providers → Apple. Add the app's bundle id
(`com.dawid.forge`) to *Authorized Client IDs*. Native Sign in with Apple sends
an identity token straight to `/auth/v1/token?grant_type=id_token`, which
Supabase checks against Apple's public keys and that client-id list. **No client
secret is used on this path at all.**

The *Secret Key (for OAuth)* field is for the browser flow — a web client, or a
dashboard that refuses to save the provider while it is empty. It wants a signed
ES256 JWT, never the `.p8` itself. Generate one without the key leaving your
machine:

```bash
./apple-client-secret.py \
    --team-id ABCDE12345 \
    --key-id FGHIJ67890 \
    --services-id com.dawid.forge.signin \
    --key ~/Downloads/AuthKey_FGHIJ67890.p8
```

Apple caps these at six months. **It will expire and sign-in will start failing
with `invalid_client`** — put the date in a calendar.

In Xcode, the *Sign in with Apple* capability is already declared in
`Forge/Forge.entitlements` — it has to be enabled on the App ID in the developer
portal too.

**Google** — Authentication → Providers → Google. Create an OAuth client of type
*Web application* in Google Cloud, and give Google this authorized redirect URI:

```
https://<project>.supabase.co/auth/v1/callback
```

Then in Supabase, add `forge://auth-callback` to *Redirect URLs* under
Authentication → URL Configuration. Forge uses the PKCE web flow through
`ASWebAuthenticationSession`, so no Google SDK and no iOS OAuth client is
involved.

## 3. Point the app at the project

Fill in the two empty keys in `Forge/Info.plist`:

```xml
<key>ForgeSupabaseURL</key>
<string>https://<project>.supabase.co</string>
<key>ForgeSupabaseAnonKey</key>
<string>eyJ…</string>
```

The anon key belongs in the bundle. It names the project and grants nothing:
`anon` reaches no row of any table, and an authenticated request only ever
reaches rows whose owner is the uuid inside its own signed token. Never put the
service-role key here or anywhere in the app.

Leave either one empty and `SupabaseConfig.fromBundle()` returns nil, which
makes the whole backend inert.

## What syncs, and when

Signing in is free and creates the account. **Backup and sync require Premium** —
that is what Premium is now, and nothing about the local app is gated.

A sync runs when the app comes forward, when it goes to the background, when a
day is earned, eight seconds after the day's contents change, and
whenever a purchase lands. Failures retry with backoff, capped at half an hour,
and are recovered by the next foreground. Nothing on the day's path ever
waits for the network.

Migration is not a separate routine: the first sign-in is a sync with no
watermark, so every local record counts as unsent and goes up in one pass. Every
row upserts onto its own primary key, so running it again writes the same rows
to the same places and changes nothing.

## Conflict rules

Three, applied everywhere (`SyncMerge`, and every one of them is a unit test):

1. **Newer wins** — each record carries when the *user* changed it.
2. **An exact tie goes to the server** — every device sees the same server row,
   so deferring to it is the only tie-break that converges without the devices
   talking to each other.
3. **Sets are unioned, never replaced** — completions, blades seen, blades
   celebrated. Two phones offline in one day both keep their work.

The cost of rule 3, stated honestly: undoing an activity does not travel. If the
other device still has it, the next merge brings it back. That is a checkbox
somebody re-taps, against a day's work somebody never gets back.
