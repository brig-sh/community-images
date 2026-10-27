# herd guest image

Claude Code and a [herdr](https://herdr.dev) server in one guest, so one
herdr client on the host can manage many brig sandboxes as remote machines,
one agent each. Published as `ghcr.io/brig-sh/herd-stock` (what brig boots,
through genericBoot) and `ghcr.io/brig-sh/herd` (bootable, opt-in in CI like
every other image).

It is the claude-code image on root, with three additions:

- `openssh-server`, with no SSH authentication and agent and TCP forwarding
  off. The gate is `brig exec`; see below.
- `herdr`, the upstream release binary, unmodified and checked against the
  sha256 upstream publishes. Its Apache-2.0 LICENSE is in
  `/usr/share/licenses/herdr/`.
- `/usr/local/sbin/herd-sshd`, the SSH end of the box.

## How the host reaches it

herdr only speaks SSH to a remote machine, and a brig guest has no open port.
So the host's ssh runs `herd-sshd` through `brig exec` as its ProxyCommand,
and `herd-sshd` runs `sshd -i` on that exec's stdin and stdout:

```sshconfig
Host herd*+*
  User root
  ForwardAgent no
  StrictHostKeyChecking yes
  UserKnownHostsFile /dev/null
  KnownHostsCommand /bin/sh -c 'r=$(echo "$1" | sed "s/+/@/") && k=$(brig -q exec "$r" -- cat /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null) && [ -n "$k" ] && echo "$1 $k"' sh %n
  LogLevel ERROR
  ProxyCommand sh -c 'exec brig -q exec "${1%%+*}@${1#*+}" -- /usr/local/sbin/herd-sshd 2>/dev/null' sh %n
```

`herd+api` then means the sandbox `herd@api`:

```bash
brig run -d herd@api
herdr machine add herd+api --label api
```

`brig exec`, not `brig sh`: `brig sh` always asks for a terminal, and a
terminal in the middle of the SSH stream hangs it.

## What to know before you use it

**No SSH key.** root has an empty password and sshd accepts it. Whoever can
run `brig exec` on the host is already root in the guest, and the guest has
no open port, so a key would guard nothing that `brig exec` does not.

**Root only.** sshd needs root to start a session, so there is no `claude`
account variant. The guest home is `/root`, as in brig's claude-code profile.

**The environment crosses into the panes.** sshd starts each session clean,
which would leave Claude Code in a herdr pane with no broker token and no CA
bundle. `herd-sshd` writes the environment brig gave the exec to
`/run/herd/env` (tmpfs, root, 0600) and `/etc/bash.bashrc` sources it in an
SSH session only, so `brig sh` keeps the token brig gave it. It is never
written to the guest home, which is host disk. A pane keeps the values it
started with; a new SSH connection refreshes the file for the next one.

**Host keys change on every boot.** The image ships none -- baked keys would
be the same public key in every herd box -- and the rootfs does not survive
`brig stop`, so `herd-sshd` generates them on first connect. The ssh config
above reads the current key through `brig exec` rather than from a
known_hosts file, which would report a changed key after every restart.

**The Claude Code release tracks latest,** as in claude-code: a rebuild
picks up the newest release, and CI's `claude_version` input applies to herd
too. The Dockerfile is a copy of claude-code's rather than built `FROM` it, so
a change to claude-code's has to be made here as well.

## Build

```bash
make stock check-stock   # what brig boots
make build check         # the bootable variant
```

`check-cli.sh` adds the herd checks to both: herdr runs, sshd's effective
config takes the empty root password with forwarding off, no host keys are
baked in, and an interactive shell reads the carried environment only in an
SSH session.

herdr is pinned at `HERDR_VERSION=0.9.5`, with the sha256 of each release
binary and of its LICENSE beside it in the Dockerfile. Bump all four together,
deliberately, in a pull request -- CI builds the new version and runs it
before anything reaches the registry.

See the [top-level README](../../README.md) for the knobs, how the two build
stages fit together, and how to verify what we publish.
