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

# herd: Claude Code (Anthropic) and a herdr server in a bootable guest image,
# reachable over SSH through `brig exec`, so one herdr client on the host can
# manage many brig sandboxes as remote machines. One agent per sandbox.
#
# This is claude-code's Dockerfile with two differences: the agent runs as
# root, and the herd stanzas below the Claude Code install. Copied rather than
# built FROM claude-code, so the file reads top to bottom (see CONTRIBUTING).
#
# The #syntax line above is what makes this more than a container: the bunny
# BuildKit frontend packages the result as a microVM image -- guest kernel
# under /.boot, urunc annotations, rootfs -- so brig can boot it directly.
# Drop that line and you get an ordinary OCI image, which is also fine.
#
# No platform pin on the FROM, so the build follows --platform and the one
# Dockerfile serves arm64 and amd64; the installer resolves the architecture
# at build time.
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

# Root, and only root. sshd needs root to start a session, and /run/herd, where
# herd-sshd writes the carried environment, is root's. A rootless brig install
# needs a root guest anyway: rootlesskit maps container uid 0 to the invoking
# user, so a root guest is that user and owns the workspace it writes. On
# macOS hull presents the host user's files as uid 0 by default.
#
# So no account is created, and none of claude-code's uid handling applies.
# brig takes the guest account from the last element of a profile's
# `guestHome:`, so a profile for this image says `guestHome: /root`.
RUN mkdir -p /work

# The native Claude Code binary. Installed to /usr/local/bin rather than left
# where the installer puts it (~/.local/bin), because a host directory gets
# mounted over the home (/root here) at boot -- anything under it disappears.
#
# "latest" takes Anthropic's newest release at build time, because Claude Code
# ships support for a new model in a point release and the stable channel
# trails it. Pass "stable" or an exact version to pin. The in-guest
# auto-updater is off either way, so whatever is baked here is what runs until
# the next rebuild.
ARG CLAUDE_VERSION=latest
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_VERSION}" \
 && install -m 0755 "$(readlink -f /root/.local/bin/claude)" /usr/local/bin/claude \
 && rm -rf /root/.local/share/claude /root/.local/bin/claude /root/.claude* \
 && /usr/local/bin/claude --version

# sshd is the only transport herdr has for a remote machine. It is never
# listening: herd-sshd runs it in inetd mode (-i) on the stdin and stdout of a
# `brig exec`, so the guest opens no port and needs no network change.
#
# No SSH authentication: root has an empty password and sshd accepts it, so
# the host needs no key and no per-sandbox setup. The gate is `brig exec`,
# which already gives root in the guest to whoever can run it, and the guest
# has no open port for anything else to reach sshd through. No agent
# forwarding: a forwarded agent would hand the guest a signer for every key on
# the host.
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub \
 && passwd -d root \
 && printf '%s\n' \
      'PermitRootLogin yes' \
      'PasswordAuthentication yes' \
      'PermitEmptyPasswords yes' \
      'PubkeyAuthentication no' \
      'KbdInteractiveAuthentication no' \
      'AllowAgentForwarding no' \
      'AllowTcpForwarding no' \
      'X11Forwarding no' \
      > /etc/ssh/sshd_config.d/herd.conf

# herdr publishes static release binaries and no container image. The release
# binary goes in unmodified, checked against the sha256 upstream publishes in
# distribution/latest.json -- herdr signs nothing, so the checksum is the
# whole check. Building from source would need a Rust toolchain and vendored
# libghostty-vt, and a patched binary would carry license obligations an
# unmodified one does not.
#
# herdr is Apache-2.0. Its LICENSE ships beside it, pinned the same way.
ARG HERDR_VERSION=0.9.5
ARG HERDR_SHA256_ARM64=17d7536f2da50859523680ef279dffcac8e4a235f4e46fe8da6c2ec44141897c
ARG HERDR_SHA256_AMD64=14d9e8bc8b4a9e0118d77c32266f76d461f09b40342eb23752960bd89f59929d
ARG HERDR_LICENSE_SHA256=c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4
ARG TARGETARCH
RUN set -eu; \
    case "${TARGETARCH}" in \
      arm64) asset=linux-aarch64; sum="${HERDR_SHA256_ARM64}" ;; \
      amd64) asset=linux-x86_64;  sum="${HERDR_SHA256_AMD64}" ;; \
      *) echo "no herdr build for ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    base="https://github.com/herdrdev/herdr"; \
    curl -fsSL -o /usr/local/bin/herdr "${base}/releases/download/v${HERDR_VERSION}/herdr-${asset}"; \
    echo "${sum}  /usr/local/bin/herdr" | sha256sum -c -; \
    chmod 0755 /usr/local/bin/herdr; \
    mkdir -p /usr/share/licenses/herdr; \
    curl -fsSL -o /usr/share/licenses/herdr/LICENSE "https://raw.githubusercontent.com/herdrdev/herdr/v${HERDR_VERSION}/LICENSE"; \
    echo "${HERDR_LICENSE_SHA256}  /usr/share/licenses/herdr/LICENSE" | sha256sum -c -; \
    herdr --version

# herd-sshd carries the environment of the `brig exec` into every SSH session
# (see the script for why). herdr panes are interactive non-login shells, which
# read /etc/bash.bashrc and never /etc/profile.d, so the hook goes there.
COPY herd-sshd /usr/local/sbin/herd-sshd
RUN chmod 0755 /usr/local/sbin/herd-sshd \
 && printf '\n# herd: the environment brig forwarded, see /usr/local/sbin/herd-sshd\n[ -r /run/herd/env ] && . /run/herd/env\n' \
      >> /etc/bash.bashrc

# No credential is baked, here or in any image in this repo. Claude Code
# authenticates at runtime (`claude` walks you through it) and the resulting
# state lives in the home directory, which is exactly what brig persists.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color \
    DISABLE_AUTOUPDATER=1 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

USER root
WORKDIR /root
CMD ["/bin/bash"]
