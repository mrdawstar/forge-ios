#!/usr/bin/env bash
#
# Check a live Forge backend.
#
# Everything here is a claim the app depends on and none of it can be checked by
# reading the schema: whether the tables actually exist, whether an
# unauthenticated request really does reach nothing, whether the two sign-in
# grants are wired up, and — given a real user token — whether a morning
# survives the round trip and stays invisible to everybody else.
#
#   ./verify.sh                      # what can be checked without an account
#   ACCESS_TOKEN=eyJ… ./verify.sh    # the whole thing, including RLS and sync
#
# Forge deliberately never logs or displays an access token, so getting one for
# this script means taking it off a signed-in device on purpose: put a breakpoint
# on `AuthService.adopt(_:provider:)` and read `session.accessToken`, or add a
# temporary print there and take it out again. Do not add a permanent way to
# extract it.

set -uo pipefail

URL="${SUPABASE_URL:-https://eslaeueyeuaejdnqfasv.supabase.co}"
KEY="${SUPABASE_KEY:-sb_publishable_Go9fLji8ndvLoeD2jfB1yg_ZTHecWEo}"
TOKEN="${ACCESS_TOKEN:-}"

TABLES=(profiles devices activities rituals mornings blades premium_status)

pass=0; fail=0; skip=0
ok()   { printf "  \033[32mPASS\033[0m  %s\n" "$1"; pass=$((pass+1)); }
no()   { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; [ $# -gt 1 ] && printf "        %s\n" "$2"; fail=$((fail+1)); }
meh()  { printf "  \033[33mSKIP\033[0m  %s\n" "$1"; skip=$((skip+1)); }
head_() { printf "\n\033[1m%s\033[0m\n" "$1"; }

req() { # method path [body] [token] -> "<status>|<body>"
    local method="$1" path="$2" body="${3:-}" tok="${4:-$KEY}" out
    if [ -n "$body" ]; then
        out=$(curl -s -w '\n%{http_code}' -X "$method" "$URL$path" \
            -H "apikey: $KEY" -H "Authorization: Bearer $tok" \
            -H "Content-Type: application/json" \
            -H "Prefer: resolution=merge-duplicates,return=representation" -d "$body")
    else
        out=$(curl -s -w '\n%{http_code}' -X "$method" "$URL$path" \
            -H "apikey: $KEY" -H "Authorization: Bearer $tok")
    fi
    printf '%s|%s' "$(printf '%s' "$out" | tail -1)" "$(printf '%s' "$out" | sed '$d')"
}

status() { printf '%s' "${1%%|*}"; }
payload() { printf '%s' "${1#*|}"; }

# ---------------------------------------------------------------------------
head_ "Reachability"
# ---------------------------------------------------------------------------

r=$(req GET "/auth/v1/settings")
if [ "$(status "$r")" = "200" ]; then
    ok "project reachable and the API key is accepted"
else
    no "project unreachable" "HTTP $(status "$r") — $(payload "$r" | head -c 200)"
    echo; echo "Nothing else can be checked. Stopping."; exit 1
fi

# ---------------------------------------------------------------------------
head_ "Schema"
# ---------------------------------------------------------------------------

missing=0
for t in "${TABLES[@]}"; do
    r=$(req GET "/rest/v1/$t?select=*&limit=1")
    case "$(status "$r")" in
        200|401|403) ok "table $t exists" ;;
        404) no "table $t is missing" "apply migrations/0001_forge_schema.sql"; missing=1 ;;
        *)   no "table $t returned $(status "$r")" "$(payload "$r" | head -c 160)"; missing=1 ;;
    esac
done

# Account deletion (0003). Required of any app that lets somebody make an
# account, and it is the only `security definer` function the app calls, so both
# halves are checked: that it is there at all, and that the grant keeps it away
# from anybody without a token.
#
# Deliberately called with the project key and never with ACCESS_TOKEN. This
# function does exactly what it says, and running it as a real user would delete
# that user's account. There is no safe way to test the authenticated path from
# here, and there should not be.
r=$(req POST "/rest/v1/rpc/delete_account" '{}')
case "$(status "$r")" in
    404)     no "delete_account is missing" "apply migrations/0003_account_deletion.sql"; missing=1 ;;
    401|403) ok "delete_account exists and refuses an unauthenticated caller" ;;
    200|204) no "DELETE_ACCOUNT RAN FOR AN UNAUTHENTICATED CALLER" \
                "revoke execute from public and anon — see 0003" ;;
    *)       no "delete_account answered $(status "$r")" "$(payload "$r" | head -c 160)" ;;
esac

# ---------------------------------------------------------------------------
head_ "Row Level Security — the unauthenticated case"
# ---------------------------------------------------------------------------
#
# The important distinction: an empty list means RLS filtered every row, which
# is correct. Rows coming back means anyone holding a key that ships inside the
# app can read the table, which is the worst possible outcome.

if [ "$missing" = "1" ]; then
    meh "skipped — the schema is not applied yet"
else
    for t in "${TABLES[@]}"; do
        r=$(req GET "/rest/v1/$t?select=*&limit=1")
        b=$(payload "$r")
        if [ "$(status "$r")" = "200" ] && [ "$(printf '%s' "$b" | tr -d '[:space:]')" = "[]" ]; then
            ok "$t returns nothing to an anonymous caller"
        elif [ "$(status "$r")" = "401" ] || [ "$(status "$r")" = "403" ]; then
            ok "$t refuses an anonymous caller outright"
        else
            no "$t LEAKED DATA to an anonymous caller" "$(printf '%s' "$b" | head -c 200)"
        fi
    done

    # A write is the other half. RLS must reject it on the `with check` clause.
    r=$(req POST "/rest/v1/mornings" \
        '{"user_id":"00000000-0000-0000-0000-000000000000","day":"2000-01-01","completions":[],"planned_ids":[],"updated_at":"2000-01-01T00:00:00.000+00:00"}')
    case "$(status "$r")" in
        401|403) ok "an anonymous write is rejected" ;;
        *) no "an anonymous write returned $(status "$r")" "$(payload "$r" | head -c 200)" ;;
    esac
fi

# ---------------------------------------------------------------------------
head_ "Authentication"
# ---------------------------------------------------------------------------

settings=$(payload "$(req GET "/auth/v1/settings")")
enabled() { printf '%s' "$settings" | python3 -c "import json,sys;print(json.load(sys.stdin)['external'].get('$1', False))"; }

[ "$(enabled apple)"  = "True" ] && ok "Sign in with Apple is enabled"  || no "Sign in with Apple is DISABLED" "Dashboard → Authentication → Sign In / Providers → Apple"
[ "$(enabled google)" = "True" ] && ok "Google is enabled"              || no "Google is DISABLED" "Dashboard → Authentication → Sign In / Providers → Google"

# Forge has no email/password path. Leaving it on means anyone can create
# accounts on this project through an endpoint the app never calls.
[ "$(enabled email)" = "False" ] && ok "email/password is off, as Forge intends" \
    || no "email/password signup is ENABLED" "Forge never calls it; turn it off so nothing else can"

# Forge's anonymous mode is entirely local and uses no Supabase session, so this
# should stay off. On, it would let anyone mint real user rows.
[ "$(enabled anonymous_users)" = "False" ] && ok "Supabase anonymous sign-in is off, as Forge intends" \
    || no "anonymous sign-in is ENABLED" "Forge's anonymous mode is local-only and needs no session"

# The two grants the app actually posts to. A wrong field name or endpoint shows
# up here as a different error than the one a bogus credential produces.
r=$(req POST "/auth/v1/token?grant_type=id_token" '{"provider":"apple","id_token":"bogus","nonce":"n"}')
case "$(payload "$r")" in
    *"ID token"*|*"id_token"*) ok "the Apple grant endpoint accepts Forge's request shape" ;;
    *provider*not*enabled*)    no "Apple provider not enabled" "$(payload "$r" | head -c 160)" ;;
    *) no "the Apple grant answered unexpectedly" "$(payload "$r" | head -c 200)" ;;
esac

r=$(req POST "/auth/v1/token?grant_type=pkce" '{"auth_code":"bogus","code_verifier":"bogus"}')
case "$(payload "$r")" in
    *flow_state*) ok "the PKCE exchange accepts Forge's request shape" ;;
    *) no "the PKCE exchange answered unexpectedly" "$(payload "$r" | head -c 200)" ;;
esac

# The redirect the app hands ASWebAuthenticationSession. If this is not in the
# allow-list Supabase silently sends the browser to the site URL instead, and
# the callback never reaches the app — a sign-in that hangs with no error.
challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM
authorize() {
    curl -s -o /dev/null -w '%{redirect_url}' \
        "$URL/auth/v1/authorize?provider=google&redirect_to=$1&code_challenge=$challenge&code_challenge_method=s256" \
        -H "apikey: $KEY"
}

r=$(authorize "forge%3A%2F%2Fauth-callback")
case "$r" in
    *accounts.google.com*) ok "Google authorize redirects to Google" ;;
    "") meh "Google authorize did not redirect (provider disabled)" ;;
    *) no "Google authorize redirected somewhere unexpected" "$r" ;;
esac

# The allow-list, tested by difference — the only way to tell "forge:// is
# permitted" from "everything is permitted", and those are very different
# projects to be running.
#
# An unrestricted list is an open redirect: a link to this project's authorize
# endpoint with `redirect_to` pointing anywhere will hand that destination the
# authorization code, wearing your domain on the way. Forge's own sign-in is not
# exposed to it — ASWebAuthenticationSession only ever accepts a callback on the
# scheme it was opened with — but a phishing page and any future web client are.
#
# Asked where the rule is actually enforced, which is not where it looks like it
# should be. `redirect_to` rides along in the URL handed to the provider as an
# opaque parameter the provider ignores, and GoTrue does not rewrite it there —
# so reading that URL reports "the allow-list permits any URL" on a project
# whose allow-list is exactly right. Enforcement happens when the provider comes
# back. So this drives a real flow state to the callback and reads where the
# browser is finally sent, which is the only answer that means anything.
lands_on() { # url-encoded redirect_to -> where the browser actually ends up
    local state
    state=$(curl -s -o /dev/null -D - \
        "$URL/auth/v1/authorize?provider=google&redirect_to=$1&code_challenge=$challenge&code_challenge_method=s256" \
        -H "apikey: $KEY" \
        | grep -i '^location' | sed -n 's/.*[?&]state=\([a-f0-9-]*\).*/\1/p' | tr -d '\r')
    [ -z "$state" ] && return 1
    curl -s -o /dev/null -D - \
        "$URL/auth/v1/callback?error=access_denied&error_description=probe&state=$state" \
        -H "apikey: $KEY" \
        | grep -i '^location:' | sed 's/location: //I' | tr -d '\r' | cut -d'?' -f1
}

if [ -n "$r" ]; then
    ours=$(lands_on "forge%3A%2F%2Fauth-callback")
    theirs=$(lands_on "https%3A%2F%2Fevil.example.com%2Fx")
    # A refused redirect falls back to the site URL, whatever that is set to, so
    # the test is that the foreign host does not appear — not that the fallback
    # equals any particular value.
    if [ "$ours" != "forge://auth-callback" ]; then
        no "forge://auth-callback is NOT allow-listed" \
           "sign-in would hang with no error — add it under Authentication → URL Configuration"
    elif printf '%s' "$theirs" | grep -q 'evil.example.com'; then
        no "THE REDIRECT ALLOW-LIST PERMITS ANY URL" \
           "Dashboard → Authentication → URL Configuration → Redirect URLs: set it to exactly forge://auth-callback"
    else
        ok "the redirect allow-list permits forge:// and refuses anything else"
    fi
fi

# ---------------------------------------------------------------------------
head_ "Sync round trip"
# ---------------------------------------------------------------------------

if [ -z "$TOKEN" ]; then
    meh "skipped — set ACCESS_TOKEN to a signed-in user's JWT"
elif [ "$missing" = "1" ]; then
    meh "skipped — the schema is not applied yet"
else
    uid=$(printf '%s' "$TOKEN" | cut -d. -f2 | tr '_-' '/+' \
        | { read -r p; printf '%s' "$p$(printf '=%.0s' $(seq $(( (4 - ${#p} % 4) % 4 ))))"; } \
        | base64 -d 2>/dev/null | python3 -c "import json,sys;print(json.load(sys.stdin)['sub'])" 2>/dev/null)

    if [ -z "$uid" ]; then
        no "could not read the user id out of ACCESS_TOKEN"
    else
        ok "token belongs to user $uid"
        day="2000-01-0$(( (RANDOM % 9) + 1 ))"

        # Upsert twice. The second must not duplicate — that property is the
        # whole of "migration happens once".
        body="{\"user_id\":\"$uid\",\"day\":\"$day\",\"completions\":[{\"ritual_id\":\"water\",\"method\":\"honor\",\"at\":\"2000-01-01T06:00:00.000+00:00\"}],\"planned_ids\":[\"water\"],\"extracted_at\":\"2000-01-01T06:05:00.000+00:00\",\"updated_at\":\"2000-01-01T06:05:00.000+00:00\"}"
        r=$(req POST "/rest/v1/mornings?on_conflict=user_id,day" "$body" "$TOKEN")
        if [ "$(status "$r")" = "201" ] || [ "$(status "$r")" = "200" ]; then
            ok "a morning uploads"
        else
            no "upload failed" "HTTP $(status "$r") — $(payload "$r" | head -c 200)"
        fi

        req POST "/rest/v1/mornings?on_conflict=user_id,day" "$body" "$TOKEN" >/dev/null
        r=$(req GET "/rest/v1/mornings?select=day,completions,synced_at&day=eq.$day" "" "$TOKEN")
        n=$(payload "$r" | python3 -c "import json,sys;print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")
        [ "$n" = "1" ] && ok "upserting twice leaves exactly one row" \
                       || no "upserting twice left $n rows" "$(payload "$r" | head -c 200)"

        printf '%s' "$(payload "$r")" | grep -q '"synced_at"' \
            && ok "the server stamps synced_at (the pull cursor works)" \
            || no "synced_at is missing" "incremental pulls will re-download everything"

        # The one that matters: a client cannot write a row it does not own.
        r=$(req POST "/rest/v1/mornings?on_conflict=user_id,day" \
            "{\"user_id\":\"00000000-0000-0000-0000-000000000000\",\"day\":\"2000-02-02\",\"completions\":[],\"planned_ids\":[],\"updated_at\":\"2000-01-01T00:00:00.000+00:00\"}" "$TOKEN")
        case "$(status "$r")" in
            401|403) ok "writing under somebody else's user_id is rejected" ;;
            *) no "A FORGED user_id WAS ACCEPTED ($(status "$r"))" "the with-check clause is not doing its job" ;;
        esac

        r=$(req GET "/rest/v1/profiles?select=id" "" "$TOKEN")
        ids=$(payload "$r" | python3 -c "import json,sys;print(','.join(r['id'] for r in json.load(sys.stdin)))" 2>/dev/null)
        if [ "$ids" = "$uid" ]; then
            ok "the signup trigger created exactly this user's profile"
        elif [ -z "$ids" ]; then
            no "no profile row" "the on_auth_user_created trigger did not fire"
        else
            no "profiles returned rows for other users" "$ids"
        fi

        curl -s -X DELETE "$URL/rest/v1/mornings?day=eq.$day" \
            -H "apikey: $KEY" -H "Authorization: Bearer $TOKEN" >/dev/null
        ok "test row cleaned up"
    fi
fi

printf "\n\033[1m%d passed, %d failed, %d skipped\033[0m\n" "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
