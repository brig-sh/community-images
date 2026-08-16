#!/usr/bin/env bash
#
# Run a command, retrying it with backoff.
#
# For the calls that depend on somebody else's service staying up. cosign is
# the reason this exists: it talks to Sigstore's transparency log, which
# answered 502 for a stretch and took three publish jobs down with it --
#
#     Post "https://rekor.sigstore.dev/api/v1/log/entries":
#     giving up after 2 attempt(s): status 502 Server Error
#     "The server encountered a temporary error... try again in 30 seconds."
#
# cosign does retry, twice, which is not enough for an outage measured in
# minutes. The backoff here is deliberately slower than the one in
# install-release-tool.sh: a CDN blip clears in seconds, a log service asking
# for 30 seconds should be given them.
#
#   retry.sh cosign sign --yes "$REF@$DIGEST"
#
# Redirections belong to the caller, not here: `retry.sh cosign verify ... >
# /dev/null` redirects the whole loop, which is what you want.
set -euo pipefail

ATTEMPTS="${ATTEMPTS:-5}"

[ $# -gt 0 ] || { echo "usage: retry.sh <command> [args...]" >&2; exit 2; }

for attempt in $(seq 1 "$ATTEMPTS"); do
  if "$@"; then
    exit 0
  fi
  if [ "$attempt" = "$ATTEMPTS" ]; then
    echo "!! giving up after $ATTEMPTS attempts: $*" >&2
    exit 1
  fi
  delay=$((attempt * 15))
  echo "attempt $attempt failed, retrying in ${delay}s: $1 ${2:-}" >&2
  sleep "$delay"
done
