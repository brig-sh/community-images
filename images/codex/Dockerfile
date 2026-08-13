#syntax=harbor.nbfc.io/nubificus/bunny:latest

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
# fetcher, git, and enough networking tooling to diagnose the guest from
# inside it, plus the node runtime installed below. Still no compiler and no
# second language runtime -- "minimal Linux + the agent CLI, and what the
# agent's own extensions need" is the contract here. Layering more on top is
# a two-line derived image; see docs/bring-your-own-image.md.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget git bash procps less file jq unzip \
    net-tools iproute2 iputils-ping dnsutils \
 && rm -rf /var/lib/apt/lists/*

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
 && mkdir -p /work && chown codex:codex /work

# Codex ships a static musl binary per release, so the CLI itself needs
# nothing from the node installed above. Installed to /usr/local/bin rather
# than the home directory, because a host directory gets mounted over
# /home/codex at boot.
#
# The asset name is a Rust target triple; map the dpkg architecture onto it
# so one Dockerfile covers both. Pinned -- bump deliberately.
ARG CODEX_VERSION=0.147.0
RUN arch="$(dpkg --print-architecture)" \
 && case "$arch" in \
      arm64) rarch=aarch64 ;; \
      amd64) rarch=x86_64 ;; \
      *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
    esac \
 && curl -fsSL -o /tmp/codex.tar.gz \
      "https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/codex-${rarch}-unknown-linux-musl.tar.gz" \
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
