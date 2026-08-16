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
