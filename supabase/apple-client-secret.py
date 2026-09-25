#!/usr/bin/env python3
"""
Generate the Apple client secret JWT that Supabase's Apple provider asks for.

Forge does not need this for its own sign-in. The app uses the native flow —
`grant_type=id_token`, handing Supabase the identity token Apple already signed
— which Supabase validates against Apple's public keys and the Authorized
Client IDs list. No client secret is involved. This exists for the OAuth
(browser) flow: a web client, or a dashboard that will not save the provider
with the field empty.

The key never leaves this machine. It is read from a path, signed with the
openssl already on the system, and neither the key nor the JWT is written
anywhere — the JWT goes to stdout and nothing else.

    ./apple-client-secret.py \
        --team-id ABCDE12345 \
        --key-id  FGHIJ67890 \
        --services-id com.dawid.forge.signin \
        --key ~/Downloads/AuthKey_FGHIJ67890.p8

No third-party Python packages: `cryptography` and `pyjwt` are not installed
here and asking somebody to pip-install a crypto library to paste one field
into a dashboard is a poor trade. openssl does the signing; the DER-to-JOSE
conversion below is the only part worth writing by hand.
"""

import argparse
import base64
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# Apple refuses anything dated more than six months out with `invalid_client`,
# and gives no hint that the lifetime is the problem.
MAX_LIFETIME = 15777000  # 182.6 days, the value Apple's own docs use.


def b64url(data: bytes) -> str:
    """base64 in the alphabet a JWT can carry, with the padding dropped."""
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def der_to_jose(der: bytes) -> bytes:
    """Convert openssl's DER ECDSA signature to the raw r||s a JWT needs.

    This is the step everything gets wrong. openssl emits
    `SEQUENCE { INTEGER r, INTEGER s }`, where each integer is
    variable-length and carries a leading zero byte whenever its top bit is
    set. JOSE wants the opposite: two fixed 32-byte big-endian values, back to
    back, with no structure at all.

    A JWT built from the DER bytes verifies nowhere and fails with the same
    `invalid_client` that a wrong Team ID produces, which is why it is worth
    doing properly rather than hoping.
    """
    if der[0] != 0x30:
        raise ValueError("not a DER sequence")

    # Length: short form, or long form with a 1-byte count. An ECDSA P-256
    # signature is ~70 bytes, so nothing longer ever occurs.
    index = 2 if der[1] < 0x80 else 3

    def read_int(i):
        if der[i] != 0x02:
            raise ValueError("expected a DER integer")
        length = der[i + 1]
        value = der[i + 2 : i + 2 + length]
        return value.lstrip(b"\x00").rjust(32, b"\x00"), i + 2 + length

    r, index = read_int(index)
    s, _ = read_int(index)
    return r + s


def sign(message: bytes, key_path: Path) -> bytes:
    result = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(key_path)],
        input=message,
        capture_output=True,
    )
    if result.returncode != 0:
        raise SystemExit(
            f"openssl could not sign with that key:\n{result.stderr.decode().strip()}"
        )
    return der_to_jose(result.stdout)


def self_check(message: bytes, key_path: Path) -> bool:
    """Sign and verify against the key's own public half, before printing.

    Cheap, and it turns "paste this and see what Apple says" into "this is a
    valid ES256 JWT for that key". It cannot prove the Team ID or the Services
    ID are right — only Apple can say that — but it rules out the whole class
    of failures where the key was the wrong file, the wrong format, or the DER
    conversion went wrong, all of which Apple reports as the same unhelpful
    `invalid_client`.
    """
    with tempfile.TemporaryDirectory() as tmp:
        pub_path = Path(tmp) / "pub.pem"
        sig_path = Path(tmp) / "sig.der"

        pub = subprocess.run(
            ["openssl", "pkey", "-in", str(key_path), "-pubout"], capture_output=True
        )
        if pub.returncode != 0:
            return False
        pub_path.write_bytes(pub.stdout)

        signed = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", str(key_path)],
            input=message, capture_output=True,
        )
        if signed.returncode != 0:
            return False
        sig_path.write_bytes(signed.stdout)

        checked = subprocess.run(
            ["openssl", "dgst", "-sha256", "-verify", str(pub_path),
             "-signature", str(sig_path)],
            input=message, capture_output=True,
        )
        return checked.returncode == 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate an Apple client secret JWT for Supabase."
    )
    parser.add_argument("--team-id", required=True,
                        help="Apple Developer → Membership details → Team ID (10 chars)")
    parser.add_argument("--key-id", required=True,
                        help="the Key ID of the Sign in with Apple key (10 chars)")
    parser.add_argument("--services-id", required=True,
                        help="the Services ID identifier, e.g. com.dawid.forge.signin")
    parser.add_argument("--key", required=True, type=Path,
                        help="path to the AuthKey_XXXXXXXXXX.p8 file")
    parser.add_argument("--lifetime", type=int, default=MAX_LIFETIME,
                        help="seconds until expiry (Apple's ceiling is 15777000)")
    args = parser.parse_args()

    if not args.key.exists():
        raise SystemExit(f"no such key file: {args.key}")
    if args.lifetime > MAX_LIFETIME:
        raise SystemExit(
            f"Apple rejects anything longer than {MAX_LIFETIME}s (six months)."
        )
    for name, value in (("team id", args.team_id), ("key id", args.key_id)):
        if len(value) != 10:
            print(f"warning: {name} is usually 10 characters, got {len(value)}",
                  file=sys.stderr)

    issued = int(time.time())
    expires = issued + args.lifetime

    header = {"alg": "ES256", "kid": args.key_id}
    claims = {
        "iss": args.team_id,
        "iat": issued,
        "exp": expires,
        "aud": "https://appleid.apple.com",
        # The Services ID, not the bundle ID: this secret is for the flow where
        # Supabase talks to Apple as a web client, and that client is the
        # Services ID.
        "sub": args.services_id,
    }

    signing_input = ".".join(
        b64url(json.dumps(part, separators=(",", ":")).encode()) for part in (header, claims)
    ).encode("ascii")

    if not self_check(signing_input, args.key):
        raise SystemExit(
            "that key did not produce a verifiable ES256 signature.\n"
            "Check it is the AuthKey_*.p8 downloaded for a *Sign in with Apple* key,\n"
            "unmodified, and not the App Store Connect API key of the same shape."
        )

    token = f"{signing_input.decode()}.{b64url(sign(signing_input, args.key))}"

    print(token)
    print(
        f"\nexpires {time.strftime('%Y-%m-%d', time.localtime(expires))} "
        f"— Apple's maximum is six months, so this must be regenerated before then.",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
