#syntax=harbor.nbfc.io/nubificus/bunny:latest

# Claude Code (Anthropic) in a bootable guest image.
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

# uid 501 is the first human user on macOS. Files the agent writes to a
# virtiofs share (its persistent home, a mounted project directory) then
# carry the host user's ownership and stay writable from both sides.
ARG AGENT_UID=501
RUN useradd -m -u ${AGENT_UID} -s /bin/bash claude \
 && mkdir -p /work && chown claude:claude /work \
 && printf 'claude ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/claude \
 && chmod 0440 /etc/sudoers.d/claude

# The native Claude Code binary. Installed to /usr/local/bin rather than left
# where the installer puts it (~/.local/bin), because a host directory gets
# mounted over /home/claude at boot -- anything under the home disappears.
#
# "stable" tracks Anthropic's stable channel at build time; pass an exact
# version to pin. The in-guest auto-updater is off either way, so whatever is
# baked here is what runs until the next rebuild.
ARG CLAUDE_VERSION=stable
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_VERSION}" \
 && install -m 0755 "$(readlink -f /root/.local/bin/claude)" /usr/local/bin/claude \
 && rm -rf /root/.local/share/claude /root/.local/bin/claude /root/.claude* \
 && /usr/local/bin/claude --version

# No credential is baked, here or in any image in this repo. Claude Code
# authenticates at runtime (`claude` walks you through it) and the resulting
# state lives in the home directory, which is exactly what brig persists.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color \
    DISABLE_AUTOUPDATER=1 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

USER claude
WORKDIR /home/claude
CMD ["/bin/bash"]
