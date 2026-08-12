# Codex guest image

Codex as a bootable guest image: Ubuntu 24.04 (arm64), the `codex` CLI,
and the urunc guest init. Published as `ghcr.io/brig-sh/codex:arm64`.

Installed from the static musl binary attached to the upstream GitHub
release, so the guest carries no node runtime. The release asset is picked
from the build architecture, so the one Dockerfile serves arm64 and amd64.

The image runs as user `codex` (uid 501 by default), and `/home/codex`
is where brig mounts your persistent home. The CLI lives in
`/usr/local/bin`, outside the home, so that mount cannot shadow it.

## Authentication

No credential is baked into the image. Sign in from inside the guest with the
device-code flow:

```bash
codex login --device-auth
codex login status          # expect: logged in
```

Or hand it a key directly, which is the easier path if the host already has
one:

```bash
printenv OPENAI_API_KEY | codex login --with-api-key
```

Either way the result lands in `~/.codex/auth.json`, in the home directory
that brig persists, so you do this once rather than once per boot.

Use `--device-auth` rather than a plain `codex login`. The plain form opens a
listener on the guest's loopback and asks the provider to redirect to
`http://localhost:<port>/callback` -- but `localhost` is whichever machine is
running the browser, and that is your host, not the guest. The browser hits
its own loopback, finds nothing listening, and the login never completes.
Device auth has no redirect and no listener: you type a short code into a
normal web page on any machine, and the CLI polls the provider outbound. A
sandboxed guest can always make outbound connections; it is inbound that it
cannot take.

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
