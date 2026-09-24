# claude-ubuntu

Claude Code (Anthropic) on Ubuntu's own `ubuntu` account, built as a bootable
brig guest image and as an ordinary container image.

Same contents as [`claude-code`](../claude-code), with one difference: this
image creates no user. `ubuntu:24.04` already ships `ubuntu` on 1000:1000,
which is the first human user on a Linux host, so the account the agent runs
as is already there and already on the uid that matches whoever is running
brig.

```bash
docker pull ghcr.io/brig-sh/claude-ubuntu-stock          # ordinary container
docker pull ghcr.io/brig-sh/claude-ubuntu-stock:root     # the same, on root
docker pull ghcr.io/brig-sh/claude-ubuntu                # bootable guest image
```

## The root tag

`-stock:root` is the same image ending on `root` in `/root` instead of
`ubuntu` in `/home/ubuntu`. It is a multi-arch index, like `:latest`, so one
reference works on both architectures -- the per-arch `-stock:<arch>-root`
tags it is assembled from are still there if you want to pin one. It is for a **rootless** brig install, where
1000:1000 stops being the right answer.

rootlesskit maps container uid 0 to the invoking user and 1..65536 to that
user's subuid range. On uid 1000 the guest therefore lands on a host id that
owns nothing, and two things fail: the monitor cannot open `/dev/kvm`, and the
guest cannot write the workspace that is its own home. On root the guest *is*
the invoking user, so both work and the files it writes arrive owned by that
user rather than by root.

On a root install the plain image is still the one to use: there container uid
1000 is the host's own 1000, which is the point of this image.

Stock only. bunny ignores `--build-arg`, so the bootable image stays on
`ubuntu` whatever is passed, and `check` asserts that rather than trusting it.
brig boots the stock image anyway, through `genericBoot`.

## Why this exists beside claude-code

The uid is not a convention the guest keeps to itself. hull resolves the
image's configured user against the image's own `/etc/passwd` and hands the
pair to the VMM as `--fs-uid`/`--fs-gid`, and that is what the shared home is
presented as inside the guest. Get it wrong and every file the agent writes to
a shared directory comes back owned by somebody else; configure no user at all
and the share arrives owned by root, where the agent cannot create anything at
the top of its own home and cannot repair it either -- `chown` on a virtiofs
mount root returns `EINVAL`.

`claude-code` takes its uid from `AGENT_UID`, and 501 is right for macOS. For
a Linux host it needs 1000, and there it runs into a wall: bunny, the BuildKit
frontend that packages the bootable variant, **ignores `--build-arg`**. So
`make base AGENT_UID=1000` produces a healthy-looking image still on 501, and
only the stock variant can carry a different uid.

This image reads no build argument. The account comes from the base and the
`USER` line names it, so the bootable and the stock variant land on 1000 by
construction. `make check` asserts it on both.

## Using it

The guest account is `ubuntu`, so a profile for this image says:

```yaml
guestHome: /home/ubuntu
```

Brig derives the account name from that path's last element and has no field
to set it separately, which is why the two have to agree.

## Build

```bash
make build check          # bootable image
make stock check-stock    # ordinary container image
```

`AGENT_UID` is set to 1000 in the Makefile and is only there so `check`
asserts the uid; the Dockerfile does not read it.
