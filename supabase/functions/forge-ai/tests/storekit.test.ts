// StoreKit 2 JWS verification, offline, against a generated CA.
//
//   deno test --allow-env --no-lock supabase/functions/forge-ai/tests/

import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  APPLE_PRODUCTION_TRUST,
  APPLE_ROOT_CA_G3_SHA256,
  type EntitlementFailure,
  EntitlementError,
  FORGE_BUNDLE_ID,
  PREMIUM_PRODUCTS,
  verifyEntitlementJWS,
  type VerifyOptions,
} from "../storekit.ts";
import {
  annualClaims,
  type Chain,
  lifetimeClaims,
  makeChain,
  MONTHLY,
  signTransaction,
  testTrust,
  toBase64url,
  withForgedPayload,
} from "./support.ts";

const chain: Chain = await makeChain();
const trust = await testTrust(chain);
const production: VerifyOptions = { trust, allowSandbox: false };

async function rejects(
  jws: string | null | undefined,
  reason: EntitlementFailure,
  options: VerifyOptions = production,
) {
  const error = await assertRejects(() => verifyEntitlementJWS(jws, options), EntitlementError);
  assertEquals((error as EntitlementError).reason, reason);
}

// --- The trusted path --------------------------------------------------------

Deno.test("a current annual subscription from a trusted chain verifies", async () => {
  const claims = annualClaims();
  const entitlement = await verifyEntitlementJWS(await signTransaction(chain, claims), production);
  assertEquals(entitlement.productId, "com.dawid.forge.premium.annual");
  assertEquals(entitlement.kind, "renewable");
  assertEquals(entitlement.environment, "Production");
  assertEquals(entitlement.originalTransactionId, claims.originalTransactionId);
  assertEquals(entitlement.transactionId, claims.transactionId);
  assertEquals(entitlement.expiresAt?.getTime(), claims.expiresDate);
});

Deno.test("a current monthly subscription verifies on the same renewable path", async () => {
  const claims = annualClaims({ productId: MONTHLY, expiresDate: Date.now() + 20 * 86_400_000 });
  const entitlement = await verifyEntitlementJWS(await signTransaction(chain, claims), production);
  assertEquals(entitlement.productId, "com.dawid.forge.premium.monthly");
  assertEquals(entitlement.kind, "renewable");
  assertEquals(entitlement.expiresAt?.getTime(), claims.expiresDate);
  // Expired is expired, whatever the period.
  await rejects(
    await signTransaction(chain, annualClaims({ productId: MONTHLY, expiresDate: Date.now() - 1000 })),
    "expired",
  );
});

Deno.test("a lifetime purchase verifies and has no expiry", async () => {
  const entitlement = await verifyEntitlementJWS(await signTransaction(chain, lifetimeClaims()), production);
  assertEquals(entitlement.kind, "lifetime");
  assertEquals(entitlement.expiresAt, null);
});

Deno.test("an old lifetime purchase verifies while its chain was valid when signed", async () => {
  // Certificates that expired last month, on a transaction signed while they
  // were valid: Apple's own libraries check the chain at `signedDate`.
  const old = await makeChain({
    notBefore: new Date(Date.now() - 900 * 86_400_000),
    notAfter: new Date(Date.now() - 30 * 86_400_000),
  });
  const jws = await signTransaction(old, lifetimeClaims({ signedDate: Date.now() - 400 * 86_400_000 }));
  const entitlement = await verifyEntitlementJWS(jws, { trust: await testTrust(old), allowSandbox: false });
  assertEquals(entitlement.kind, "lifetime");
});

// --- The signature -----------------------------------------------------------

Deno.test("a payload that was edited after signing is refused", async () => {
  const jws = await signTransaction(chain, annualClaims({ productId: "com.other.app.thing" }));
  const forged = withForgedPayload(jws, annualClaims());
  await rejects(forged, "bad_signature");
});

Deno.test("a signature by a key that is not the leaf's is refused", async () => {
  const stranger = (await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair;
  await rejects(await signTransaction(chain, annualClaims(), stranger.privateKey), "bad_signature");
});

// --- The chain ---------------------------------------------------------------

Deno.test("the production trust policy refuses a chain that does not end in Apple Root CA G3", async () => {
  const jws = await signTransaction(chain, annualClaims());
  await rejects(jws, "untrusted_chain", { trust: APPLE_PRODUCTION_TRUST, allowSandbox: true });
});

Deno.test("production is pinned to Apple Root CA G3 and nothing else", () => {
  assertEquals(APPLE_PRODUCTION_TRUST.rootFingerprints, [APPLE_ROOT_CA_G3_SHA256]);
  assertEquals(APPLE_ROOT_CA_G3_SHA256, "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179");
  assertEquals(APPLE_PRODUCTION_TRUST.requireAppleMarkers, true);
});

Deno.test("a chain from a different, untrusted root is refused", async () => {
  const other = await makeChain();
  await rejects(await signTransaction(other, annualClaims()), "untrusted_chain");
});

Deno.test("a trusted root with somebody else's intermediate is refused", async () => {
  const other = await makeChain();
  const spliced = { ...other, x5c: [other.x5c[0], other.x5c[1], chain.x5c[2]] };
  await rejects(await signTransaction(spliced, annualClaims()), "untrusted_chain");
});

Deno.test("a chain without Apple's marker extensions is refused when markers are required", async () => {
  const bare = await makeChain({ withoutMarkers: true });
  await rejects(await signTransaction(bare, annualClaims()), "untrusted_chain", {
    trust: await testTrust(bare, true),
    allowSandbox: false,
  });
});

Deno.test("a chain that was not valid when the transaction was signed is refused", async () => {
  const future = await makeChain({
    notBefore: new Date(Date.now() + 86_400_000),
    notAfter: new Date(Date.now() + 400 * 86_400_000),
  });
  await rejects(await signTransaction(future, annualClaims()), "untrusted_chain", {
    trust: await testTrust(future),
    allowSandbox: false,
  });
});

Deno.test("a header with the wrong algorithm or no chain is malformed", async () => {
  const payload = toBase64url(new TextEncoder().encode(JSON.stringify(annualClaims())));
  const none = toBase64url(new TextEncoder().encode(JSON.stringify({ alg: "none", x5c: chain.x5c })));
  await rejects(`${none}.${payload}.AAAA`, "malformed");
  const noChain = toBase64url(new TextEncoder().encode(JSON.stringify({ alg: "ES256" })));
  await rejects(`${noChain}.${payload}.AAAA`, "malformed");
});

// --- Absent and malformed ----------------------------------------------------

Deno.test("no transaction at all is 'missing'", async () => {
  await rejects(null, "missing");
  await rejects(undefined, "missing");
  await rejects("", "missing");
  await rejects("   ", "missing");
});

Deno.test("garbage is 'malformed'", async () => {
  await rejects("not-a-jws", "malformed");
  await rejects("a.b", "malformed");
  await rejects("a.b.c.d", "malformed");
  await rejects("%%%.***.$$$", "malformed");
  await rejects("x".repeat(20_000), "malformed");
});

// --- The claims --------------------------------------------------------------

Deno.test("another app's bundle id is refused", async () => {
  await rejects(await signTransaction(chain, annualClaims({ bundleId: "com.dawid.forge.other" })), "wrong_bundle");
  await rejects(await signTransaction(chain, annualClaims({ bundleId: "com.dawid.forgeTests" })), "wrong_bundle");
  assertEquals(FORGE_BUNDLE_ID, "com.dawid.forge");
});

Deno.test("an expired subscription is refused", async () => {
  await rejects(await signTransaction(chain, annualClaims({ expiresDate: Date.now() - 1000 })), "expired");
  await rejects(await signTransaction(chain, annualClaims({ expiresDate: undefined })), "expired");
});

Deno.test("a revoked transaction is refused, lifetime included", async () => {
  await rejects(await signTransaction(chain, annualClaims({ revocationDate: Date.now() - 1000 })), "revoked");
  await rejects(
    await signTransaction(chain, lifetimeClaims({ revocationDate: Date.now() - 1000, revocationReason: 0 })),
    "revoked",
  );
});

Deno.test("a product that is not Forge Premium is refused", async () => {
  await rejects(
    await signTransaction(chain, annualClaims({ productId: "com.dawid.forge.tip.small" })),
    "unsupported_product",
  );
  // A real product id with the wrong transaction type.
  await rejects(
    await signTransaction(chain, lifetimeClaims({ type: "Consumable" })),
    "unsupported_product",
  );
  assertEquals(Object.keys(PREMIUM_PRODUCTS).sort(), [
    "com.dawid.forge.premium.annual",
    "com.dawid.forge.premium.lifetime",
    "com.dawid.forge.premium.monthly",
  ]);
});

Deno.test("a Sandbox transaction is refused unless the server allows Sandbox", async () => {
  const jws = await signTransaction(chain, annualClaims({ environment: "Sandbox" }));
  await rejects(jws, "wrong_environment");
  const allowed = await verifyEntitlementJWS(jws, { trust, allowSandbox: true });
  assertEquals(allowed.environment, "Sandbox");
});

Deno.test("an Xcode (local StoreKit testing) transaction is always refused", async () => {
  const jws = await signTransaction(chain, annualClaims({ environment: "Xcode" }));
  await rejects(jws, "wrong_environment", { trust, allowSandbox: true });
});

Deno.test("a transaction signed in the future is malformed", async () => {
  await rejects(
    await signTransaction(chain, annualClaims({ signedDate: Date.now() + 3_600_000 })),
    "malformed",
  );
});
