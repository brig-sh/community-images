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

# Codex (OpenAI) in a bootable guest image.
#
# The #syntax line above is what makes this more than a container: the bunny
# BuildKit frontend packages the result as a microVM image -- guest kernel
# under /.boot, urunc annotations, rootfs -- so brig can boot it directly.
# Drop that line and you get an ordinary OCI image, which is also fine.
#
# No platform pin on the FROM, so the build follows --platform and the one
# Dockerfile serves arm64 and amd64; the release asset is chosen from the
# build architecture below.
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
RUN useradd -m -u ${AGENT_UID} -s /bin/bash codex \
 && mkdir -p /work && chown codex:codex /work \
 && printf 'codex ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/codex \
 && chmod 0440 /etc/sudoers.d/codex

# Codex ships a static musl binary per release, so the CLI itself needs
# nothing from the node installed above. Installed to /usr/local/bin rather
# than the home directory, because a host directory gets mounted over
# /home/codex at boot.
#
# The asset name is a Rust target triple; map the dpkg architecture onto it
# so one Dockerfile covers both. Pinned -- bump deliberately.
# "latest" resolves the newest release at build time; set an explicit version
# to pin. Unpinned by default so a rebuild picks up the current CLI -- the
# whole point of rebuilding these images -- and the resolved version is echoed
# into the log so a build can still be traced back to what it installed.
ARG CODEX_VERSION=latest
RUN arch="$(dpkg --print-architecture)" \
 && case "$arch" in \
      arm64) rarch=aarch64 ;; \
      amd64) rarch=x86_64 ;; \
      *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
    esac \
 && ver="$CODEX_VERSION" \
 && if [ "$ver" = latest ]; then \
      ver="$(curl -fsSL https://api.github.com/repos/openai/codex/releases/latest \
             | sed -n 's/.*"tag_name" *: *"rust-v\([^"]*\)".*/\1/p' | head -1)"; \
      [ -n "$ver" ] || { echo "could not resolve the latest codex release" >&2; exit 1; }; \
      echo "codex: resolved latest to $ver"; \
    fi \
 && curl -fsSL -o /tmp/codex.tar.gz \
      "https://github.com/openai/codex/releases/download/rust-v${ver}/codex-${rarch}-unknown-linux-musl.tar.gz" \
 && mkdir -p /tmp/codex-x && tar -xzf /tmp/codex.tar.gz -C /tmp/codex-x \
 && install -m 0755 /tmp/codex-x/codex* /usr/local/bin/codex \
 && rm -rf /tmp/codex.tar.gz /tmp/codex-x \
 && /usr/local/bin/codex --version

# No credential is baked, here or in any image in this repo. Sign in at
# runtime with `codex login --device-auth`; the resulting ~/.codex/auth.json
# lives in the home directory, which is exactly what brig persists.
#
# The device-code flow specifically, not plain `codex login`. That one opens a
# listener on the guest's loopback and hands the provider a redirect_uri of
# http://localhost:<port>/callback -- but `localhost` is whichever machine is
# running the *browser*, and that is the host, not the guest. The browser hits
# its own loopback, finds nothing listening, and the login never completes.
# Device auth has no redirect and no listener: the CLI polls the provider
# outbound, which is all a sandboxed guest can do anyway.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color

USER codex
WORKDIR /home/codex
CMD ["/bin/bash"]
