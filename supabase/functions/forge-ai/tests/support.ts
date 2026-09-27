// Test-only: a generated CA chain shaped like Apple's, and a StoreKit-style
// JWS signed with it.
//
// Nothing here is Apple's and nothing pretends to be. The root is a fresh
// self-signed P-256 certificate made per test run; trust in it is injected via
// `testTrust(...)`. Production pins Apple Root CA G3 (`APPLE_PRODUCTION_TRUST`),
// and `storekit.test.ts` checks that a chain from here is refused by it.

import * as x509 from "npm:@peculiar/x509@1.14.0";
import {
  FORGE_BUNDLE_ID,
  OID_APPLE_RECEIPT_SIGNING,
  OID_APPLE_WWDR_INTERMEDIATE,
  type TrustPolicy,
} from "../storekit.ts";

const EC = { name: "ECDSA", namedCurve: "P-256", hash: "SHA-256" } as const;
const DAY = 86_400_000;
// DER NULL — what Apple puts in its marker extensions.
const DER_NULL = new Uint8Array([0x05, 0x00]);

export interface Chain {
  root: x509.X509Certificate;
  intermediate: x509.X509Certificate;
  leaf: x509.X509Certificate;
  leafKeys: CryptoKeyPair;
  /// x5c order: leaf, intermediate, root.
  x5c: string[];
}

export interface ChainOptions {
  /// Leave off the Apple OIDs.
  withoutMarkers?: boolean;
  /// Validity window of every certificate, relative to now.
  notBefore?: Date;
  notAfter?: Date;
}

async function keys(): Promise<CryptoKeyPair> {
  return await crypto.subtle.generateKey(EC, true, ["sign", "verify"]) as CryptoKeyPair;
}

let serial = 1;
const nextSerial = () => (serial++).toString(16).padStart(2, "0");

export async function makeChain(options: ChainOptions = {}): Promise<Chain> {
  const notBefore = options.notBefore ?? new Date(Date.now() - 30 * DAY);
  const notAfter = options.notAfter ?? new Date(Date.now() + 365 * DAY);

  const rootKeys = await keys();
  const root = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: nextSerial(),
    name: "CN=Forge Test Root CA, O=Forge Tests",
    notBefore,
    notAfter,
    signingAlgorithm: EC,
    keys: rootKeys,
    extensions: [
      new x509.BasicConstraintsExtension(true, undefined, true),
      new x509.KeyUsagesExtension(x509.KeyUsageFlags.keyCertSign | x509.KeyUsageFlags.cRLSign, true),
    ],
  });

  const intermediateKeys = await keys();
  const intermediate = await x509.X509CertificateGenerator.create({
    serialNumber: nextSerial(),
    subject: "CN=Forge Test Intermediate, O=Forge Tests",
    issuer: root.subject,
    notBefore,
    notAfter,
    signingAlgorithm: EC,
    publicKey: intermediateKeys.publicKey,
    signingKey: rootKeys.privateKey,
    extensions: [
      new x509.BasicConstraintsExtension(true, 0, true),
      ...(options.withoutMarkers ? [] : [new x509.Extension(OID_APPLE_WWDR_INTERMEDIATE, false, DER_NULL)]),
    ],
  });

  const leafKeys = await keys();
  const leaf = await x509.X509CertificateGenerator.create({
    serialNumber: nextSerial(),
    subject: "CN=Forge Test StoreKit Signing, O=Forge Tests",
    issuer: intermediate.subject,
    notBefore,
    notAfter,
    signingAlgorithm: EC,
    publicKey: leafKeys.publicKey,
    signingKey: intermediateKeys.privateKey,
    extensions: [
      new x509.BasicConstraintsExtension(false, undefined, true),
      ...(options.withoutMarkers ? [] : [new x509.Extension(OID_APPLE_RECEIPT_SIGNING, false, DER_NULL)]),
    ],
  });

  return {
    root,
    intermediate,
    leaf,
    leafKeys,
    x5c: [leaf, intermediate, root].map((c) => toBase64(new Uint8Array(c.rawData))),
  };
}

/// Trust exactly this chain's root, with Apple's marker rule on.
export async function testTrust(chain: Chain, requireAppleMarkers = true): Promise<TrustPolicy> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", chain.root.rawData));
  return {
    rootFingerprints: [Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("")],
    requireAppleMarkers,
  };
}

// ---------------------------------------------------------------------------
// Transactions
// ---------------------------------------------------------------------------

export const ANNUAL = "com.dawid.forge.premium.annual";
export const LIFETIME = "com.dawid.forge.premium.lifetime";

// deno-lint-ignore no-explicit-any
export type Claims = Record<string, any>;

/// A current annual subscription in Production, as StoreKit would describe it.
export function annualClaims(overrides: Claims = {}): Claims {
  const now = Date.now();
  return {
    transactionId: "2000000123456789",
    originalTransactionId: "2000000100000001",
    bundleId: FORGE_BUNDLE_ID,
    productId: ANNUAL,
    type: "Auto-Renewable Subscription",
    purchaseDate: now - 10 * DAY,
    originalPurchaseDate: now - 400 * DAY,
    expiresDate: now + 355 * DAY,
    inAppOwnershipType: "PURCHASED",
    signedDate: now - 60_000,
    environment: "Production",
    ...overrides,
  };
}

export function lifetimeClaims(overrides: Claims = {}): Claims {
  const now = Date.now();
  return {
    transactionId: "2000000987654321",
    originalTransactionId: "2000000900000009",
    bundleId: FORGE_BUNDLE_ID,
    productId: LIFETIME,
    type: "Non-Consumable",
    purchaseDate: now - 800 * DAY,
    originalPurchaseDate: now - 800 * DAY,
    inAppOwnershipType: "PURCHASED",
    signedDate: now - 60_000,
    environment: "Production",
    ...overrides,
  };
}

/// Sign `claims` as a StoreKit transaction, with `chain` in `x5c`.
export async function signTransaction(
  chain: Chain,
  claims: Claims,
  signingKey: CryptoKey = chain.leafKeys.privateKey,
): Promise<string> {
  const header = toBase64url(new TextEncoder().encode(JSON.stringify({ alg: "ES256", x5c: chain.x5c })));
  const payload = toBase64url(new TextEncoder().encode(JSON.stringify(claims)));
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      signingKey,
      new TextEncoder().encode(`${header}.${payload}`),
    ),
  );
  return `${header}.${payload}.${toBase64url(signature)}`;
}

/// The same JWS with its payload swapped and the original signature kept.
export function withForgedPayload(jws: string, claims: Claims): string {
  const [header, , signature] = jws.split(".");
  return `${header}.${toBase64url(new TextEncoder().encode(JSON.stringify(claims)))}.${signature}`;
}

export function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}

export function toBase64url(bytes: Uint8Array): string {
  return toBase64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
