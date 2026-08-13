#syntax=harbor.nbfc.io/nubificus/bunny:latest

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
# fetcher, git, and enough networking tooling to diagnose the guest from
# inside it, plus the node runtime installed below. Still no compiler and no
# second language runtime -- "minimal Linux + the agent CLI, and what the
# agent's own extensions need" is the contract here. Layering more on top is
# a two-line derived image; see docs/bring-your-own-image.md.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget git bash procps less file jq unzip \
    net-tools iproute2 iputils-ping dnsutils \
 && rm -rf /var/lib/apt/lists/*

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
 && mkdir -p /work && chown grok:grok /work

# Installed globally, outside /home, so the host directory mounted over
# /home/grok at boot cannot shadow it. Pinned -- bump deliberately.
#
# The trailing --version does two jobs: it sanity-checks the install, and it
# warms the launcher's unpack of the platform binary while we are still root.
# The chmod then keeps the unpacked artifacts readable for the unprivileged
# runtime user, which is what actually runs the agent.
ARG GROK_VERSION=1.0.0
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
