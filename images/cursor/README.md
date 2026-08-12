# Cursor Agent guest image

Cursor Agent as a bootable guest image: Ubuntu 24.04 (arm64), the `cursor-agent` CLI,
and the urunc guest init. Build it locally; we do not publish it (see below).

**Not published.** It builds, and CI exercises it on every pull request, but
we do not host it -- publishing would mean redistributing Cursor's binary from
our registry, and that is a question their terms have to answer first. Build
it yourself with the command below; it fetches the CLI straight from Cursor
and never touches our registry.

Installed from the same URL `cursor.com/install` resolves to, but with the
version pinned here rather than whatever the script points at today. A piped
installer that moves under you is not a reproducible build.

The image runs as user `cursor` (uid 501 by default), and `/home/cursor`
is where brig mounts your persistent home. The CLI lives in
`/usr/local/bin`, outside the home, so that mount cannot shadow it.

**Authentication.** Run `cursor-agent login`; the resulting state lives in the home directory. No credential is baked into the image.

## Build

```bash
make build check
```

`check` asserts the image has a guest kernel, its urunc metadata, both guest
binaries, and a `cursor-agent` the unprivileged user can run.

Pinned at `CURSOR_VERSION=2026.08.11-e8db854`. Bump it deliberately, in a pull request -- CI
builds the new version and runs it before anything reaches the registry.

See the [top-level README](../../README.md) for the knobs, how the two build
stages fit together, and how to verify what we publish.
