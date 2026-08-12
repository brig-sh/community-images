# Grok CLI guest image

Grok CLI as a bootable guest image: Ubuntu 24.04 (arm64), the `grok` CLI,
and the urunc guest init. Published as `ghcr.io/brig-sh/grok:arm64`.

`@xai-official/grok` is a thin node launcher and the real binary arrives as
a per-platform optional dependency, so the guest carries node 22 for the
launcher. The build runs `grok --version` as root, which warms the
launcher's unpack of the platform binary, then makes the unpacked tree
readable for the unprivileged user that actually runs the agent.

The image runs as user `grok` (uid 501 by default), and `/home/grok`
is where brig mounts your persistent home. The CLI lives in
`/usr/local/bin`, outside the home, so that mount cannot shadow it.

**Authentication.** The provider key arrives at runtime as `XAI_API_KEY`, forwarded by the
host. No credential is baked into the image.

## Build

```bash
make build check
```

`check` asserts the image has a guest kernel, its urunc metadata, both guest
binaries, and a `grok` the unprivileged user can run.

Pinned at `GROK_VERSION=1.0.0`. Bump it deliberately, in a pull request -- CI
builds the new version and runs it before anything reaches the registry.

See the [top-level README](../../README.md) for the knobs, how the two build
stages fit together, and how to verify what we publish.
