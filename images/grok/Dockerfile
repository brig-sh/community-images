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

# Grok CLI (xAI) in a bootable guest image.
#
# The #syntax line above is what makes this more than a container: the bunny
# BuildKit frontend packages the result as a microVM image -- guest kernel
# under /.boot, urunc annotations, rootfs -- so brig can boot it directly.
# Drop that line and you get an ordinary OCI image, which is also fine.
#
# No platform pin on the FROM, so the build follows --platform and the one
# Dockerfile serves arm64 and amd64; npm resolves the per-platform binary at
# install time.
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

# Every image here carries node for the agent's extensions, but grok needs
# it for the CLI itself: @xai-official/grok is a thin node launcher, and the
# real binary arrives as the per-platform optionalDependency
# (@xai-official/grok-linux-arm64 here). NodeSource, because Ubuntu 24.04
# ships node 18.
ARG NODE_MAJOR=22
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/* \
 && node --version && npx --version

# uid 501 is the first human user on macOS. Files the agent writes to a
# virtiofs share (its persistent home, a mounted project directory) then
# carry the host user's ownership and stay writable from both sides.
ARG AGENT_UID=501
RUN useradd -m -u ${AGENT_UID} -s /bin/bash grok \
 && mkdir -p /work && chown grok:grok /work \
 && printf 'grok ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/grok \
 && chmod 0440 /etc/sudoers.d/grok

# Installed globally, outside /home, so the host directory mounted over
# /home/grok at boot cannot shadow it. Pinned -- bump deliberately.
#
# The trailing --version does two jobs: it sanity-checks the install, and it
# warms the launcher's unpack of the platform binary while we are still root.
# The chmod then keeps the unpacked artifacts readable for the unprivileged
# runtime user, which is what actually runs the agent.
# Unpinned so a rebuild picks up the current CLI; set a version to pin.
ARG GROK_VERSION=latest
RUN npm install -g @xai-official/grok@${GROK_VERSION} \
 && npm cache clean --force \
 && rm -rf /root/.npm /tmp/* \
 && grok --version \
 && chmod -R a+rX /usr/lib/node_modules

# No credential is baked, here or in any image in this repo. The provider key
# arrives at runtime as XAI_API_KEY, forwarded by the host.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color

USER grok
WORKDIR /home/grok
CMD ["/bin/bash"]
