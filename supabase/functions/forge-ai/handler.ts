// The request, from arrival to answer. No Supabase client, no Apple, no OpenAI
// in here — each is a dependency, so every rule below can be tested alone.
//
// # The order is the security model
//
//   1. A POST with a JSON body naming one of the three tasks, and
//      for the coach a conversation ending in the person's turn.   else 405/400
//   2. A real Supabase user, from `auth.getUser()` on the caller's
//      own JWT. The app's user is an invisible anonymous one.      else 401
//   3. A verified StoreKit 2 Premium transaction in
//      `X-Forge-Transaction` — see `storekit.ts`.                  else 402
//   3a. Coach only: the safety screen (`safety.ts`). A message
//      suggesting a crisis gets the 988 reply, a declined topic
//      its one line — 200, with no model and no quota spent.
//   4. A provider configured on the server (`OPENAI_API_KEY`).     else 503
//   5. A quota slot, claimed atomically in Postgres, for both the
//      user and the purchase's `originalTransactionId` — the coach
//      in its own bucket (migration 0009).                         else 429/503
//   6. The model, then its answer mapped to the shapes the app
//      already understands; a coach's reply checked again.         else 422/502
//
// Nothing a client writes can say who it is or which purchase it holds: the
// user id comes from the verified JWT and the purchase from the verified JWS.
// Any `originalTransactionId` in the body or a header is never read.

import type { Entitlement } from "./storekit.ts";
import { EntitlementError } from "./storekit.ts";
import type { ModelProvider } from "./openai.ts";
import {
  type AIRequestBody,
  coachTurns,
  inputFor,
  instructionsFor,
  isTask,
  MAX_OUTPUT_TOKENS,
  modelFor,
  SCHEMAS,
  type Task,
} from "./prompts.ts";
import { checkAnswer, replyFor, screen } from "./safety.ts";

/// The header carrying `Transaction.jwsRepresentation`.
export const TRANSACTION_HEADER = "X-Forge-Transaction";

/// Model calls per verified purchase per UTC day. The spend boundary: one
/// purchase cannot power unlimited anonymous identities, because every one of
/// them draws from this same count. A weekly reading and a few plans is well
/// under it.
export const DAILY_TRANSACTION_LIMIT = 10;

/// Model calls per Supabase user per UTC day — the 0007 protection, kept.
export const DAILY_USER_LIMIT = 10;

/// Ask Forge messages per verified purchase per UTC day, and per user: a
/// bucket of its own (migration 0009), so a conversation can never spend the
/// allowance a weekly reading or a plan needs, nor the other way round.
export const DAILY_COACH_TRANSACTION_LIMIT = 30;
export const DAILY_COACH_USER_LIMIT = 30;

export type ClaimResult = "ok" | "user_limit" | "transaction_limit";

/// Which allowance a call draws on. The reading and the plan share one; the
/// coach has its own.
export type QuotaBucket = "standard" | "coach";

export function bucketFor(task: Task): QuotaBucket {
  return task === "coach" ? "coach" : "standard";
}

export interface HandlerDeps {
  /// The user behind the bearer token, or null. Production: `auth.getUser()`.
  authenticate(authorization: string): Promise<{ id: string } | null>;
  /// Resolves with the verified entitlement, or throws `EntitlementError`.
  verifyEntitlement(jws: string | null): Promise<Entitlement>;
  /// Atomically claims one call for both keys, in the task's bucket. Throws if
  /// it cannot run.
  claim(userId: string, originalTransactionId: string, bucket: QuotaBucket): Promise<ClaimResult>;
  /// Null when `OPENAI_API_KEY` is not set on the server.
  provider: ModelProvider | null;
  /// Diagnostic lines. Never given a request body, a brief, a JWS or a key.
  log?(message: string, detail?: Record<string, unknown>): void;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export function createHandler(deps: HandlerDeps): (req: Request) => Promise<Response> {
  const log = deps.log ?? (() => {});

  return async (req: Request): Promise<Response> => {
    if (req.method !== "POST") return json({ error: "method" }, 405);

    let body: AIRequestBody;
    try {
      const parsed = await req.json();
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error();
      body = parsed;
    } catch {
      return json({ error: "body" }, 400);
    }

    // Three jobs. `challenge` was one and was retired with the generator
    // (FORGE_CONTEXT §2j.3); the app answers it from its own catalogue.
    const task = body.task;
    if (!isTask(task)) return json({ error: "task" }, 400);

    // The coach answers the person's last turn, so it needs one.
    const turns = task === "coach" ? coachTurns(body) : null;
    if (task === "coach" && !turns) return json({ error: "messages" }, 400);

    // 2. Who. The platform's `verify_jwt` has already rejected a missing or
    // forged token; this establishes which user it names.
    const user = await deps.authenticate(req.headers.get("Authorization") ?? "");
    if (!user) return json({ error: "unauthenticated" }, 401);

    // 3. Entitled. Every failure — absent, malformed, forged, expired,
    // revoked, wrong app, wrong product, Sandbox in production — is 402.
    let entitlement: Entitlement;
    try {
      entitlement = await deps.verifyEntitlement(req.headers.get(TRANSACTION_HEADER));
    } catch (error) {
      const reason = error instanceof EntitlementError ? error.reason : "error";
      log("forge-ai entitlement", { task, reason });
      return json({ error: "not_entitled" }, 402);
    }

    // 3a. The coach's safety screen, on the person's last message only. Before
    // the provider and the quota: these answers are fixed, so they need no
    // model, cost nothing, and are given even when the model is unavailable.
    if (turns) {
      const rule = screen(turns[turns.length - 1].text);
      if (rule) {
        log("forge-ai screened", { task, rule });
        return json({ reply: replyFor(rule), proposal: null });
      }
    }

    // 4. Before the quota, so a missing secret does not spend anybody's slot.
    if (!deps.provider) {
      log("forge-ai provider unconfigured", { task });
      return json({ error: "unavailable" }, 503);
    }

    // 5. The spend boundary, claimed before the call so a request that dies
    // mid-flight costs a slot rather than an uncounted call. Fails closed.
    let claim: ClaimResult;
    try {
      claim = await deps.claim(user.id, entitlement.originalTransactionId, bucketFor(task));
    } catch {
      log("forge-ai quota unavailable", { task });
      return json({ error: "quota_unavailable" }, 503);
    }
    if (claim !== "ok") return json({ error: "rate_limited" }, 429);

    // 6. The model.
    try {
      const result = await deps.provider.generate({
        model: modelFor(task),
        instructions: instructionsFor(task),
        input: inputFor(task, body),
        schemaName: `forge_${task}`,
        schema: SCHEMAS[task],
        maxOutputTokens: MAX_OUTPUT_TOKENS[task],
      });
      switch (result.kind) {
        case "json":
          if (task === "coach") return coachAnswer(result.text, log);
          return new Response(result.text, {
            status: 200,
            headers: { "Content-Type": "application/json" },
          });
        // Every non-answer is a non-2xx, and the app treats every non-2xx the
        // same way: it uses its own arithmetic and says so.
        case "refused":
          return json({ error: "refused" }, 422);
        case "empty":
          return json({ error: "empty" }, 502);
        case "malformed":
          log("forge-ai malformed", { task });
          return json({ error: "malformed" }, 502);
        case "failed":
          log("forge-ai upstream", { task, status: result.status ?? null });
          return json({ error: "upstream" }, 502);
      }
    } catch {
      log("forge-ai upstream", { task });
      return json({ error: "upstream" }, 502);
    }
  };
}

/// A coach's answer, checked (`checkAnswer`): in Forge's voice, with a dose,
/// a crisis or a declined topic replaced by its fixed line, and the proposal
/// dropped wherever nothing may be coached. Only `reply` and `proposal` are
/// passed on.
function coachAnswer(
  text: string,
  log: (message: string, detail?: Record<string, unknown>) => void,
): Response {
  let parsed: { reply?: unknown; proposal?: unknown };
  try {
    parsed = JSON.parse(text);
  } catch {
    log("forge-ai malformed", { task: "coach" });
    return json({ error: "malformed" }, 502);
  }
  const checked = checkAnswer({ reply: parsed.reply as string, proposal: parsed.proposal ?? null });
  if (!checked) return json({ error: "empty" }, 502);
  return json(checked);
}
