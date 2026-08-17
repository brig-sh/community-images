#syntax=harbor.nbfc.io/nubificus/bunny:latest@sha256:f4e9d86375f6975600d3c569a717ee9c6b2d9d5f607ad1d4a49daa05d8cf3893

# Pinned by digest, not by :latest.
#
# This line is not a base image, it is the BuildKit frontend: BuildKit fetches
# it and hands it this Dockerfile, and whatever comes back decides what the
# resulting image contains. It is arbitrary code with total authority over the
# artifact, pulled from a registry that is neither GitHub nor Sigstore, and
# :latest is a tag whoever controls that registry can move at any time.
#
# The signature does not cover this. Signing attests who built the image and
# from which workflow -- never what went into it -- so an image built by a
# swapped frontend signs cleanly, verifies cleanly, and contains whatever the
# frontend decided to put there.
#
# Bump deliberately, and resolve the digest rather than copying one:
#   crane digest harbor.nbfc.io/nubificus/bunny:latest

# Cursor Agent (Cursor) in a bootable guest image.
#
# NOT PUBLISHED. This Dockerfile builds and is tested in CI, but the image is
# deliberately kept out of the default publish set: republishing Cursor's
# binary in an image we host is a redistribution question their terms have to
# answer first, and that check is still open. Build it yourself today --
# `make -C images/cursor build` fetches the CLI straight from Cursor and
# never touches our registry -- and it joins the published set once the terms
# are cleared.
#
# The #syntax line above is what makes this more than a container: the bunny
# BuildKit frontend packages the result as a microVM image -- guest kernel
# under /.boot, urunc annotations, rootfs -- so brig can boot it directly.
# Drop that line and you get an ordinary OCI image, which is also fine.
#
# No platform pin on the FROM, so the build follows --platform and the one
# Dockerfile serves arm64 and amd64; the download is chosen from the build
# architecture below.
FROM ubuntu:24.04

# The shared base every agent image in this repo starts from: TLS roots, a
# fetcher, git, enough networking tooling to diagnose the guest from inside
# it, and a working toolchain.
#
# The toolchain is not decoration. An agent asked to fix a bug will try to
# build and test the thing it just edited, and a guest with no cc(1) fails at
# that point with an error about the project rather than about the image.
# python3 with venv and pip for the same reason.
#
# sudo is passwordless for the agent user, so it can apt-get install whatever
# the task turns out to need. That is not a hole in the sandbox: the boundary
# here is the VM, not the user account inside it, and an agent that cannot
# install a missing header is an agent that stops halfway through the job. The
# stock container variant inherits this too, which is worth knowing if you run
# it somewhere the container boundary *is* your boundary.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget git bash procps less file jq unzip \
    net-tools iproute2 iputils-ping dnsutils \
    sudo build-essential pkg-config python3 python3-venv python3-pip \
 && rm -rf /var/lib/apt/lists/*

# The GitHub CLI, from GitHub's own signed apt repo rather than a release
# tarball, so apt keeps it current alongside everything else. The keyring is
# fetched fail-closed (a bad download aborts the layer), and the repo's arch
# comes from dpkg so one line resolves on both arm64 and amd64.
RUN install -m 0755 -d /usr/share/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && chmod 0644 /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/* \
 && gh --version

# Rust, via rustup, under /usr/local rather than a home directory -- a host
# directory is mounted over the agent's home at boot and would hide it.
#
# The minimal profile plus clippy and rustfmt: an agent writing Rust reaches
# for `cargo clippy` and `cargo fmt` immediately, while the offline docs the
# default profile installs are dead weight in a sandbox.
#
# a+rwX, not a+rX, because the agent runs unprivileged and rustup writes into
# these trees whenever it adds a target or a component.
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUN curl -fsSL https://sh.rustup.rs \
      | sh -s -- -y --no-modify-path --profile minimal -c clippy -c rustfmt \
 && chmod -R a+rwX /usr/local/rustup /usr/local/cargo \
 && rustc --version && cargo --version && cargo clippy --version

# node, for the agent's own extensions rather than for the CLI itself. Skills
# and plugins routinely shell out to node or npx -- installing a Claude Code
# plugin runs npm behind the scenes -- and a guest without them fails at the
# point of use, with an error that names the skill rather than the image.
# NodeSource, because Ubuntu 24.04 ships node 18.
ARG NODE_MAJOR=22
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/* \
 && node --version && npx --version

# uid 501 is the first human user on macOS. Files the agent writes to a
# virtiofs share (its persistent home, a mounted project directory) then
# carry the host user's ownership and stay writable from both sides.
ARG AGENT_UID=501
RUN useradd -m -u ${AGENT_UID} -s /bin/bash cursor \
 && mkdir -p /work && chown cursor:cursor /work \
 && printf 'cursor ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/cursor \
 && chmod 0440 /etc/sudoers.d/cursor

# The agent package, fetched from the same URL cursor.com/install resolves to
# but with the version pinned here rather than whatever the script points at
# today -- a piped installer that moves under you is not a reproducible
# build. The tarball is a directory of files around the cursor-agent binary,
# so the whole tree lands in /usr/local/share and only the entry point is
# linked onto PATH.
#
# Under /usr/local rather than the home directory, because a host directory
# gets mounted over /home/cursor at boot. `agent` is the current name and
# `cursor-agent` the legacy one; the installer creates both, so we do too.
ARG CURSOR_VERSION=2026.08.11-e8db854
RUN arch="$(dpkg --print-architecture)" \
 && case "$arch" in \
      arm64) carch=arm64 ;; \
      amd64) carch=x64 ;; \
      *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
    esac \
 && mkdir -p /usr/local/share/cursor-agent \
 && curl -fsSL \
      "https://downloads.cursor.com/lab/${CURSOR_VERSION}/linux/${carch}/agent-cli-package.tar.gz" \
    | tar --strip-components=1 -xzf - -C /usr/local/share/cursor-agent \
 && chmod -R a+rX /usr/local/share/cursor-agent \
 && chmod 0755 /usr/local/share/cursor-agent/cursor-agent \
 && ln -s /usr/local/share/cursor-agent/cursor-agent /usr/local/bin/cursor-agent \
 && ln -s /usr/local/share/cursor-agent/cursor-agent /usr/local/bin/agent \
 && /usr/local/bin/cursor-agent --version

# No credential is baked, here or in any image in this repo. Sign in at
# runtime with `cursor-agent login`; the resulting state lives in the home
# directory, which is exactly what brig persists.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color

USER cursor
WORKDIR /home/cursor
CMD ["/bin/bash"]
