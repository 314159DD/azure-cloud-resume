#!/usr/bin/env bash
# DISRUPTIVE: floods the API until the kill switch stops the function app. Run it on purpose only,
# then restart the app:
#   az functionapp start -g <resource-group> -n <function-app>
#
# Sends GET requests (they do not change the counter) with limited parallelism, reports how the scale
# caps throttled them, then waits for the API to answer 403 ("This web app is stopped").
set -euo pipefail

API="${1:?usage: flood-test.sh <api-base-url> [requests] [parallel] [wait-minutes]}"
REQUESTS="${2:-3600}"
PARALLEL="${3:-25}"
WAIT_MINUTES="${4:-15}"

echo "Flood: $REQUESTS requests, $PARALLEL in parallel, started $(date -u +%FT%TZ)"
start=$(date +%s)
seq "$REQUESTS" | xargs -P "$PARALLEL" -I{} curl -s -o /dev/null -w "%{http_code}\n" "$API/visits" \
  | sort | uniq -c | sed 's/^/  HTTP /'
elapsed=$(( $(date +%s) - start ))
echo "Finished after ${elapsed}s (about $(( REQUESTS / (elapsed > 0 ? elapsed : 1) )) requests/s)"

echo "Waiting up to $WAIT_MINUTES minutes for the kill switch"
deadline=$(( $(date +%s) + WAIT_MINUTES * 60 ))
while (( $(date +%s) < deadline )); do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$API/visits")
  echo "  $(date -u +%T) API $code"
  if [[ "$code" == "403" ]]; then
    echo "Kill switch stopped the app."
    exit 0
  fi
  sleep 30
done
echo "The app was not stopped within $WAIT_MINUTES minutes." >&2
exit 1
