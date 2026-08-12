# Codex guest image

Codex as a bootable guest image: Ubuntu 24.04 (arm64), the `codex` CLI,
and the urunc guest init. Published as `ghcr.io/brig-sh/codex:arm64`.

Installed from the static musl binary attached to the upstream GitHub
release, so the guest carries no node runtime. The release asset is picked
from the build architecture, so the one Dockerfile serves arm64 and amd64.

The image runs as user `codex` (uid 501 by default), and `/home/codex`
is where brig mounts your persistent home. The CLI lives in
`/usr/local/bin`, outside the home, so that mount cannot shadow it.

**Authentication.** Run `codex login`; the resulting `~/.codex/auth.json` lives in the home
directory, which brig persists. No credential is baked into the image.

## Build

```bash
make build check
```

`check` asserts the image has a guest kernel, its urunc metadata, both guest
binaries, and a `codex` the unprivileged user can run.

Pinned at `CODEX_VERSION=0.147.0`. Bump it deliberately, in a pull request -- CI
builds the new version and runs it before anything reaches the registry.

See the [top-level README](../../README.md) for the knobs, how the two build
stages fit together, and how to verify what we publish.
