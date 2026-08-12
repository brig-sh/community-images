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
# fetcher, git, and enough networking tooling to diagnose the guest from
# inside it. Deliberately no compiler and no language runtime the agent does
# not need -- "minimal Linux + the agent CLI" is the contract here. Layering
# a toolchain on top is a two-line derived image; see
# docs/bring-your-own-image.md.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget git bash procps less file jq unzip \
    net-tools iproute2 iputils-ping dnsutils \
 && rm -rf /var/lib/apt/lists/*

# uid 501 is the first human user on macOS. Files the agent writes to a
# virtiofs share (its persistent home, a mounted project directory) then
# carry the host user's ownership and stay writable from both sides.
ARG AGENT_UID=501
RUN useradd -m -u ${AGENT_UID} -s /bin/bash claude \
 && mkdir -p /work && chown claude:claude /work

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
