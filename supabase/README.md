# Forge — backend setup

Forge works with none of this done. A build with no Supabase project in
`Forge/Info.plist` makes no AI request of any kind, and the app is the
local-only one it has always been. **Since 1.1 (session S6,
`docs/FORGE_CONTEXT.md` §17.6) the project is in `Info.plist` and the switch is
on.**

**What the backend is for now:** the `forge-ai` Edge Function, which runs
Forge's three model jobs — the weekly **Reading**, **Plan** in your own words,
and **Ask Forge** (`coach`) — for Forge Pro users, through the OpenAI API. There is **no visible account** (see
`docs/FORGE_CONTEXT.md` §2n and §2q): the app signs in *anonymously and
invisibly* so every request carries a Supabase JWT, and proves Premium with the
signed StoreKit 2 transaction. The account and sync code further down is
dormant and needs no setup.

| Piece | Where |
|---|---|
| Edge Function | `functions/forge-ai/` — `index.ts` (wiring), `handler.ts` (request rules), `storekit.ts` (Apple JWS verification), `openai.ts` (provider), `prompts.ts` (models, rules, schemas), `safety.ts` (Ask Forge's screen and answer check) |
| Tests | `functions/forge-ai/tests/` — Deno; no network, no real keys; `fixtures/` are the wire contract the app's `AskForgeTests` also read. `tests/ai_coach_quota.test.sql` — 0009 against a throwaway Postgres |
| Quotas | migrations `0007_ai_usage.sql` (per user), `0008_ai_transaction_quota.sql` (per purchase) — 10 a day each, shared by Reading and Plan — and `0009_ai_coach_quota.sql`, Ask Forge's own bucket: 30 messages a day per purchase and per user |
| Server secrets | `OPENAI_API_KEY` (required), `FORGE_ALLOW_SANDBOX` (optional) |
| Models | Reading → `gpt-6-sol`; Plan and Ask Forge → `gpt-6-luna` (`COACH_MODEL = PLAN_MODEL`, fixed in `prompts.ts`) |

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

## 1. Deploying AI — the checklist

Do these in order. Nothing here puts a secret in the repository, and nothing
here changes the app. Steps 1.1–1.8 were done by hand before session S6; S6 did
step 1.9 (`RemoteForgeAI.isModelEnabled = true`) and added migration `0009` and
the `coach` task, which need 1.3 and 1.7 run once more.

### 1.1 Log in and link the project

```bash
supabase login
supabase link --project-ref eslaeueyeuaejdnqfasv   # the project verify.sh points at
```

`link` asks for the database password (Dashboard → Project Settings →
Database). It writes `supabase/.temp/`, which is gitignored.

### 1.2 Turn on anonymous sign-ins

Dashboard → **Authentication → Sign In / Providers** → enable **Allow
anonymous sign-ins**, then Save.

Without it, the app's `POST /auth/v1/signup` with an empty body is refused,
the app gets no JWT, and every AI request quietly falls back to the phone's
own arithmetic. Nothing else about Auth needs changing: leave email, Apple and
Google exactly as they are, and leave **Authentication → Rate Limits → anonymous
sign-ins** at its default (30 per hour per IP) — an anonymous user on its own
gets nothing from `forge-ai`, so the rate limit only has to stop the users table
filling up.

### 1.3 Apply the migrations

```bash
supabase db push
supabase migration list        # 0001 … 0009 applied on both sides
```

`0009` adds Ask Forge's own allowance (`ai_coach_usage`,
`ai_coach_usage_by_transaction`, `claim_ai_coach_call`): 30 messages a day per
purchase and per user, row-locked, failing closed, service role only. Push it
**before** deploying the function that calls it — until it exists, every Ask
Forge message fails closed with 503 (nothing is spent, the app shows its one
"can't reach the server" line).

`0008` adds the per-purchase quota (`ai_usage_by_transaction`,
`claim_ai_entitled_call`) and closes an old grant: 0007's functions were still
executable by client roles through `PUBLIC`. Check it took:

```sql
select has_function_privilege('anon', 'public.claim_ai_call(uuid,integer)', 'execute');                      -- false
select has_function_privilege('anon', 'public.claim_ai_entitled_call(uuid,integer,text,integer)', 'execute'); -- false
select has_function_privilege('anon', 'public.claim_ai_coach_call(uuid,integer,text,integer)', 'execute');    -- false
select tablename, rowsecurity from pg_tables where schemaname = 'public';                                    -- all true
```

### 1.4 Create the OpenAI API key

1. Go to **https://platform.openai.com** and sign in (a ChatGPT login works,
   but this is a different product).
2. **API billing is separate from ChatGPT Plus / Pro.** A ChatGPT subscription
   includes no API usage at all. Open **Settings → Billing**
   (https://platform.openai.com/settings/organization/billing), add a payment
   method and buy prepaid credits. Until there is a positive balance, every
   call fails (`429 insufficient_quota`), and `forge-ai` answers 502 — the app
   falls back and nobody sees an error.
3. Set a budget while you are there: **Settings → Limits** — a monthly usage
   limit and an email alert. The per-purchase cap bounds each user; this bounds
   the total.
4. If your OpenAI project restricts which models it may use (the project's
   **Limits** page), make sure `gpt-6-sol` and `gpt-6-luna` are both allowed
   (Ask Forge uses `gpt-6-luna`).
5. Create the key: **API keys** (https://platform.openai.com/api-keys) →
   *Create new secret key*, in the project above. Permissions *All* works; if
   you choose *Restricted*, it needs write access to the Responses API and
   nothing else. Copy it once; OpenAI will not show it again.

Never paste the key into Swift, `Info.plist`, an `.xcconfig`, a test, a commit,
an issue or a PR. It exists in exactly one place: the Supabase secret below.

### 1.5 Save it as a Supabase secret

Read it without echoing it and without it entering your shell history:

```bash
read -rs OPENAI_API_KEY && supabase secrets set OPENAI_API_KEY="$OPENAI_API_KEY"; unset OPENAI_API_KEY
supabase secrets list          # shows OPENAI_API_KEY with a digest, never the value
```

(Or Dashboard → **Edge Functions → Secrets** → add `OPENAI_API_KEY`.) To rotate
it later: create a new key, run the same command, revoke the old key in OpenAI.

### 1.6 Decide `FORGE_ALLOW_SANDBOX`

`forge-ai` accepts only **Production** StoreKit transactions unless this is
exactly `true`.

| When | Set | Command |
|---|---|---|
| Testing purchases with a **Sandbox** tester or a **TestFlight** build (TestFlight purchases are Sandbox) | `true` | `supabase secrets set FORGE_ALLOW_SANDBOX=true` |
| **Production**, once testing is done | absent (or `false`) | `supabase secrets unset FORGE_ALLOW_SANDBOX` |

Two things to know:

- **App Review buys in Sandbox too.** While a build that turns the model on is
  in review, a reviewer's Premium purchase is a Sandbox transaction. With
  Sandbox off, the reviewer gets the phone's own Reading and Plan (honestly
  labelled, never an error). If you want them to see the model, set it to
  `true` for the review window and unset it after release — accepting that,
  meanwhile, any Sandbox/TestFlight purchase can reach the model (each still
  capped at 10 readings and plans, and 30 Ask Forge messages, a day per
  purchase).
- **Xcode's local StoreKit testing never works here.** `Forge.storekit`
  transactions are signed by Xcode, not Apple, and are refused with or without
  this flag. Test AI with a Sandbox account on a device.

### 1.7 Deploy the function

```bash
supabase functions deploy forge-ai
```

**Never add `--no-verify-jwt`.** JWT verification is what stops anybody who
reads the app's binary from calling the function; it stays on (the default).

### 1.8 Smoke test — costs nothing

```bash
URL=https://eslaeueyeuaejdnqfasv.supabase.co
KEY=<the publishable key from verify.sh or Project Settings → API>

# No JWT → 401, rejected by the platform before the function runs.
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$URL/functions/v1/forge-ai" -d '{}'

# An anonymous user → a JWT. (Proves step 1.2.)
TOKEN=$(curl -s -X POST "$URL/auth/v1/signup" -H "apikey: $KEY" \
  -H 'Content-Type: application/json' -d '{}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')

# Anonymous, no purchase → 402. OpenAI is never called; no quota is spent.
curl -s -w '\n%{http_code}\n' -X POST "$URL/functions/v1/forge-ai" \
  -H "Authorization: Bearer $TOKEN" -H "apikey: $KEY" -H 'Content-Type: application/json' \
  -d '{"task":"reading","brief":{}}'
```

Ask Forge the same way — 402 without a purchase, and 400 before anything else
when the conversation does not end in the person's turn:

```bash
curl -s -w '\n%{http_code}\n' -X POST "$URL/functions/v1/forge-ai" \
  -H "Authorization: Bearer $TOKEN" -H "apikey: $KEY" -H 'Content-Type: application/json' \
  -d '{"task":"coach","brief":{},"messages":[{"role":"user","text":"Why is Discipline slipping?"}]}'   # 402
curl -s -w '\n%{http_code}\n' -X POST "$URL/functions/v1/forge-ai" \
  -H "Authorization: Bearer $TOKEN" -H "apikey: $KEY" -H 'Content-Type: application/json' \
  -d '{"task":"coach","brief":{},"messages":[]}'                                                       # 400
```

A 200 needs a real Premium transaction from a device (Sandbox with step 1.6 on).
If OpenAI rejects a model name, the app shows its fallback and
`supabase functions logs forge-ai` shows `forge-ai upstream` with the status
OpenAI returned (400 or 404) — never the body.
`supabase functions logs forge-ai` shows only the task and a reason — never a
brief, a JWS or a key.

### 1.9 Turning it on in the app — done in 1.1, session S6

*Done (`docs/FORGE_CONTEXT.md` §17.6), together with Ask Forge.* Kept as the
record of what the change had to touch, because it changes what the app
collects:

1. Put the project in `Forge/Info.plist` (`ForgeSupabaseURL`,
   `ForgeSupabaseAnonKey` — the publishable key only, never the service-role
   key), and update `BackendRegressionTests.theAppShipsWithNoAccount`, which
   exists to fail when that happens.
2. `RemoteForgeAI.isModelEnabled = true`, and update `NoNetworkTests`, which
   exists to fail when that happens.
3. `ForgeNetwork.allowedHosts` adds the configured project's host **by
   itself** once steps 1 and 2 are done (prepared in `FORGE_CONTEXT.md` §2r) —
   update the tests that assert it is TelemetryDeck alone.
4. Switch `docs/APP_STORE.md` §1 to its prepared "once AI is activated" labels,
   publish the prepared privacy-policy paragraph (§2), and use the prepared
   review note (§6). Consent, the entitlement proof and the Weekly Reading flow
   are already built — see §2r for the full activation list.

## 2. Running the function's tests

Deno only — no Supabase, no Apple, no OpenAI, no keys:

```bash
deno test --allow-env --allow-read --no-lock supabase/functions/forge-ai/tests/
deno check --no-lock supabase/functions/forge-ai/index.ts
```

`--allow-read` is for the wire fixtures. If a `package.json` sits in a parent
folder (the home folder, on the owner's Mac), Deno switches to a manual
`node_modules` and cannot resolve `npm:` imports: prefix both commands with
`DENO_NO_PACKAGE_JSON=1`.

Migration `0009`'s quota semantics, grants and RLS are tested in SQL against a
throwaway Postgres (never the project): create the roles `anon`,
`authenticated`, `service_role` and a stub `auth.users (id uuid primary key)`,
apply `0007`, `0008` and `0009`, then

```bash
psql -v ON_ERROR_STOP=1 -f supabase/tests/ai_coach_quota.test.sql   # "ai_coach_quota tests passed"
```

The StoreKit tests generate a throwaway CA chain each run and inject trust in
it; production is pinned to Apple Root CA G3 by fingerprint, and a test checks
that the generated chain is refused by the production policy. The OpenAI tests
mock `fetch`.

## 3. The schema

> The app speaks of **days** rather than mornings, but the schema does not.
> The table is still `mornings` and the one ritual row is still `'morning'`,
> because both are deployed with real data behind them and neither has ever been
> shown to a user. `SupabaseDataAPI.Table.days` and `RitualRow.dayRitualID` pin
> the old spellings deliberately — see the comments there before changing either.

`migrations/0001_forge_schema.sql` can also be pasted into the SQL editor. It is
idempotent — every statement is `if not exists`, `or replace`, or a
`drop … ; create …` pair — so re-running it is safe.

Verify RLS afterwards. Every table must show it enabled:

```sql
select tablename, rowsecurity from pg_tables where schemaname = 'public';
```

---

# Dormant: the visible account and sync

Everything below describes the account that was removed from the app in §2n.
The code is still in `Forge/Backend/` and still tested, but **nothing in the
app reaches it and none of it needs configuring** for AI. It is kept for the
day sync comes back. The anonymous identity above does not use any of it.

## Providers (dormant)

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

## Point the app at the project (see 1.9 first)

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

## What syncs, and when (dormant)

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

## Conflict rules (dormant)

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
