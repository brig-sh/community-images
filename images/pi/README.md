# pi guest image

pi as a bootable guest image: Ubuntu 24.04 (arm64), the `pi` CLI, and the
urunc guest init. Published as `ghcr.io/brig-sh/pi:arm64`.

pi is an open-source terminal coding agent from Earendil Works, model-agnostic
by design: Anthropic, OpenAI, Google, and any OpenAI-compatible endpoint, all
picked with `/model` at runtime.

Installed from npm as `@earendil-works/pi-coding-agent`, globally under
`/usr/local`, so the host directory brig mounts over `/home/pi` at boot cannot
shadow it. The CLI is JavaScript and needs node -- it declares
`engines.node >= 22.19.0`, so the image carries node 22 from NodeSource rather
than Ubuntu's 18.

`fd` and `ripgrep` are baked in because pi's `find` and `grep` tools are those
two underneath: pi probes the system first and otherwise downloads release
binaries from GitHub on first use, which costs every fresh guest a download and
fails outright where egress is restricted.

The image runs as user `pi` (uid 501 by default), and `/home/pi` is where brig
mounts your persistent home.

**Authentication.** Run `pi`, then `/login` for the provider you want -- or pass
a provider key in from the host. Credentials land in `~/.pi/agent/auth.json`,
inside the home directory brig persists. No credential is baked into the image.

## Build

```bash
make build check
```

`check` asserts the image has a guest kernel, its urunc metadata, both guest
binaries, and a `pi` the unprivileged user can run.

Pinned at `PI_VERSION=0.85.1`. Bump it deliberately, in a pull request -- CI
builds the new version and runs it before anything reaches the registry.

See the [top-level README](../../README.md) for the knobs, how the two build
stages fit together, and how to verify what we publish.
