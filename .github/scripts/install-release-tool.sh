#!/usr/bin/env bash
#
# Install a pinned tool from a GitHub release, with retries and a checksum.
#
# Every packaged installer we tried (setup-crane, download-syft,
# cosign-installer) fetches a release asset and pipes it straight into tar or a
# file with no retry, so a single bad response takes the whole job down. That is
# not theoretical: GitHub's release CDN served us 503s and dropped connections
# for an evening, and jobs died with
#
#     gzip: stdin: unexpected end of file            (crane, truncated body)
#     ##[error]Process completed with exit code 56   (cosign, connection died)
#
# before reaching anything this repo builds. Two of the three also resolved
# "latest" at run time, which is a moving dependency in a repo whose whole point
# is pinning what it installs.
#
# So: one helper, used for all of them. Download to a file, verify it, and only
# then unpack -- a truncated body becomes a retry rather than a corrupt pipe.
#
#   install-release-tool.sh --name crane \
#     --url https://.../go-containerregistry_Linux_arm64.tar.gz \
#     --checksums https://.../checksums.txt \
#     --tar-member crane
#
#   install-release-tool.sh --name cosign --url https://.../cosign-linux-amd64 \
#     --checksums https://.../cosign_checksums.txt
#
# --checksums is optional but expected: hand-rolling the download is not a
# reason to stop verifying what came back. Omit it only where the release
# publishes no checksums file.
set -euo pipefail

NAME=""; URL=""; CHECKSUMS=""; TAR_MEMBER=""; DEST="${DEST:-/usr/local/bin}"
ATTEMPTS="${ATTEMPTS:-5}"

while [ $# -gt 0 ]; do
  case "$1" in
    --name)       NAME="$2"; shift 2 ;;
    --url)        URL="$2"; shift 2 ;;
    --checksums)  CHECKSUMS="$2"; shift 2 ;;
    --tar-member) TAR_MEMBER="$2"; shift 2 ;;
    --dest)       DEST="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$NAME" ] && [ -n "$URL" ] || {
  echo "usage: --name NAME --url URL [--checksums URL] [--tar-member NAME]" >&2
  exit 2
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
asset="$(basename "${URL%%\?*}")"

# One attempt: fetch, verify, unpack. All of it runs as a unit, because a
# half-downloaded file is exactly what we are defending against.
attempt_once() {
  rm -rf "${work:?}"/*
  curl -fsSL --retry 3 --retry-delay 2 -o "$work/$asset" "$URL" || return 1

  if [ -n "$CHECKSUMS" ]; then
    curl -fsSL --retry 3 --retry-delay 2 -o "$work/checksums.txt" "$CHECKSUMS" || return 1
    # The checksums file lists every asset in the release; take the line for
    # ours. A missing line fails rather than passes -- otherwise a renamed
    # asset would silently skip verification. The optional '*' is how
    # sha256sum marks binary mode, which some releases publish and some do not.
    grep " \*\{0,1\}${asset}\$" "$work/checksums.txt" > "$work/want.txt" || {
      echo "no checksum line for $asset" >&2; return 1
    }
    ( cd "$work" && sha256sum -c want.txt ) >/dev/null || return 1
  fi

  local extracted
  if [ -n "$TAR_MEMBER" ]; then
    tar xzf "$work/$asset" -C "$work" "$TAR_MEMBER" || return 1
    extracted="$TAR_MEMBER"
  else
    extracted="$asset"
  fi
  # Guarded: the member is usually already called what we want (crane, oras),
  # and mv onto itself is an error, not a no-op.
  [ "$extracted" = "$NAME" ] || mv "$work/$extracted" "$work/$NAME"
}

for attempt in $(seq 1 "$ATTEMPTS"); do
  if attempt_once; then
    break
  fi
  if [ "$attempt" = "$ATTEMPTS" ]; then
    echo "!! $NAME: giving up after $ATTEMPTS attempts" >&2
    exit 1
  fi
  echo "$NAME: attempt $attempt failed, retrying"
  sleep $((attempt * 5))
done

sudo install -m 0755 "$work/$NAME" "$DEST/$NAME"
echo "installed $NAME -> $DEST/$NAME"
