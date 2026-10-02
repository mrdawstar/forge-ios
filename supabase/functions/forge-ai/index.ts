// Forge's half of the model seam: production wiring only.
//
// # Why this function exists at all
//
// A model API key shipped inside an iOS binary is an extracted API key — by
// anybody with a copy of the app and twenty minutes. So the app never holds a
// model key and never talks to a model. It posts here, and this function —
// which runs on Supabase's edge and holds `OPENAI_API_KEY` as a server secret —
// talks to OpenAI on the app's behalf. That also makes it the one place to
// check entitlement, cap spend and decide what is logged.
//
// # Who may call it
//
// Forge has no visible account (FORGE_CONTEXT §2n). The app signs in
// *anonymously* and invisibly (`AnonymousIdentity`), which gives it a real
// Supabase user and JWT with no name, email or password attached. The JWT is
// required:
//
//   * `verify_jwt` stays at its default of true — Supabase rejects a missing or
//     forged token before this file runs. Never deploy with --no-verify-jwt.
//   * `auth.getUser()` then resolves which user it is.
//
// An anonymous user alone gets nothing. Every call also needs a verified
// StoreKit 2 Premium transaction (`storekit.ts`), and draws on two daily
// quotas: per user, and per purchase (`originalTransactionId`, migration 0008).
// Ask Forge (`coach`) draws on a bucket of its own, the same two keys
// (migration 0009).
//
// Deploy:   supabase functions deploy forge-ai
// Secrets:  OPENAI_API_KEY (required), FORGE_ALLOW_SANDBOX ("true" only while
//           testing with StoreKit Sandbox). See supabase/README.md.

import { createClient } from "npm:@supabase/supabase-js@2";
import {
  createHandler,
  DAILY_COACH_TRANSACTION_LIMIT,
  DAILY_COACH_USER_LIMIT,
  DAILY_TRANSACTION_LIMIT,
  DAILY_USER_LIMIT,
} from "./handler.ts";
import type { ClaimResult } from "./handler.ts";
import { createOpenAIProvider } from "./openai.ts";
import { APPLE_PRODUCTION_TRUST, verifyEntitlementJWS } from "./storekit.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

/// Read once. Absent means every request is answered 503 after the
/// entitlement check, without spending a quota slot.
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";

/// Exactly the string "true", and nothing else, admits Sandbox transactions.
const ALLOW_SANDBOX = Deno.env.get("FORGE_ALLOW_SANDBOX") === "true";

// The service role is used for the quota RPC and nothing else: the usage
// tables are deliberately unreachable by any client (0007, 0008).
const service = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const handler = createHandler({
  async authenticate(authorization) {
    if (!authorization.startsWith("Bearer ")) return null;
    const asCaller = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data } = await asCaller.auth.getUser();
    return data?.user ? { id: data.user.id } : null;
  },

  verifyEntitlement(jws) {
    return verifyEntitlementJWS(jws, {
      trust: APPLE_PRODUCTION_TRUST,
      allowSandbox: ALLOW_SANDBOX,
    });
  },

  async claim(userId, originalTransactionId, bucket) {
    // The reading and the plan share 0008's allowance; the coach has 0009's.
    const coach = bucket === "coach";
    const fn = coach ? "claim_ai_coach_call" : "claim_ai_entitled_call";
    const { data, error } = await service.rpc(fn, {
      p_user: userId,
      p_user_limit: coach ? DAILY_COACH_USER_LIMIT : DAILY_USER_LIMIT,
      p_original_transaction_id: originalTransactionId,
      p_transaction_limit: coach ? DAILY_COACH_TRANSACTION_LIMIT : DAILY_TRANSACTION_LIMIT,
    });
    if (error) throw new Error(`${fn} failed`);
    if (data === "ok" || data === "user_limit" || data === "transaction_limit") {
      return data as ClaimResult;
    }
    throw new Error(`${fn} returned an unknown answer`);
  },

  provider: OPENAI_API_KEY ? createOpenAIProvider({ apiKey: OPENAI_API_KEY }) : null,

  log(message, detail) {
    console.error(message, detail ?? {});
  },
});

Deno.serve(handler);
