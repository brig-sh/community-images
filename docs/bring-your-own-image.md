# Bring your own image

The images in this repo are a convenience, not a requirement. brig boots an
OCI image and runs a command in it, so any Linux CLI already works without a
template and without asking us to add one.

This page covers the three cases: layering on top of one of our images,
building a guest image from scratch, and running a plain container image.

## Layering on one of ours

The quickest path. Our images carry TLS roots, curl, git, a few networking
tools, the agent CLI, node for the agents' own skills and plugins, a C
toolchain, python3 with venv and pip, Rust with clippy and rustfmt, `gh`, and
passwordless `sudo` for the agent user.

That last part matters more than it sounds. The agent can `apt-get install`
whatever a task turns out to need, at runtime, without a derived image at all:

```console
$ sudo apt-get update && sudo apt-get install -y libpq-dev
```

So reach for a derived image when you want something baked in -- pinned, and
there on every boot rather than re-installed each session:

```dockerfile
FROM ghcr.io/brig-sh/claude-code:arm64

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    golang openjdk-21-jdk-headless \
 && rm -rf /var/lib/apt/lists/*
USER claude
```

Two things to keep in mind.

Install outside `/home`. A host directory gets mounted over the agent's home
at boot, so anything you put under `/home/claude` at build time disappears the
moment the guest starts. This is also why our own Dockerfiles relocate the
agent binary to `/usr/local/bin`.

Do not touch `/.boot/kernel`, `/urunc.json`, `/urunit` or `/urunit-agent`.
That is the bootable part, and it is inherited from the base for free.

## Building a guest image from scratch

For an agent we do not ship, copy the closest `images/<agent>/` directory and
replace the install stanza. The skeleton is:

```dockerfile
#syntax=harbor.nbfc.io/nubificus/bunny:latest

FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git bash procps \
 && rm -rf /var/lib/apt/lists/*

ARG AGENT_UID=501
RUN useradd -m -u ${AGENT_UID} -s /bin/bash myagent

# ... install the CLI into /usr/local/bin, then run it once with --version
# so a broken install fails the build rather than the boot ...

USER myagent
WORKDIR /home/myagent
CMD ["/bin/bash"]
```

The `#syntax` line is what makes this bootable. It swaps in
[bunny](https://github.com/nubificus/bunny) as the BuildKit frontend, which
adds a guest kernel under `/.boot` and the urunc metadata in `/urunc.json`.

Then overlay the guest init on top, which is what `Dockerfile.overlay` and
`images/agent.mk` do for you:

```bash
make -C images/myagent build check
```

`check` is worth running. It asserts the image has a kernel, its urunc
metadata, both guest binaries, and a CLI the unprivileged user can actually
run. Those are exactly the four ways an image looks fine and then fails at
boot.

## Running a plain container image

You do not need bunny at all. Drop the `#syntax` line and you have an ordinary
OCI image, which brig can boot with an external kernel rather than a bundled
one.

This is the right shape when you already have an image you trust -- a
company base image, or one of the vendors' own published images -- and you
just want an agent inside it. Add the CLI, keep everything else.

## What makes a good agent image

A few things we learned building the ones here.

**Pin the CLI version.** Piping a vendor install script that resolves to
"latest" means two builds a week apart give you two different agents, and you
find out at the worst possible moment. Every Dockerfile here takes an `ARG`
with an exact version.

**Run the CLI once at build time.** A `--version` at the end of the install
layer costs nothing and turns a silent bad install into a failed build.

**Do not bake credentials.** Not a key, not a token, not a session file. The
agent authenticates at runtime and its state lives in the home directory,
which is the part that gets persisted. An image with a key in it is an image
you cannot share, and the whole point here is images you can share.

**Check the install path is readable by the runtime user.** npm and pip
install as root; the guest does not run as root. A `chmod -R a+rX` over the
install tree is usually all it takes. Our node-based images (`gemini`, `grok`)
do exactly this.

**Keep it small.** Every megabyte is a megabyte the guest pages in at boot.
`--no-install-recommends` and a `rm -rf /var/lib/apt/lists/*` in the same
layer are the easy wins.

## Getting it added here

If you build an image for an agent we do not ship, we would like it. Open a
pull request -- see [CONTRIBUTING.md](../CONTRIBUTING.md). The bar is that it
builds, `make check` passes, and the CLI is pinned.
