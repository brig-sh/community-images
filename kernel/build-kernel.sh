#!/usr/bin/env bash
#
# Build a guest kernel for the brig agent images, by profile.
#
# A profile is a setup, not an architecture: it names the machine the guest
# boots on and the way its root arrives, and from that follows which drivers
# have to be compiled *in*. The guests boot with no initramfs, so a driver
# needed to reach the root filesystem cannot be a module -- it would live on
# the filesystem it is required to mount. Everything else stays modular and is
# simply never shipped, which is what keeps the kernel small.
#
#   PROFILE=arm64   brig on Apple Silicon: virtiofs root under Apple
#                   Virtualization.framework. Ships an uncompressed arm64
#                   `Image`, which is what VZLinuxBootLoader accepts.
#   PROFILE=amd64   urunc on Linux: block root (an ext4 devmapper snapshot).
#                   Ships a bzImage.
#
#   PROFILE=amd64 ./kernel/build-kernel.sh
#
# Output, into $OUT (default ./dist):
#
#   kernel        the bootable image, named the same for both profiles so the
#                 consuming side never has to care which one it pulled
#   config        the exact .config it was built with
#   config.diff   defconfig -> final .config, so the delta is reviewable
#   KVER          the kernel version string
#
# The build runs inside a container of the target platform, so the host needs
# only Docker -- no cross-toolchain, and the same script works on an Apple
# Silicon Mac as in CI. Building the amd64 profile on an arm64 host works but
# is emulated and slow; CI runs each profile on a native runner.
#
# A cold build is tens of minutes. $CCACHE_DIR is reused across runs, and CI
# caches it, so iterating is much cheaper than the first time.
set -euo pipefail

PROFILE="${PROFILE:-arm64}"
KVER="${KVER:-6.12.95}"                 # 6.12 LTS, pinned; bump deliberately
OUT="${OUT:-$(pwd)/dist}"
CCACHE_DIR="${CCACHE_DIR:-${TMPDIR:-/tmp}/brig-kernel-ccache}"
BUILDER_IMG="${BUILDER_IMG:-debian:bookworm-slim}"

# The shipped kernel must stay small. BTF pulls DWARF into the intermediate
# vmlinux (hundreds of MB); the final link strips it back to the loadable
# kernel plus the compact .BTF section. This gate catches the regression where
# debug info leaks into what we ship.
MAX_IMAGE_MB="${MAX_IMAGE_MB:-80}"

# Common to both profiles.
#
# Written as a plain list rather than an array of arrays: this has to run under
# the bash 3.2 that ships with macOS.
REQUIRED_Y_BASE="
  VIRTIO VIRTIO_PCI VIRTIO_BLK VIRTIO_NET VIRTIO_CONSOLE
  VIRTIO_MMIO VIRTIO_MMIO_CMDLINE_DEVICES
  VSOCKETS VIRTIO_VSOCKETS
  IP_PNP IP_PNP_DHCP
  EXT4_FS DEVTMPFS DEVTMPFS_MOUNT TMPFS SHMEM OVERLAY_FS
  UNIX INET INOTIFY_USER PCI
"
# VIRTIO_CONSOLE gives /sys/class/virtio-ports, which is how the in-guest exec
# agent finds its transport. VIRTIO_MMIO covers VMMs that present virtio over
# MMIO rather than PCI (virtio_mmio.device= on the cmdline); VIRTIO_PCI stays
# on, so Vz and QEMU are unaffected. IP_PNP is what makes the `ip=dhcp` on the
# cmdline do anything: urunit is PID 1 and no dhcp client runs, so without it
# the guest comes up with no address and no /proc/net/pnp. OVERLAY_FS must be
# built in because the init mounts a tmpfs-upper overlay over the root, and
# defconfig leaves it =m -- dead weight in a guest that ships no /lib/modules.

# arm64: virtiofs root, so FUSE and virtio-fs are the ones that cannot be
# modules. PCI_HOST_GENERIC is the PCIe host the VZ platform exposes.
REQUIRED_Y_ARM64="
  FUSE_FS VIRTIO_FS PCI_HOST_GENERIC TMPFS_POSIX_ACL BINFMT_MISC
"
# amd64: block root, so ext2/ext4 are the ones that matter. virtio-fs is built
# in as well -- it is not the root here, but it is how shared directories
# arrive, and one symbol is cheaper than a second profile.
REQUIRED_Y_AMD64="
  EXT2_FS FUSE_FS VIRTIO_FS
"
# BTF (/sys/kernel/btf/vmlinux) for in-guest bpf/CO-RE tooling. DEBUG_INFO_BTF
# has real dependencies: DEBUG_KERNEL gates the "Debug information" choice and
# BPF_SYSCALL is required. DWARF5 keeps the intermediate debug info smaller
# than DWARF4, and pahole encodes it into the .BTF section that survives the
# strip.
REQUIRED_Y_BTF="
  DEBUG_KERNEL BPF_SYSCALL DEBUG_INFO_DWARF5 DEBUG_INFO_BTF
"

case "$PROFILE" in
  arm64)
    REQUIRED_Y="$REQUIRED_Y_BASE $REQUIRED_Y_ARM64 $REQUIRED_Y_BTF"
    PLATFORM="linux/arm64"; KARCH="arm64"; MAKE_TARGET="Image"
    BUILT="arch/arm64/boot/Image"
    ;;
  amd64)
    REQUIRED_Y="$REQUIRED_Y_BASE $REQUIRED_Y_AMD64 $REQUIRED_Y_BTF"
    PLATFORM="linux/amd64"; KARCH="x86_64"; MAKE_TARGET="bzImage"
    BUILT="arch/x86/boot/bzImage"
    ;;
  *)
    echo "!! unknown PROFILE '$PROFILE' (want: arm64|amd64)" >&2; exit 1 ;;
esac

JOBS="${JOBS:-$(docker run --rm --platform "$PLATFORM" "$BUILDER_IMG" nproc)}"

mkdir -p "$OUT" "$CCACHE_DIR"

echo ">> building Linux $KVER kernel ($PROFILE profile, $PLATFORM, $JOBS jobs)"

docker run --rm --platform "$PLATFORM" \
  -e KVER="$KVER" -e JOBS="$JOBS" -e KARCH="$KARCH" \
  -e MAKE_TARGET="$MAKE_TARGET" -e BUILT="$BUILT" \
  -e REQUIRED_Y="$REQUIRED_Y" -e MAX_IMAGE_MB="$MAX_IMAGE_MB" \
  -v "$OUT":/out -v "$CCACHE_DIR":/ccache \
  "$BUILDER_IMG" bash -euxo pipefail -c '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    # dwarves provides pahole, which generates the BTF from the DWARF info.
    apt-get install -y -qq --no-install-recommends \
      build-essential bc bison flex libssl-dev libelf-dev dwarves \
      cpio xz-utils wget kmod ccache python3 ca-certificates
    export PATH=/usr/lib/ccache:$PATH
    export CCACHE_DIR=/ccache CCACHE_MAXSIZE=5G
    ccache -z >/dev/null || true

    cd /usr/src
    SER="v${KVER%%.*}.x"
    # An exact tarball, not a git branch: a branch moves under you, and this
    # repo pins everything else it installs.
    wget -q "https://cdn.kernel.org/pub/linux/kernel/$SER/linux-$KVER.tar.xz"
    tar -xf "linux-$KVER.tar.xz"
    cd "linux-$KVER"

    export ARCH=$KARCH
    make defconfig
    cp .config /out/defconfig.base

    # BTF needs the DWARF "Debug information" choice active, so clear the
    # conflicting members first -- olddefconfig would otherwise keep NONE.
    ./scripts/config --disable DEBUG_INFO_NONE
    ./scripts/config --disable DEBUG_INFO_REDUCED
    ./scripts/config --disable DEBUG_INFO_SPLIT

    for sym in $REQUIRED_Y; do
      ./scripts/config --enable "$sym"
    done
    # MODULES deliberately stays enabled. Turning it off does not make a lean
    # guest kernel -- it makes an enormous one, because olddefconfig then has
    # to resolve every =m in defconfig to =y or =n, and most resolve to =y. The
    # arm64 Image came out at 92MB that way, with WLAN and sound built into a
    # headless microVM.
    #
    # Leaving it on costs nothing. The drivers this guest actually needs are
    # forced =y above and are in the image; everything else stays =m and is
    # simply never shipped, since the guest carries no /lib/modules and nothing
    # ever calls modprobe.
    make olddefconfig

    # Hard gate. `scripts/config --enable` is a request: a symbol whose
    # dependencies are unmet stays unset and the build still succeeds, which is
    # how you ship a kernel that panics before userspace.
    fail=0
    for sym in $REQUIRED_Y; do
      if ! grep -q "^CONFIG_${sym}=y$" .config; then
        echo "!! CONFIG_${sym} is NOT =y (got: $(grep "CONFIG_${sym}\b" .config || echo unset))" >&2
        fail=1
      fi
    done
    [ "$fail" = 0 ] || { echo "!! required built-ins missing -- aborting" >&2; exit 2; }

    make -j"$JOBS" CC="ccache gcc" "$MAKE_TARGET"

    # Boot-image sanity, per architecture. VZLinuxBootLoader rejects anything
    # that is not an uncompressed arm64 Image with ARMd at 0x38; a bzImage is
    # identified by the 0xAA55 boot signature at 0x1FE.
    python3 - "$BUILT" "$KARCH" <<PY
import sys
data = open(sys.argv[1], "rb").read()
if sys.argv[2] == "arm64":
    assert data[0x38:0x3c] == b"ARMd", "arm64 Image magic @0x38 is %r, expected ARMd" % data[0x38:0x3c]
else:
    assert data[0x1fe:0x200] == b"\x55\xaa", "bzImage boot signature @0x1fe is %r, expected 55aa" % data[0x1fe:0x200]
print("   boot magic OK (%s)" % sys.argv[2])
PY

    grep -q "^CONFIG_DEBUG_INFO_BTF=y$" .config || { echo "!! BTF not enabled" >&2; exit 4; }

    sz_mb=$(( $(stat -c %s "$BUILT") / 1024 / 1024 ))
    if [ "$sz_mb" -gt "$MAX_IMAGE_MB" ]; then
      echo "!! kernel is ${sz_mb}MB > ${MAX_IMAGE_MB}MB cap (debug info leaked?)" >&2
      exit 5
    fi

    # One name for both profiles, so whatever pulls this does not have to know
    # whether it got an Image or a bzImage.
    cp "$BUILT" /out/kernel
    cp .config /out/config
    echo "$KVER" > /out/KVER
    diff -u /out/defconfig.base .config > /out/config.diff || true
    rm -f /out/defconfig.base
    ccache -s | sed "s/^/   ccache: /" || true
    ls -l /out/kernel
  '

echo ">> OK. $PROFILE kernel $(cat "$OUT/KVER")"
echo "   $OUT/kernel        (bootable image)"
echo "   $OUT/config        (final .config)"
echo "   $OUT/config.diff   (defconfig -> final delta)"
