#!/usr/bin/env bash
# Verifies the deployed system end to end:
#   1. the site is served with its security headers,
#   2. the API reads and increments,
#   3. concurrent increments are not lost (atomic counter),
#   4. CORS admits the site's origin and nothing else.
set -euo pipefail

API="${1:?usage: smoke-test.sh <api-base-url> <site-url>}"
SITE="${2:?usage: smoke-test.sh <api-base-url> <site-url>}"
PARALLEL=20

fail() { echo "FAIL: $*" >&2; exit 1; }
count() { curl -fsS --retry 5 --retry-all-errors --retry-delay 5 "$API/visits" | jq -r .count; }

echo "1) site"
headers=$(curl -fsS -D - -o /dev/null "$SITE")
grep -qi '^content-security-policy:' <<< "$headers" || fail "site has no Content-Security-Policy header"

echo "2) read (retries cover the cold start after a deploy)"
before=$(count)
[[ "$before" =~ ^[0-9]+$ ]] || fail "unexpected counter value: $before"

echo "3) $PARALLEL concurrent increments"
for _ in $(seq "$PARALLEL"); do
  curl -fsS -o /dev/null -X POST "$API/visits" &
done
wait
after=$(count)
(( after - before == PARALLEL )) || fail "expected +$PARALLEL, got +$((after - before)) (lost updates?)"

echo "4) CORS"
allowed=$(curl -fsS -D - -o /dev/null -H "Origin: $SITE" "$API/visits" | tr -d '\r' | grep -i '^access-control-allow-origin:' || true)
[[ "$allowed" == *"$SITE"* ]] || fail "site origin not allowed by CORS"
foreign=$(curl -fsS -D - -o /dev/null -H "Origin: https://example.com" "$API/visits" | grep -i '^access-control-allow-origin:' || true)
[[ -z "$foreign" ]] || fail "foreign origin allowed by CORS: $foreign"

echo "OK: counter $before -> $after, CORS restricted to $SITE"
