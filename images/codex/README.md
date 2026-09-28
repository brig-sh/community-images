# Codex guest image

Codex as a bootable guest image: Ubuntu 24.04 (arm64), the `codex` CLI,
and the urunc guest init. Published as `ghcr.io/brig-sh/codex:arm64`.

Installed from the `codex-package-<triple>.tar.gz` asset attached to the
upstream GitHub release, checked against the release's SHA256SUMS. codex
itself is a static musl binary, so the CLI needs no node. The guest carries
node 22 anyway, because the agent's own extensions expect it. The release
asset is picked from the build architecture, so the one Dockerfile serves
arm64 and amd64.

Since 0.156 the TUI starts a background app server, installed from the
package the CLI came from. A bare `codex` binary has no package, and exits
with "this CLI has no complete local package" unless you pass `--no-daemon`.

The image runs as user `codex` (uid 501 by default), and `/home/codex`
is where brig mounts your persistent home. The package lives in
`/usr/local/lib/codex`, with `/usr/local/bin/codex` linked to it, outside the
home, so that mount cannot shadow it.

On its first start codex copies the package, about 330MB on arm64 and 375MB
on amd64, into `~/.codex/packages/app-server-daemon`. That is your
persistent home, so it grows by that much after the first `brig run codex`.

The app server also runs an updater. By default, every 60 minutes, it runs
upstream's `install.sh` and installs the latest codex release into
`~/.codex`, replacing that copy. So the app server in your home moves to the
newest release on its own, while `/usr/local/bin/codex` stays at the version
the image was built with. The image does not control the updater: its
setting is in `~/.codex/app-server-daemon/settings.json`, in your home.

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
binaries, and a `codex` the unprivileged user can run. It also runs
[check-cli.sh](check-cli.sh), which asserts the package layout codex needs and
starts its app server daemon. `check-stock` runs the same script.

Tracks the current release: `CODEX_VERSION` defaults to `latest`, which the
build resolves to the newest release and prints in the log. To pick up a newer
one, run `Build images` on main with `image=codex` and `push` on. CI runs each
image's checks, check-cli.sh among them, before it reaches the registry, so a
release whose package codex rejects is not published.

See the [top-level README](../../README.md) for the knobs, how the two build
stages fit together, and how to verify what we publish.
