#syntax=harbor.nbfc.io/nubificus/bunny:latest

# Cursor Agent (Cursor) in a bootable guest image.
#
# NOT PUBLISHED. This Dockerfile builds and is tested in CI, but the image is
# deliberately kept out of the default publish set: republishing Cursor's
# binary in an image we host is a redistribution question their terms have to
# answer first, and that check is still open. Build it yourself today --
# `make -C images/cursor build` fetches the CLI straight from Cursor and
# never touches our registry -- and it joins the published set once the terms
# are cleared.
#
# The #syntax line above is what makes this more than a container: the bunny
# BuildKit frontend packages the result as a microVM image -- guest kernel
# under /.boot, urunc annotations, rootfs -- so brig can boot it directly.
# Drop that line and you get an ordinary OCI image, which is also fine.
#
# No platform pin on the FROM, so the build follows --platform and the one
# Dockerfile serves arm64 and amd64; the download is chosen from the build
# architecture below.
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
RUN useradd -m -u ${AGENT_UID} -s /bin/bash cursor \
 && mkdir -p /work && chown cursor:cursor /work

# The agent package, fetched from the same URL cursor.com/install resolves to
# but with the version pinned here rather than whatever the script points at
# today -- a piped installer that moves under you is not a reproducible
# build. The tarball is a directory of files around the cursor-agent binary,
# so the whole tree lands in /usr/local/share and only the entry point is
# linked onto PATH.
#
# Under /usr/local rather than the home directory, because a host directory
# gets mounted over /home/cursor at boot. `agent` is the current name and
# `cursor-agent` the legacy one; the installer creates both, so we do too.
ARG CURSOR_VERSION=2026.08.11-e8db854
RUN arch="$(dpkg --print-architecture)" \
 && case "$arch" in \
      arm64) carch=arm64 ;; \
      amd64) carch=x64 ;; \
      *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
    esac \
 && mkdir -p /usr/local/share/cursor-agent \
 && curl -fsSL \
      "https://downloads.cursor.com/lab/${CURSOR_VERSION}/linux/${carch}/agent-cli-package.tar.gz" \
    | tar --strip-components=1 -xzf - -C /usr/local/share/cursor-agent \
 && chmod -R a+rX /usr/local/share/cursor-agent \
 && chmod 0755 /usr/local/share/cursor-agent/cursor-agent \
 && ln -s /usr/local/share/cursor-agent/cursor-agent /usr/local/bin/cursor-agent \
 && ln -s /usr/local/share/cursor-agent/cursor-agent /usr/local/bin/agent \
 && /usr/local/bin/cursor-agent --version

# No credential is baked, here or in any image in this repo. Sign in at
# runtime with `cursor-agent login`; the resulting state lives in the home
# directory, which is exactly what brig persists.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color

USER cursor
WORKDIR /home/cursor
CMD ["/bin/bash"]
