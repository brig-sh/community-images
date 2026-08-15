#syntax=harbor.nbfc.io/nubificus/bunny:latest

# opencode (OSS, provider-agnostic) in a bootable guest image.
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
RUN useradd -m -u ${AGENT_UID} -s /bin/bash opencode \
 && mkdir -p /work && chown opencode:opencode /work

# opencode publishes a single self-contained binary per platform, so the CLI
# itself needs nothing from the node installed above -- the npm package is a
# launcher around the same artifact. Taken straight from the GitHub release
# rather than through the install script, so the version is pinned and the
# fetch is auditable.
# The glibc build, not -musl, because this is Ubuntu.
#
# Installed to /usr/local/bin rather than the home directory, because a host
# directory gets mounted over /home/opencode at boot.
# "latest" resolves the newest release at build time; set an explicit version
# to pin. See the codex image for the reasoning.
ARG OPENCODE_VERSION=latest
RUN arch="$(dpkg --print-architecture)" \
 && case "$arch" in \
      arm64) oarch=linux-arm64 ;; \
      amd64) oarch=linux-x64 ;; \
      *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
    esac \
 && ver="$OPENCODE_VERSION" \
 && if [ "$ver" = latest ]; then \
      ver="$(curl -fsSL https://api.github.com/repos/sst/opencode/releases/latest \
             | sed -n 's/.*"tag_name" *: *"v\([^"]*\)".*/\1/p' | head -1)"; \
      [ -n "$ver" ] || { echo "could not resolve the latest opencode release" >&2; exit 1; }; \
      echo "opencode: resolved latest to $ver"; \
    fi \
 && curl -fsSL -o /tmp/opencode.tar.gz \
      "https://github.com/sst/opencode/releases/download/v${ver}/opencode-${oarch}.tar.gz" \
 && mkdir -p /tmp/opencode-x && tar -xzf /tmp/opencode.tar.gz -C /tmp/opencode-x \
 && install -m 0755 /tmp/opencode-x/opencode /usr/local/bin/opencode \
 && rm -rf /tmp/opencode.tar.gz /tmp/opencode-x \
 && /usr/local/bin/opencode --version

# No credential is baked, here or in any image in this repo. opencode is
# provider-agnostic: the key for whichever provider you point it at arrives
# at runtime from the host, and `opencode auth login` state lives in the home
# directory, which is exactly what brig persists.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color

USER opencode
WORKDIR /home/opencode
CMD ["/bin/bash"]
