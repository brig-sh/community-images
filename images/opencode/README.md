# opencode guest image

opencode as a bootable guest image: Ubuntu 24.04 (arm64), the `opencode` CLI,
and the urunc guest init. Published as `ghcr.io/brig-sh/opencode:arm64`.

Installed from the self-contained binary attached to the upstream GitHub
release, taken directly rather than through the install script so the version
is pinned and the fetch is auditable. The glibc build, not musl, since this is
Ubuntu. The CLI needs no node, but the guest carries node 22 anyway, because
the agent's own extensions expect it.

The image runs as user `opencode` (uid 501 by default), and `/home/opencode`
is where brig mounts your persistent home. The CLI lives in
`/usr/local/bin`, outside the home, so that mount cannot shadow it.

**Authentication.** opencode is provider-agnostic: the key for whichever provider you point it at
arrives from the host, and `opencode auth login` state lives in the home
directory. No credential is baked into the image.

## Build

```bash
make build check
```

`check` asserts the image has a guest kernel, its urunc metadata, both guest
binaries, and a `opencode` the unprivileged user can run.

Pinned at `OPENCODE_VERSION=1.18.16`. Bump it deliberately, in a pull request -- CI
builds the new version and runs it before anything reaches the registry.

See the [top-level README](../../README.md) for the knobs, how the two build
stages fit together, and how to verify what we publish.
