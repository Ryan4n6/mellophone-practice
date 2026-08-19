#!/usr/bin/env python3
"""Minimal App Store Connect API helper for testflight.sh.

Mints an ES256 JWT from the Massfeller LLC ASC API key and makes a single
request. Recreated 2026-06-21 (#875) after it went missing on this build mac and
crashed testflight.sh's step [4/4] distribution (json.load on empty stdout).

Usage:
  python3 asc.py get   "/v1/builds?filter[app]=...&filter[version]=25"
  python3 asc.py post  "/v1/betaGroups/<gid>/relationships/builds" '<json>'
  python3 asc.py patch "/v1/builds/<bid>" '<json>'

Prints the response body (JSON) to stdout; exits non-zero with the body on
stderr for any HTTP >= 400 so the caller never parses an empty string.
"""
import sys
import os
import time
import http.client
import jwt

KEY_ID = "4X9H8LCJ7T"
ISSUER = "ffc0258c-d69f-4a90-a734-7e7b11dc4739"
KEY_PATH = os.path.expanduser(f"~/.appstoreconnect/AuthKey_{KEY_ID}.p8")
HOST = "api.appstoreconnect.apple.com"


def make_token() -> str:
    with open(KEY_PATH) as f:
        private_key = f.read()
    now = int(time.time())
    payload = {"iss": ISSUER, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})


def call(method, path, body=None):
    conn = http.client.HTTPSConnection(HOST, timeout=60)
    headers = {"Authorization": f"Bearer {make_token()}", "Content-Type": "application/json"}
    conn.request(method, path, body=body, headers=headers)
    resp = conn.getresponse()
    data = resp.read().decode()
    if resp.status >= 400:
        sys.stderr.write(f"ASC HTTP {resp.status} on {method} {path}: {data}\n")
        sys.exit(1)
    return data


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit("usage: asc.py <get|post|patch> <path> [json-body]")
    method = sys.argv[1].lower()
    path = sys.argv[2]
    body = sys.argv[3] if len(sys.argv) > 3 else None
    verb = {"get": "GET", "post": "POST", "patch": "PATCH", "delete": "DELETE"}.get(method)
    if not verb:
        sys.exit(f"unknown method: {method}")
    print(call(verb, path, body))


if __name__ == "__main__":
    main()
