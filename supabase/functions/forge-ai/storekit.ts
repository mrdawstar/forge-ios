// Is this a real, current Forge Premium purchase? Answered offline, from the
// StoreKit 2 transaction the app sends, with nothing but Apple's certificates.
//
// # What arrives
//
// The app sends `Transaction.jwsRepresentation` for its current Premium
// entitlement in `X-Forge-Transaction`. That is a compact JWS (ES256) whose
// header carries the signing certificate chain in `x5c` — leaf, Apple's WWDR
// intermediate, and Apple Root CA G3 — and whose payload is the transaction.
//
// # What makes it trustworthy
//
// Not the client. The client can send any bytes it likes, so every claim is
// checked here, in this order, and any failure is the same answer (402):
//
//   1. The chain: three certificates; the last is self-signed and is exactly
//      the pinned root (SHA-256 of its DER); the intermediate is a CA signed by
//      the root; the leaf is signed by the intermediate and is not a CA; each
//      is within its validity period at the transaction's `signedDate`; and in
//      production the Apple markers are present (WWDR intermediate OID on the
//      intermediate, App Store receipt-signing OID on the leaf).
//   2. The signature: ES256 over `header.payload`, with the leaf's key.
//   3. The claims: Forge's exact bundle id; a Premium product id; the right
//      transaction type for it; not revoked; a subscription not yet expired;
//      the Production environment — or Sandbox only when the server says so.
//
// No App Store Server API call, no App Store Connect key, no network: the same
// check Apple's own libraries do offline.
//
// # Why validity is checked at `signedDate`
//
// StoreKit signs the transaction when it issues it, and a lifetime purchase
// can be years old. Apple's libraries check the chain at the signing date for
// exactly that reason. Freshness is covered separately: a subscription must be
// unexpired *now*, and a revocation is always final.

import * as x509 from "npm:@peculiar/x509@1.14.0";

// ---------------------------------------------------------------------------
// What Forge sells — read from the Xcode project, not assumed
// ---------------------------------------------------------------------------

/// `PRODUCT_BUNDLE_IDENTIFIER` of the Forge app target in
/// `Forge.xcodeproj/project.pbxproj`.
export const FORGE_BUNDLE_ID = "com.dawid.forge";

export type ProductKind = "renewable" | "lifetime";

/// `PremiumProduct` in `Forge/Models/Premium.swift`, `Forge.storekit` and the
/// table in `docs/APP_STORE.md` §7. `PremiumTests.productsAgree` (Swift) reads
/// this file and fails if the four disagree.
///
/// Forge Pro sells four: annual, the annual offer and monthly (auto-renewable,
/// one group) and lifetime. The offer — a lower annual price, shown once to
/// somebody who declines the paywall — is a renewable like the other two, and
/// the renewable path below is not specific to a price or a period, so its id
/// is the whole change here. Founders (1.0 / 1.0.1 installs) hold none of these
/// and stay unentitled: the AI is not part of what a founder keeps free, and
/// the 402 path is unchanged.
export const PREMIUM_PRODUCTS: Readonly<Record<string, ProductKind>> = {
  "com.dawid.forge.premium.annual": "renewable",
  "com.dawid.forge.premium.annual.offer": "renewable",
  "com.dawid.forge.premium.monthly": "renewable",
  "com.dawid.forge.premium.lifetime": "lifetime",
};

/// What Apple writes in `type` for each kind.
const TRANSACTION_TYPE: Record<ProductKind, string> = {
  renewable: "Auto-Renewable Subscription",
  lifetime: "Non-Consumable",
};

// ---------------------------------------------------------------------------
// Trust
// ---------------------------------------------------------------------------

/// SHA-256 of the DER of **Apple Root CA - G3**, the anchor for every StoreKit
/// 2 signature (https://www.apple.com/certificateauthority/). Check it with:
///
///     openssl x509 -inform der -in AppleRootCA-G3.cer -noout -fingerprint -sha256
export const APPLE_ROOT_CA_G3_SHA256 =
  "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";

/// Apple Worldwide Developer Relations intermediate marker.
export const OID_APPLE_WWDR_INTERMEDIATE = "1.2.840.113635.100.6.2.1";
/// App Store receipt-signing leaf marker.
export const OID_APPLE_RECEIPT_SIGNING = "1.2.840.113635.100.6.11.1";

export interface TrustPolicy {
  /// Lower-case hex SHA-256 fingerprints of acceptable root certificates.
  rootFingerprints: readonly string[];
  /// Require Apple's intermediate and leaf OIDs.
  requireAppleMarkers: boolean;
}

/// Production. One root, and it is Apple's.
export const APPLE_PRODUCTION_TRUST: TrustPolicy = Object.freeze({
  rootFingerprints: Object.freeze([APPLE_ROOT_CA_G3_SHA256]),
  requireAppleMarkers: true,
});

// ---------------------------------------------------------------------------
// The answer
// ---------------------------------------------------------------------------

export type Environment = "Production" | "Sandbox";

/// A verified entitlement. Every field comes from the signed payload.
export interface Entitlement {
  /// The quota key. Only ever read from here — never from a request.
  originalTransactionId: string;
  transactionId: string;
  productId: string;
  kind: ProductKind;
  environment: Environment;
  /// Nil for lifetime.
  expiresAt: Date | null;
}

export type EntitlementFailure =
  | "missing"
  | "malformed"
  | "untrusted_chain"
  | "bad_signature"
  | "wrong_bundle"
  | "wrong_environment"
  | "unsupported_product"
  | "expired"
  | "revoked";

export class EntitlementError extends Error {
  constructor(readonly reason: EntitlementFailure) {
    super(`entitlement: ${reason}`);
    this.name = "EntitlementError";
  }
}

export interface VerifyOptions {
  /// Production passes `APPLE_PRODUCTION_TRUST`. Tests pass their own CA.
  trust: TrustPolicy;
  /// `FORGE_ALLOW_SANDBOX=true` on the server, and nothing else.
  allowSandbox: boolean;
  now?: Date;
  bundleId?: string;
  products?: Readonly<Record<string, ProductKind>>;
}

/// The whole check. Resolves with the entitlement or throws `EntitlementError`.
export async function verifyEntitlementJWS(
  jws: string | null | undefined,
  options: VerifyOptions,
): Promise<Entitlement> {
  const now = options.now ?? new Date();
  const bundleId = options.bundleId ?? FORGE_BUNDLE_ID;
  const products = options.products ?? PREMIUM_PRODUCTS;

  if (typeof jws !== "string" || jws.trim() === "") throw new EntitlementError("missing");
  // A StoreKit transaction with its chain is a few kilobytes.
  if (jws.length > 16_384) throw new EntitlementError("malformed");

  const parts = jws.trim().split(".");
  if (parts.length !== 3 || parts.some((p) => !/^[A-Za-z0-9_-]+$/.test(p))) {
    throw new EntitlementError("malformed");
  }
  const [encodedHeader, encodedPayload, encodedSignature] = parts;

  const header = decodeJSON(encodedHeader);
  const payload = decodeJSON(encodedPayload);
  if (header.alg !== "ES256") throw new EntitlementError("malformed");
  const x5c = header.x5c;
  if (!Array.isArray(x5c) || x5c.length !== 3 || !x5c.every((c) => typeof c === "string")) {
    throw new EntitlementError("malformed");
  }

  const signedDate = millis(payload.signedDate);
  if (signedDate === null) throw new EntitlementError("malformed");
  // A signature from the future is not one StoreKit made.
  if (signedDate > now.getTime() + 5 * 60_000) throw new EntitlementError("malformed");

  // 1. The chain.
  const leaf = await verifyChain(x5c as string[], options.trust, new Date(signedDate));

  // 2. The signature, with the leaf's key.
  let key: CryptoKey;
  try {
    key = await leaf.publicKey.export({ name: "ECDSA", namedCurve: "P-256" }, ["verify"]);
  } catch {
    throw new EntitlementError("untrusted_chain");
  }
  const signature = base64urlToBytes(encodedSignature);
  if (signature.byteLength !== 64) throw new EntitlementError("bad_signature");
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    signature,
    new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`),
  );
  if (!valid) throw new EntitlementError("bad_signature");

  // 3. The claims — only now that they are known to be Apple's.
  if (payload.bundleId !== bundleId) throw new EntitlementError("wrong_bundle");

  const environment = payload.environment;
  if (environment === "Sandbox") {
    if (!options.allowSandbox) throw new EntitlementError("wrong_environment");
  } else if (environment !== "Production") {
    // "Xcode" (local StoreKit testing) and anything unknown.
    throw new EntitlementError("wrong_environment");
  }

  const productId = payload.productId;
  const kind = typeof productId === "string" ? products[productId] : undefined;
  if (!kind) throw new EntitlementError("unsupported_product");
  if (payload.type !== TRANSACTION_TYPE[kind]) throw new EntitlementError("unsupported_product");

  if (payload.revocationDate !== undefined && payload.revocationDate !== null) {
    throw new EntitlementError("revoked");
  }

  let expiresAt: Date | null = null;
  if (kind === "renewable") {
    const expires = millis(payload.expiresDate);
    if (expires === null || expires <= now.getTime()) throw new EntitlementError("expired");
    expiresAt = new Date(expires);
  }

  const originalTransactionId = identifier(payload.originalTransactionId);
  const transactionId = identifier(payload.transactionId);
  if (!originalTransactionId || !transactionId) throw new EntitlementError("malformed");

  return {
    originalTransactionId,
    transactionId,
    productId: productId as string,
    kind,
    environment: environment as Environment,
    expiresAt,
  };
}

/// Resolves with the leaf, or throws `untrusted_chain`.
async function verifyChain(
  x5c: string[],
  trust: TrustPolicy,
  at: Date,
): Promise<x509.X509Certificate> {
  let leaf: x509.X509Certificate;
  let intermediate: x509.X509Certificate;
  let root: x509.X509Certificate;
  try {
    [leaf, intermediate, root] = x5c.map((c) => {
      if (!/^[A-Za-z0-9+/]+={0,2}$/.test(c)) throw new Error("not base64");
      return new x509.X509Certificate(base64ToBytes(c));
    });
  } catch {
    throw new EntitlementError("malformed");
  }

  const untrusted = () => new EntitlementError("untrusted_chain");

  // The anchor, by exact bytes.
  const fingerprint = hex(new Uint8Array(await crypto.subtle.digest("SHA-256", root.rawData)));
  if (!trust.rootFingerprints.includes(fingerprint)) throw untrusted();

  // Each link: issuer name matches, and the signature verifies with the
  // issuer's key. The root must sign itself.
  const links: [x509.X509Certificate, x509.X509Certificate][] = [
    [root, root],
    [intermediate, root],
    [leaf, intermediate],
  ];
  for (const [subject, issuer] of links) {
    if (subject.issuer !== issuer.subject) throw untrusted();
    let ok = false;
    try {
      ok = await subject.verify({ publicKey: issuer.publicKey, signatureOnly: true });
    } catch {
      ok = false;
    }
    if (!ok) throw untrusted();
  }

  // Only CAs may issue, and the leaf may not.
  if (!isCA(root) || !isCA(intermediate) || isCA(leaf)) throw untrusted();

  for (const cert of [leaf, intermediate, root]) {
    if (at < cert.notBefore || at > cert.notAfter) throw untrusted();
  }

  if (trust.requireAppleMarkers) {
    if (!intermediate.getExtension(OID_APPLE_WWDR_INTERMEDIATE)) throw untrusted();
    if (!leaf.getExtension(OID_APPLE_RECEIPT_SIGNING)) throw untrusted();
  }

  return leaf;
}

function isCA(cert: x509.X509Certificate): boolean {
  return cert.getExtension(x509.BasicConstraintsExtension)?.ca === true;
}

// ---------------------------------------------------------------------------
// Encoding
// ---------------------------------------------------------------------------

// deno-lint-ignore no-explicit-any
function decodeJSON(segment: string): Record<string, any> {
  try {
    const value = JSON.parse(new TextDecoder().decode(base64urlToBytes(segment)));
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error();
    return value;
  } catch {
    throw new EntitlementError("malformed");
  }
}

/// Apple sends dates as milliseconds since 1970.
function millis(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : null;
}

/// Apple sends ids as strings of digits; accept a number defensively.
function identifier(value: unknown): string | null {
  if (typeof value === "string" && /^[0-9A-Za-z._-]{1,64}$/.test(value)) return value;
  if (typeof value === "number" && Number.isSafeInteger(value) && value > 0) return String(value);
  return null;
}

export function base64urlToBytes(value: string): ArrayBuffer {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
  return base64ToBytes(base64 + "=".repeat((4 - (base64.length % 4)) % 4));
}

/// An `ArrayBuffer` rather than a `Uint8Array`, so it is a `BufferSource`
/// under every TypeScript the edge runtime might check with.
function base64ToBytes(value: string): ArrayBuffer {
  try {
    const binary = atob(value);
    const buffer = new ArrayBuffer(binary.length);
    const bytes = new Uint8Array(buffer);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return buffer;
  } catch {
    throw new EntitlementError("malformed");
  }
}

function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}
