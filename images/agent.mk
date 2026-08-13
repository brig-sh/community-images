# Shared build rules for every agent image. Each images/<agent>/Makefile sets
# AGENT (and whatever it wants to override) and includes this file.
#
#   make build   # bunny base + guest binaries -> local IMAGE tag
#   make check   # assert the built image is bootable and has the CLI
#   make push    # push IMAGE to the registry (crane)
#   make all     # build + check + push
#
# The guest binaries (urunit, urunit-agent) are compiled from source rather
# than vendored, so an image always ships the current agent-capable init.
# Both sources are public, so nothing here needs credentials:
#
#   URUNC_SRC   a urunc checkout on the darwin/converge line, which is where
#               cmd/urunit-agent lives (nofireai/urunc_fork)
#   URUNIT_SRC  a urunit checkout with the controlling-tty fix
#
# Leave them unset and `make build` clones both into dist/src itself.
#
# Everything compiles natively inside containers of the target platform, so
# no host cross-toolchain is needed -- this runs anywhere Docker does,
# including an Apple Silicon Mac.
#
# The default is arm64, which is what hull boots on macOS. For urunc on Linux:
#
#   make build PLATFORM=linux/amd64

REGISTRY    ?= ghcr.io/brig-sh
PLATFORM    ?= linux/arm64
# The tag follows the platform, so `make build PLATFORM=linux/amd64` produces
# the amd64 image without having to restate the tag as well.
TAG         ?= $(if $(filter linux/amd64,$(PLATFORM)),amd64,arm64)
IMAGE       ?= $(REGISTRY)/$(AGENT):$(TAG)
# Per-arch, so building both locally does not have one clobber the other.
BASE_TAG    ?= brig-$(AGENT):base-$(TAG)

# uid 501 is the first human user on macOS. Files the agent writes to a
# virtiofs share (its persistent home, a mounted project) then land with the
# host user's ownership and stay writable both ways. Override on Linux hosts.
AGENT_UID   ?= 501

SOURCE_URL  ?= https://github.com/brig-sh/community-images
REVISION    ?= $(shell git rev-parse HEAD 2>/dev/null || echo unknown)

URUNC_SRC   ?=
URUNIT_SRC  ?=
URUNC_REPO  ?= https://github.com/nofireai/urunc_fork
URUNC_REF   ?= darwin/converge
URUNIT_REPO ?= https://github.com/NOFireAI/urunit
URUNIT_REF  ?= fix/controlling-tty

BUILD_DIR   := dist

# Both platforms currently boot on the kernel bunny bundles. Swapping in one of
# the published profiles (ghcr.io/brig-sh/kernel:<profile>, built by
# ../../kernel/build-kernel.sh) is the next step and is not wired up here yet.
#
# An earlier attempt passed the kernel to bunny as a --build-arg. It does not
# take: the image built fine and silently shipped bunny's kernel anyway, which
# is why `check` below now compares what is in the image against what we
# staged. The mechanism that does work is a COPY over /.boot/kernel in the
# overlay.

# Resolved lazily: an explicit *_SRC wins, otherwise use the checkout that
# the `sources` target clones into dist/src.
urunc_src   = $(if $(URUNC_SRC),$(abspath $(URUNC_SRC)),$(CURDIR)/$(BUILD_DIR)/src/urunc)
urunit_src  = $(if $(URUNIT_SRC),$(abspath $(URUNIT_SRC)),$(CURDIR)/$(BUILD_DIR)/src/urunit)

.PHONY: all build sources base binaries overlay check push clean

all: build check push

build: base binaries overlay

# 0. guest-init sources, unless the caller pointed at their own checkouts.
sources:
	@test -n "$(URUNC_SRC)"  || test -d "$(urunc_src)"  || \
		git clone --depth 1 -b $(URUNC_REF) $(URUNC_REPO) $(urunc_src)
	@test -n "$(URUNIT_SRC)" || test -d "$(urunit_src)" || \
		git clone --depth 1 -b $(URUNIT_REF) $(URUNIT_REPO) $(urunit_src)

# 1. bunny base image. The #syntax line in the Dockerfile makes BuildKit
#    package the result as a bootable image: guest kernel under /.boot,
#    urunc annotations, rootfs.
base:
	DOCKER_BUILDKIT=1 docker build --platform $(PLATFORM) \
		--build-arg AGENT_UID=$(AGENT_UID) \
		--provenance=false --sbom=false \
		-t $(BASE_TAG) -f Dockerfile .

# 2. guest binaries, each compiled natively inside a container of the target
#    platform from a read-only mount of the checkout. -buildvcs=false because
#    the mount is a git repo the in-container user does not own, so git exits
#    128 and Go's VCS stamping would fail the build.
binaries: $(BUILD_DIR)/urunit-agent $(BUILD_DIR)/urunit

$(BUILD_DIR)/urunit-agent: | $(BUILD_DIR)
	$(MAKE) sources
	docker run --rm --platform $(PLATFORM) \
		-v $(urunc_src):/src:ro -v $(CURDIR)/$(BUILD_DIR):/out \
		golang:1.26 bash -euc \
		'cd /src && CGO_ENABLED=0 go build -buildvcs=false -o /out/urunit-agent ./cmd/urunit-agent'

$(BUILD_DIR)/urunit: | $(BUILD_DIR)
	$(MAKE) sources
	docker run --rm --platform $(PLATFORM) \
		-v $(urunit_src):/src:ro -v $(CURDIR)/$(BUILD_DIR):/out \
		ubuntu:24.04 bash -euc '\
			apt-get update -qq && apt-get install -y -qq --no-install-recommends make gcc libc6-dev >/dev/null; \
			cp -r /src /build && make -C /build static >/dev/null && cp /build/dist/urunit_static /out/urunit'

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# 3. overlay the guest binaries onto the base. A plain docker build, on
#    purpose: bunny injects its own stock urunit, which the agent-capable one
#    has to override, and a plain build inherits bunny's kernel and urunc
#    annotations untouched.
overlay:
	@test -f $(BUILD_DIR)/urunit -a -f $(BUILD_DIR)/urunit-agent \
		|| { echo "run 'make binaries' first"; exit 1; }
	DOCKER_BUILDKIT=1 docker build --platform $(PLATFORM) \
		--build-arg BASE=$(BASE_TAG) \
		--build-arg SOURCE_URL=$(SOURCE_URL) \
		--build-arg REVISION=$(REVISION) \
		--provenance=false --sbom=false \
		-t $(IMAGE) -f Dockerfile.overlay .

# 4. assert the thing we are about to publish is actually bootable and
#    actually carries the agent. This is not a boot test -- it cannot be, off
#    an Apple Silicon host -- but it catches the failures that would otherwise
#    ship silently: an overlay that dropped bunny's kernel or its urunc
#    metadata, or a CLI installed somewhere the unprivileged user cannot run
#    it from.
#
# bunny records the urunc metadata in /urunc.json (base64 values), not in
# image labels, which is why the overlay's plain `FROM` keeps it -- but that
# is worth asserting rather than assuming, since a dropped urunc.json still
# produces a perfectly good-looking container image that simply never boots.
#
# The CLI check runs as the image's own user, not root: an agent installed
# under a root-only path passes `test -x` and then fails at boot.
check:
	@echo "==> checking $(IMAGE)"
	@docker run --rm --platform $(PLATFORM) --entrypoint /bin/sh --user root $(IMAGE) -c '\
		set -e; \
		test -s /urunit       || { echo "missing /urunit"; exit 1; }; \
		test -s /urunit-agent || { echo "missing /urunit-agent"; exit 1; }; \
		test -s /.boot/kernel || { echo "missing guest kernel"; exit 1; }; \
		grep -q com.urunc.unikernel.binary /urunc.json \
			|| { echo "no urunc metadata -- the overlay dropped bunny/urunc.json"; exit 1; }; \
		echo "ok: kernel + urunit + urunit-agent + urunc.json"'
	@docker run --rm --platform $(PLATFORM) --entrypoint /bin/sh $(IMAGE) -c '\
		set -e; command -v $(CLI) >/dev/null || { echo "$(CLI) not on the runtime user PATH"; exit 1; }; \
		echo "ok: $(CLI) runnable as $$(id -un)"'
	@# node, as the runtime user. The agents' skills and plugins shell out to
	@# node and npx, so a guest missing either fails at the point of use with
	@# an error that names the skill rather than the image. npx is asserted
	@# separately because it arrives with the nodejs package rather than on
	@# its own, and that is an assumption worth checking rather than trusting.
	@docker run --rm --platform $(PLATFORM) --entrypoint /bin/sh $(IMAGE) -c '\
		set -e; \
		command -v node >/dev/null || { echo "node not on the runtime user PATH"; exit 1; }; \
		command -v npx  >/dev/null || { echo "npx not on the runtime user PATH";  exit 1; }; \
		echo "ok: node $$(node --version), npx $$(npx --version)"'
	@# If a kernel was staged for this build, the image must actually be
	@# carrying it. Asserting only that /.boot/kernel is non-empty is not
	@# enough: a staged kernel that never lands leaves bunny's default in
	@# place, the image looks perfectly healthy, and the build silently
	@# shipped something other than what it compiled. That happened.
	@if [ -s $(BUILD_DIR)/kernel ]; then \
		want=$$( (sha256sum $(BUILD_DIR)/kernel 2>/dev/null || shasum -a 256 $(BUILD_DIR)/kernel) | cut -d' ' -f1 ); \
		got=$$(docker run --rm --platform $(PLATFORM) --entrypoint /bin/sh --user root $(IMAGE) \
			-c 'sha256sum /.boot/kernel' | cut -d' ' -f1); \
		if [ "$$want" != "$$got" ]; then \
			echo "the image is not carrying the kernel we staged"; \
			echo "  staged:   $$want"; \
			echo "  in image: $$got"; \
			exit 1; \
		fi; \
		echo "ok: /.boot/kernel matches $(BUILD_DIR)/kernel"; \
	fi

push:
	docker save $(IMAGE) -o $(BUILD_DIR)/image.tar
	crane push $(BUILD_DIR)/image.tar $(IMAGE)
	rm -f $(BUILD_DIR)/image.tar

clean:
	rm -rf $(BUILD_DIR)
	-docker rmi $(BASE_TAG) $(IMAGE) 2>/dev/null || true
