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
 && mkdir -p /work && chown gemini:gemini /work \
 && printf 'gemini ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/gemini \
 && chmod 0440 /etc/sudoers.d/gemini

# Installed globally, outside /home, so the host directory mounted over
# /home/gemini at boot cannot shadow it. Pinned -- bump deliberately.
#
# The trailing --version doubles as the install's own sanity check, and the
# chmod keeps the tree readable for the unprivileged runtime user: npm
# installs as root here, and the guest does not run as root.
ARG GEMINI_VERSION=0.55.1
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
