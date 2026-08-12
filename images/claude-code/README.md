# Claude Code guest image

Claude Code as a bootable guest image: Ubuntu 24.04 (arm64), the `claude` CLI,
and the urunc guest init. Published as `ghcr.io/brig-sh/claude-code:arm64`.

Installed with Anthropic's own install script, then relocated to
`/usr/local/bin/claude`. The in-guest auto-updater is switched off, so the
version baked at build time is the version that runs.

The image runs as user `claude` (uid 501 by default), and `/home/claude`
is where brig mounts your persistent home. The CLI lives in
`/usr/local/bin`, outside the home, so that mount cannot shadow it.

**Authentication.** Run `claude` and it walks you through sign-in; the resulting state lives in
the home directory, which brig persists. No credential is baked into the image.

## Build

```bash
make build check
```

`check` asserts the image has a guest kernel, its urunc metadata, both guest
binaries, and a `claude` the unprivileged user can run.

Pinned at `CLAUDE_VERSION=stable`. Bump it deliberately, in a pull request -- CI
builds the new version and runs it before anything reaches the registry.

See the [top-level README](../../README.md) for the knobs, how the two build
stages fit together, and how to verify what we publish.
