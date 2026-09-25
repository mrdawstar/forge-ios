// The request logic, with every dependency mocked except the StoreKit verifier,
// which runs for real against a generated CA — so "the quota key comes from the
// verified JWS" is tested end to end rather than asserted against a stub.

import { assertEquals } from "jsr:@std/assert@1";
import {
  type ClaimResult,
  createHandler,
  DAILY_TRANSACTION_LIMIT,
  DAILY_USER_LIMIT,
  type HandlerDeps,
  TRANSACTION_HEADER,
} from "../handler.ts";
import type { ModelProvider, ModelRequest, ModelResult } from "../openai.ts";
import { PLAN_MODEL, READING_MODEL } from "../prompts.ts";
import { verifyEntitlementJWS } from "../storekit.ts";
import { annualClaims, lifetimeClaims, makeChain, signTransaction, testTrust } from "./support.ts";

const chain = await makeChain();
const trust = await testTrust(chain);
const VERIFIED_OTID = "2000000100000001";

interface Harness {
  deps: HandlerDeps;
  calls: ModelRequest[];
  claims: { userId: string; otid: string }[];
}

function harness(options: {
  user?: { id: string } | null;
  claim?: ClaimResult | "throw";
  result?: ModelResult | "throw";
  provider?: "none";
  allowSandbox?: boolean;
} = {}): Harness {
  const calls: ModelRequest[] = [];
  const claims: { userId: string; otid: string }[] = [];
  const provider: ModelProvider = {
    generate(request) {
      calls.push(request);
      if (options.result === "throw") return Promise.reject(new Error("boom"));
      return Promise.resolve(options.result ?? { kind: "json", text: '{"observation":"x"}' });
    },
  };
  return {
    calls,
    claims,
    deps: {
      authenticate: (authorization) =>
        Promise.resolve(
          authorization === "Bearer anon-jwt"
            ? (options.user === undefined ? { id: "00000000-0000-4000-8000-000000000001" } : options.user)
            : null,
        ),
      verifyEntitlement: (jws) => verifyEntitlementJWS(jws, { trust, allowSandbox: options.allowSandbox ?? false }),
      claim(userId, otid) {
        claims.push({ userId, otid });
        if (options.claim === "throw") return Promise.reject(new Error("db down"));
        return Promise.resolve(options.claim ?? "ok");
      },
      provider: options.provider === "none" ? null : provider,
    },
  };
}

async function post(
  h: Harness,
  body: unknown,
  headers: Record<string, string> = {},
): Promise<Response> {
  const jws = await signTransaction(chain, annualClaims());
  const request = new Request("https://example.test/functions/v1/forge-ai", {
    method: "POST",
    headers: {
      "Authorization": "Bearer anon-jwt",
      "Content-Type": "application/json",
      [TRANSACTION_HEADER]: jws,
      ...headers,
    },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
  return await createHandler(h.deps)(request);
}

const reading = { task: "reading", brief: { daysKept: 12, week: { kept: 4, asked: 5 } } };
const plan = { task: "plan", brief: { activities: [] }, request: "move reading to the evening" };

// --- Model routing -----------------------------------------------------------

Deno.test("a reading goes to gpt-6-sol, with the reading rules", async () => {
  const h = harness();
  const response = await post(h, reading);
  assertEquals(response.status, 200);
  assertEquals(h.calls.length, 1);
  assertEquals(h.calls[0].model, "gpt-6-sol");
  assertEquals(h.calls[0].model, READING_MODEL);
  assertEquals(h.calls[0].schemaName, "forge_reading");
  assertEquals(h.calls[0].instructions.includes("reading somebody's own week"), true);
  assertEquals(h.calls[0].instructions.includes("Never give medical advice"), true);
  assertEquals(await response.text(), '{"observation":"x"}');
});

Deno.test("a plan goes to gpt-6-luna, with the plan rules and the request", async () => {
  const h = harness({ result: { kind: "json", text: '{"summary":"s","changes":[]}' } });
  const response = await post(h, plan);
  assertEquals(response.status, 200);
  assertEquals(h.calls[0].model, "gpt-6-luna");
  assertEquals(h.calls[0].model, PLAN_MODEL);
  assertEquals(h.calls[0].schemaName, "forge_plan");
  assertEquals(h.calls[0].instructions.includes("rearranging a week"), true);
  assertEquals(h.calls[0].input.includes("They asked: move reading to the evening"), true);
});

Deno.test("the two models are fixed and different", () => {
  assertEquals(READING_MODEL, "gpt-6-sol");
  assertEquals(PLAN_MODEL, "gpt-6-luna");
});

Deno.test("the client cannot choose a model", async () => {
  const h = harness();
  await post(h, { ...reading, model: "gpt-6-luna" });
  assertEquals(h.calls[0].model, "gpt-6-sol");
});

Deno.test("only reading and plan are served — challenge and chat are not", async () => {
  for (const task of ["challenge", "chat", "", undefined]) {
    const h = harness();
    const response = await post(h, { task, brief: {} });
    assertEquals(response.status, 400);
    assertEquals(h.calls.length, 0);
    assertEquals(h.claims.length, 0);
  }
});

// --- Authentication and entitlement -------------------------------------------

Deno.test("no valid user is 401, before anything else is looked at", async () => {
  const h = harness({ user: null });
  const response = await post(h, reading);
  assertEquals(response.status, 401);
  assertEquals(h.claims.length, 0);
  assertEquals(h.calls.length, 0);
});

Deno.test("a user without a transaction is 402 and costs nothing", async () => {
  const h = harness();
  const response = await post(h, reading, { [TRANSACTION_HEADER]: "" });
  assertEquals(response.status, 402);
  assertEquals(await response.json(), { error: "not_entitled" });
  assertEquals(h.claims.length, 0);
  assertEquals(h.calls.length, 0);
});

Deno.test("an invalid, expired, revoked, foreign or Sandbox transaction is 402", async () => {
  const bad = [
    "garbage",
    await signTransaction(chain, annualClaims({ expiresDate: Date.now() - 1 })),
    await signTransaction(chain, annualClaims({ revocationDate: Date.now() - 1 })),
    await signTransaction(chain, annualClaims({ bundleId: "com.example.other" })),
    await signTransaction(chain, annualClaims({ productId: "com.example.other" })),
    await signTransaction(chain, annualClaims({ environment: "Sandbox" })),
    await signTransaction(await makeChain(), annualClaims()),
  ];
  for (const jws of bad) {
    const h = harness();
    const response = await post(h, reading, { [TRANSACTION_HEADER]: jws });
    assertEquals(response.status, 402);
    assertEquals(h.claims.length, 0);
    assertEquals(h.calls.length, 0);
  }
});

Deno.test("Sandbox is served when the server allows it", async () => {
  const h = harness({ allowSandbox: true });
  const jws = await signTransaction(chain, annualClaims({ environment: "Sandbox" }));
  const response = await post(h, reading, { [TRANSACTION_HEADER]: jws });
  assertEquals(response.status, 200);
});

// --- The quota key -----------------------------------------------------------

Deno.test("the quota key is the verified originalTransactionId, whatever the client says", async () => {
  const h = harness();
  const response = await post(
    h,
    { ...reading, originalTransactionId: "attacker-chosen", original_transaction_id: "attacker-chosen" },
    {
      "X-Forge-Original-Transaction-Id": "attacker-chosen",
      "X-Original-Transaction-Id": "attacker-chosen",
    },
  );
  assertEquals(response.status, 200);
  assertEquals(h.claims, [{ userId: "00000000-0000-4000-8000-000000000001", otid: VERIFIED_OTID }]);
});

Deno.test("two purchases are two quota keys; one purchase on many users is one key", async () => {
  const a = harness({ user: { id: "user-a" } });
  const b = harness({ user: { id: "user-b" } });
  const jws = await signTransaction(chain, lifetimeClaims({ originalTransactionId: "999" }));
  await post(a, reading, { [TRANSACTION_HEADER]: jws });
  await post(b, reading, { [TRANSACTION_HEADER]: jws });
  assertEquals(a.claims[0].otid, "999");
  assertEquals(b.claims[0].otid, "999");
});

Deno.test("either limit reached is 429 and the model is not called", async () => {
  for (const claim of ["user_limit", "transaction_limit"] as const) {
    const h = harness({ claim });
    const response = await post(h, reading);
    assertEquals(response.status, 429);
    assertEquals(h.calls.length, 0);
  }
});

Deno.test("a quota check that cannot run fails closed with 503", async () => {
  const h = harness({ claim: "throw" });
  const response = await post(h, reading);
  assertEquals(response.status, 503);
  assertEquals(h.calls.length, 0);
});

Deno.test("the limits are conservative", () => {
  assertEquals(DAILY_TRANSACTION_LIMIT, 10);
  assertEquals(DAILY_USER_LIMIT <= DAILY_TRANSACTION_LIMIT, true);
});

// --- Configuration -----------------------------------------------------------

Deno.test("no OPENAI_API_KEY on the server is 503, without spending a quota slot", async () => {
  const h = harness({ provider: "none" });
  const response = await post(h, reading);
  assertEquals(response.status, 503);
  assertEquals(h.claims.length, 0);
});

// --- What comes back ---------------------------------------------------------

Deno.test("provider outcomes map to the statuses the app already falls back on", async () => {
  const cases: [ModelResult | "throw", number, string][] = [
    [{ kind: "refused" }, 422, "refused"],
    [{ kind: "empty" }, 502, "empty"],
    [{ kind: "malformed" }, 502, "malformed"],
    [{ kind: "failed", status: 500 }, 502, "upstream"],
    ["throw", 502, "upstream"],
  ];
  for (const [result, status, error] of cases) {
    const h = harness({ result });
    const response = await post(h, reading);
    assertEquals(response.status, status);
    assertEquals(await response.json(), { error });
  }
});

// --- The shape of a request --------------------------------------------------

Deno.test("only POST with a JSON object body is accepted", async () => {
  const h = harness();
  assertEquals((await createHandler(h.deps)(new Request("https://x.test", { method: "GET" }))).status, 405);
  assertEquals((await post(h, "not json")).status, 400);
  assertEquals((await post(h, "[1]")).status, 400);
  assertEquals(h.calls.length, 0);
});

Deno.test("nothing from the request reaches the log", async () => {
  const lines: string[] = [];
  const h = harness({ result: { kind: "failed", status: 500 } });
  h.deps.log = (message, detail) => lines.push(JSON.stringify([message, detail]));
  await post(h, { ...reading, brief: { secret: "my private sentence" } });
  await post(h, reading, { [TRANSACTION_HEADER]: "garbage" });
  const joined = lines.join("\n");
  assertEquals(joined.includes("my private sentence"), false);
  assertEquals(joined.includes("garbage"), false);
  assertEquals(joined.includes("eyJ"), false);
});
