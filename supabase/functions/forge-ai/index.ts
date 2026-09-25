// Forge's half of the model seam.
//
// # Why this file exists at all
//
// An Anthropic API key shipped inside an iOS binary is an extracted API key.
// Not "at risk" — extracted, by anybody with a copy of the app and twenty
// minutes, because the binary is on their device and the key is a string in it.
// Obfuscation changes how long the twenty minutes takes and nothing else.
//
// So the app never holds a model key and never talks to a model. It posts here,
// signed in as itself, and this function — which runs on Supabase's edge, holds
// `ANTHROPIC_API_KEY` as a server secret, and is the only thing in the system
// that has ever seen it — talks to Anthropic on the app's behalf.
//
// Three things follow from that, and each of them would justify the hop alone:
//
//   1. The key cannot leak from a device, because it was never on one.
//   2. There is one place to check that the caller is entitled, so a free
//      account cannot spend Forge's money by calling an endpoint directly.
//   3. There is one place to rate limit, cap spend and log, and it is not on a
//      phone the user controls.
//
// Deploy:  supabase functions deploy forge-ai
// Secret:  supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//
// `verify_jwt` is left at its default of true, so Supabase rejects an
// unauthenticated request before this file runs.

import Anthropic from "npm:@anthropic-ai/sdk@0.68.0";
import { createClient } from "npm:@supabase/supabase-js@2";

// Claude Opus 5. The reading is the request that decides this: it is one short
// sentence about somebody's own life, said once a week, and it has to be true,
// in a specific register, and drawn from counts it must not misread. That is a
// small-output, high-care task, which is exactly where the strongest model is
// cheapest in the way that matters — a wrong answer here costs a user's trust
// in every number the app has ever shown them.
//
// At $5/$25 per MTok and briefs of roughly 500 in and 150 out, a call is well
// under a cent. A weekly reading, a handful of plans and a challenge or two per
// user per month is a rounding error against the subscription.
const MODEL = "claude-opus-5";

const anthropic = new Anthropic({
  apiKey: Deno.env.get("ANTHROPIC_API_KEY") ?? "",
});

// ---------------------------------------------------------------------------
// The voice
//
// Forge's register is the product. Nothing congratulates, nothing diagnoses,
// nothing exclaims, and no sentence tells somebody what they are like. The app
// has shipped for a year sounding like this and a model that sounds like a
// habit tracker would undo it in one screen.
//
// The reading's rules are stricter than the others' because the reading is the
// only task that makes a claim *about the user*. Everything it says is checked
// against the record on the device before it is shown — see
// `ReviewObservation.validate` — so a sentence that ignores these rules is not
// a bad answer, it is a discarded one, and the user silently gets the phone's
// own sentence instead.
// ---------------------------------------------------------------------------

const VOICE = `You write for Forge, an app for keeping a daily practice.

The register, which is not negotiable:
- Flat, adult, unsentimental. State what the record shows and stop.
- Never congratulate, praise, encourage, or commiserate.
- Never diagnose the person. "You kept four of five Mondays" is a fact.
  "You struggle on Fridays" is a claim about who they are, and you have no
  standing to make it.
- No exclamation marks. No emoji. No second-person imperatives about effort
  ("keep going", "push harder", "you've got this").
- Counts are spelled out as words below one hundred: "four", not "4".
- Short. A sentence that could be shorter is wrong.`;

const READING_RULES = `You are reading somebody's own week back to them.

HARD RULES — a sentence breaking any of these is thrown away unread:
1. Assert ONLY numbers that appear in the data you were given. Do not add,
   subtract, average, or round. If the data says four of five Mondays, you may
   say four of five Mondays and nothing else about Mondays.
2. Name ONLY activities and identity statements that appear in the data,
   spelled exactly as given.
3. At most two sentences.
4. Say one thing. Not a summary, not a list, not a conclusion — one
   observation the person could not easily have made themselves.
5. If the week does not clearly show anything, say what the week was, plainly.

Prefer, in this order: a split between two weekdays; a split between two named
activities; an identity with no evidence beside one with plenty; the plain
count.`;

const PLAN_RULES = `You are rearranging a week somebody already keeps.

HARD RULES:
1. Only edit activities present in the brief, by their exact id. You may not
   invent an activity, and there is no way to add one — an activity nobody
   chose has no business in a routine somebody built by hand.
2. Never place anything inside an hour the person said they were busy.
3. Leave a time somebody already chose alone unless it collides with something.
4. Spread repeats across the week rather than stacking them on consecutive days.
5. Nothing before waking, nothing after 22:30.
6. The summary is one sentence about the shape of the change.`;

const CHALLENGE_RULES = `Write one small, concrete thing to do today.

HARD RULES:
1. It must be doable today, by one person, without buying anything.
2. Concrete. "Read for twenty minutes before you open a browser" — not
   "prioritise learning".
3. The title is at most six words. The detail is one or two sentences.
4. No preamble, no framing, no explanation of why it is good for them.`;


// ---------------------------------------------------------------------------
// The shapes
//
// Structured outputs rather than free text plus a parser. The app's decoders
// are tolerant by design, but "tolerant" is the wrong property for the boundary
// where a model's output first becomes data — a plan whose changes half-parsed
// is worse than one that did not arrive.
// ---------------------------------------------------------------------------

const SCHEMAS: Record<string, unknown> = {
  reading: {
    type: "object",
    properties: { observation: { type: "string" } },
    required: ["observation"],
    additionalProperties: false,
  },
  challenge: {
    type: "object",
    properties: { title: { type: "string" }, detail: { type: "string" } },
    required: ["title", "detail"],
    additionalProperties: false,
  },
  plan: {
    type: "object",
    properties: {
      summary: { type: "string" },
      changes: {
        type: "array",
        items: {
          type: "object",
          properties: {
            kind: { type: "string", enum: ["time", "duration", "days"] },
            id: { type: "string" },
            minute: { type: "integer" },
            minutes: { type: "integer" },
            weekdays: { type: "array", items: { type: "integer" } },
          },
          required: ["kind", "id"],
          additionalProperties: false,
        },
      },
    },
    required: ["summary", "changes"],
    additionalProperties: false,
  },
};

const RULES: Record<string, string> = {
  reading: READING_RULES,
  challenge: CHALLENGE_RULES,
  plan: PLAN_RULES,
};

// All four are premium. The free app has the whole daily loop, the complete
// history and a rules-written weekly observation; what is sold is the model.
const PAID = new Set(["reading", "challenge", "plan"]);

// How many model calls one account may make in a UTC day.
//
// # This, not the premium row, is the spend boundary
//
// `premium_status` is writable by its owner — it has to be, because StoreKit on
// the device is the thing that knows — so the check below is a *product* gate,
// not a security one: it stops an honest free account from reaching a paid
// feature, and it stops nothing else. An account that writes itself a
// 'lifetime' row passes it.
//
// So the cap is what actually bounds the bill, and it is enforced in Postgres
// against a table no client can touch (migration 0007). Forty is far more than
// a real week of use — a weekly reading, a daily challenge and a handful of
// plans is under ten — and small enough that the worst an abuser achieves is a
// few cents a day.
//
// The correct long-term fix is App Store Server API verification of the
// transaction, server-side. It is not built; this is what holds until it is.
const DAILY_CALL_LIMIT = 40;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return json({ error: "method" }, 405);

  let payload: { task?: string; brief?: unknown; request?: string; difficulty?: string; focus?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "body" }, 400);
  }

  const task = payload.task ?? "";
  if (!RULES[task]) return json({ error: "task" }, 400);

  // Who is asking. `verify_jwt` has already established the token is real and
  // unexpired; this establishes which row it belongs to, without trusting any
  // id the app might have put in the body.
  const authorization = req.headers.get("Authorization") ?? "";
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authorization } } },
  );
  const { data: userData } = await supabase.auth.getUser();
  const user = userData?.user;
  if (!user) return json({ error: "unauthenticated" }, 401);

  if (PAID.has(task)) {
    // The product gate. Read through the caller's own token so row-level
    // security answers rather than a service key plus a WHERE clause we could
    // get wrong — and read, not trusted: see DAILY_CALL_LIMIT for why this
    // check is not the thing standing between us and an unbounded bill.
    const { data: entitlement } = await supabase
      .from("premium_status")
      .select("entitlement")
      .eq("user_id", user.id)
      .maybeSingle();
    const tier = entitlement?.entitlement ?? "free";
    if (tier !== "subscribed" && tier !== "lifetime") {
      return json({ error: "not_entitled" }, 403);
    }
  }

  // The spend boundary. Claimed before the model is called rather than after,
  // so a request that dies mid-flight costs a quota slot instead of an
  // uncounted call. The service role is used here and nowhere else in this
  // function, because `ai_usage` is deliberately unreachable by any client.
  const service = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  const { data: allowed, error: quotaError } = await service.rpc("claim_ai_call", {
    // From `auth.getUser()` above, never from the request body — the body is
    // written by a client and is the one thing here that cannot say who
    // somebody is.
    p_user: user.id,
    p_limit: DAILY_CALL_LIMIT,
  });
  if (quotaError) {
    // Fail closed. A quota check that cannot run is a spend cap that is not
    // enforced, and the app's fallback to its own arithmetic makes refusing
    // cost the user a nicer sentence rather than a working feature.
    console.error("forge-ai quota", quotaError);
    return json({ error: "quota_unavailable" }, 503);
  }
  if (allowed === false) return json({ error: "rate_limited" }, 429);

  const system = `${VOICE}\n\n${RULES[task]}`;
  const brief = JSON.stringify(payload.brief ?? {});
  const asked = (payload.request ?? "").slice(0, 500);

  const parts = [`Here is what Forge knows about this person:\n${brief}`];
  if (task === "challenge") {
    parts.push(
      `Aim: ${payload.focus ?? "discipline"}. Weight: ${payload.difficulty ?? "medium"}.`,
    );
  }
  if (asked) parts.push(`They asked: ${asked}`);

  try {
    const response = await anthropic.messages.create({
      model: MODEL,
      max_tokens: 2000,
      system,
      // Adaptive thinking. The reading in particular is a small amount of
      // careful arithmetic against a table of counts, which is precisely the
      // shape that goes wrong without it — and `effort: "low"` keeps a
      // once-a-week sentence from costing what an agent loop does.
      thinking: { type: "adaptive" },
      output_config: {
        effort: task === "reading" ? "medium" : "low",
        format: { type: "json_schema", schema: SCHEMAS[task] },
      },
      messages: [{ role: "user", content: parts.join("\n\n") }],
    });

    // A refusal is a real outcome, not an exception. The app treats any
    // non-answer identically — it falls back to the arithmetic — so the honest
    // thing is to say so plainly rather than to return half a shape.
    if (response.stop_reason === "refusal") {
      return json({ error: "refused" }, 422);
    }

    const text = response.content.find((b) => b.type === "text");
    if (!text || text.type !== "text") return json({ error: "empty" }, 502);
    return new Response(text.text, {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("forge-ai", task, error);
    return json({ error: "upstream" }, 502);
  }
});
