#syntax=harbor.nbfc.io/nubificus/bunny:latest

# Gemini CLI (Google) in a bootable guest image.
#
# The #syntax line above is what makes this more than a container: the bunny
# BuildKit frontend packages the result as a microVM image -- guest kernel
# under /.boot, urunc annotations, rootfs -- so brig can boot it directly.
# Drop that line and you get an ordinary OCI image, which is also fine.
#
# No platform pin on the FROM, so the build follows --platform and the one
# Dockerfile serves arm64 and amd64; the package is architecture-independent
# JavaScript.
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

# Every image here carries node for the agent's extensions, but Gemini CLI
# needs it for the CLI itself: it publishes no native Linux binary, only an
# npm package whose bin is a bundled gemini.js. NodeSource, because Ubuntu
# 24.04 ships node 18 and the package requires >= 20.
ARG NODE_MAJOR=22
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/* \
 && node --version && npx --version

# uid 501 is the first human user on macOS. Files the agent writes to a
# virtiofs share (its persistent home, a mounted project directory) then
# carry the host user's ownership and stay writable from both sides.
ARG AGENT_UID=501
RUN useradd -m -u ${AGENT_UID} -s /bin/bash gemini \
 && mkdir -p /work && chown gemini:gemini /work

# Installed globally, outside /home, so the host directory mounted over
# /home/gemini at boot cannot shadow it. Pinned -- bump deliberately.
#
# The trailing --version doubles as the install's own sanity check, and the
# chmod keeps the tree readable for the unprivileged runtime user: npm
# installs as root here, and the guest does not run as root.
# Unpinned so a rebuild picks up the current CLI; set a version to pin.
ARG GEMINI_VERSION=latest
RUN npm install -g @google/gemini-cli@${GEMINI_VERSION} \
 && npm cache clean --force \
 && rm -rf /root/.npm /tmp/* \
 && gemini --version \
 && chmod -R a+rX /usr/lib/node_modules

# No credential is baked, here or in any image in this repo. Gemini CLI
# authenticates at runtime, either interactively or from GEMINI_API_KEY
# passed in by the host; the resulting state lives in the home directory,
# which is exactly what brig persists.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color

USER gemini
WORKDIR /home/gemini
CMD ["/bin/bash"]
