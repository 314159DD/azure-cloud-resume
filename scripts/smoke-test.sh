#!/usr/bin/env bash
# Verifies the deployed system end to end:
#   1. the site is served with its security headers,
#   2. the API reads and increments,
#   3. concurrent increments are not lost (atomic counter),
#   4. CORS admits the site's origin and nothing else.
# Increments go to the separate "smoke" counter, so the public number on the site stays untouched and
# real visitors during the run cannot make the test fail.
set -euo pipefail

API="${1:?usage: smoke-test.sh <api-base-url> <site-url>}"
SITE="${2:?usage: smoke-test.sh <api-base-url> <site-url>}"
COUNTER="$API/visits?id=smoke"
PARALLEL=20

fail() { echo "FAIL: $*" >&2; exit 1; }
# Retries cover the cold start of the function and propagation of new site content after a deploy.
fetch() { curl -fsS --retry 6 --retry-all-errors --retry-delay 5 "$@"; }
count() { fetch "$COUNTER" | jq -r .count; }

echo "1) site"
fetch -D - -o /dev/null "$SITE" | grep -qi '^content-security-policy:' || fail "site has no Content-Security-Policy header"

echo "2) read"
before=$(count)
[[ "$before" =~ ^[0-9]+$ ]] || fail "unexpected counter value: $before"

echo "3) $PARALLEL concurrent increments"
pids=()
for _ in $(seq "$PARALLEL"); do
  curl -fsS -o /dev/null -X POST "$COUNTER" &
  pids+=("$!")
done
for pid in "${pids[@]}"; do
  wait "$pid" || fail "an increment request failed"
done
after=$(count)
(( after - before == PARALLEL )) || fail "expected +$PARALLEL, got +$((after - before)) (lost updates?)"

echo "4) CORS"
allowed=$(fetch -D - -o /dev/null -H "Origin: $SITE" "$API/visits" | tr -d '\r' | grep -i '^access-control-allow-origin:' || true)
[[ "$allowed" == *"$SITE"* ]] || fail "site origin not allowed by CORS"
foreign=$(fetch -D - -o /dev/null -H "Origin: https://example.com" "$API/visits" | grep -i '^access-control-allow-origin:' || true)
[[ -z "$foreign" ]] || fail "foreign origin allowed by CORS: $foreign"

echo "OK: smoke counter $before -> $after, CORS restricted to $SITE"
