# Claude Code guest image

Claude Code as a bootable guest image: Ubuntu 24.04 (arm64), the `claude` CLI,
and the urunc guest init. Published as `ghcr.io/brig-sh/claude-code:arm64`.

Installed with Anthropic's own install script, then relocated to
`/usr/local/bin/claude`. The in-guest auto-updater is switched off, so the
version baked at build time is the version that runs.

The CLI is a native binary and needs no node, but the guest carries node 22
because skills and plugins do: installing a plugin runs npm, and plenty of
skills shell out to `node` or `npx`.

The image runs as user `claude` (uid 501 by default), and `/home/claude`
is where brig mounts your persistent home. The CLI lives in
`/usr/local/bin`, outside the home, so that mount cannot shadow it.

501 is the first human user on macOS. On a Linux host it is 1000, so build
with `AGENT_UID=1000` if you want files the agent writes to a bind mount or a
share to come back owned by you:

```bash
make stock AGENT_UID=1000
```

CI publishes that build too, so you do not have to make it yourself:

```bash
docker pull ghcr.io/brig-sh/claude-code-stock:uid1000
```

`:uid1000` is the multi-arch index, with `:arm64-uid1000` and `:amd64-uid1000`
beside it. `:latest` is unchanged and still means the 501 build.

Stock only. The bootable `claude-code` package has no uid tags, because bunny
ignores `--build-arg` and a bootable image built with `AGENT_UID=1000` comes
out on 501 anyway -- healthy-looking and wrong. `make check` asserts the uid
now, so that image fails its own check instead of being published.

The account is `claude` either way. At 1000 it is Ubuntu's own `ubuntu` user
renamed rather than a second account beside it, which is also what puts the
group on 1000 -- at the 501 default the group lands on 1001, because `ubuntu`
is still holding 1000.

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
