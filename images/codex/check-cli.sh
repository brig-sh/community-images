# Asserts that codex is installed as a complete local package. agent.mk
# pipes this into the built image as its runtime user, for both the bootable
# and the stock variant, so it is plain sh and reads nothing from the host.
#
# Since 0.156 the codex TUI starts a background app server before it draws
# anything, and that server is installed from the package the running CLI
# came from. A bare binary has no package, and codex exits with "this CLI has
# no complete local package" before the TUI starts (issue #18). `codex
# --version` still works on that image, which is why the plain CLI check in
# agent.mk passed it.
#
# The static checks mirror what codex itself requires, in
# codex-rs/install-context/src/lib.rs (CodexPackageLayout::from_exe) and
# codex-rs/app-server-daemon/src/prepare_install.rs (validate_package).

set -eu

fail() {
	echo "codex package: $*" >&2
	exit 1
}

command -v codex >/dev/null || fail "codex is not on the runtime user PATH"

# codex finds its package from its own resolved path: the exe has to sit in a
# directory named bin, with codex-package.json one level up. /usr/local/bin
# is named bin as well, so the manifest is what tells a bare binary apart.
exe=$(readlink -f "$(command -v codex)")
bindir=$(dirname "$exe")
pkg=$(dirname "$bindir")
[ "$(basename "$bindir")" = bin ] && [ -f "$pkg/codex-package.json" ] \
	|| fail "$exe is not a package entrypoint: no codex-package.json in $pkg"

# A host directory is mounted over the home at boot, so a package in there is
# gone at runtime. The standalone installer puts it under ~/.codex.
case "$pkg/" in
"$HOME"/* | /home/*) fail "$pkg is under the home directory, which brig mounts over" ;;
esac

# codex refuses a package built for another target or naming another
# entrypoint. The version check catches an image whose manifest and binary
# came from different releases.
want_target="$(uname -m)-unknown-linux-musl"
got_target=$(jq -r .target "$pkg/codex-package.json")
got_entry=$(jq -r .entrypoint "$pkg/codex-package.json")
got_ver=$(jq -r .version "$pkg/codex-package.json")
cli_ver=$(codex --version)
cli_ver=${cli_ver##* }
[ "$got_target" = "$want_target" ] \
	|| fail "manifest target is $got_target, this platform is $want_target"
[ "$got_entry" = bin/codex ] \
	|| fail "manifest entrypoint is $got_entry, codex requires bin/codex"
[ "$got_ver" = "$cli_ver" ] \
	|| fail "manifest says $got_ver, codex --version says $cli_ver"

for f in bin/codex bin/codex-code-mode-host codex-path/rg codex-resources/bwrap; do
	[ -f "$pkg/$f" ] || fail "package is incomplete: no $f"
	[ -x "$pkg/$f" ] || fail "package is incomplete: $f is not executable by $(id -un)"
done

# On first start codex hashes and copies every file of the package into
# ~/.codex as the runtime user, and it refuses a package holding a directory
# link or a link out of the package. One unreadable file or one such link
# fails that copy. A file link inside the package is copied through.
[ -z "$(find "$pkg" ! -readable)" ] \
	|| fail "$(id -un) cannot read: $(find "$pkg" ! -readable | head -3)"
[ -z "$(find "$pkg" -type d ! -executable)" ] \
	|| fail "$(id -un) cannot enter: $(find "$pkg" -type d ! -executable | head -3)"
[ -z "$(find "$pkg" -type l -xtype d)" ] \
	|| fail "package holds a directory link: $(find "$pkg" -type l -xtype d | head -3)"
escaping=$(find "$pkg" -type l | while IFS= read -r l; do
	case "$(readlink -f "$l")" in ("$pkg"/*) ;; (*) echo "$l" ;; esac
done | head -3)
[ -z "$escaping" ] || fail "package holds a link out of it: $escaping"

echo "ok: codex $cli_ver is a complete package at $pkg"

# The static checks above cover what codex validates. This runs the step that
# failed in #18: start the app server daemon the way the TUI does. The
# CODEX_HOME is a fresh directory in the home, where ~/.codex lives at
# runtime. The start needs no login and no network: agent.mk runs this
# script with --network none.
home=$(mktemp -d "$HOME/.check-codex.XXXXXX")
if ! out=$(CODEX_HOME="$home" timeout 120 codex app-server daemon start 2>&1); then
	echo "$out" >&2
	fail "codex app-server daemon start failed as $(id -un)"
fi
case "$out" in
*"no complete local package"*)
	echo "$out" >&2
	fail "codex does not recognise the package"
	;;
esac
CODEX_HOME="$home" codex app-server daemon stop >/dev/null 2>&1 || true

# `daemon stop` leaves the daemon's updater (`pid-update-loop`) running from
# the package it copied into $home, and it recreates its socket there. rm
# then races it and fails with "Directory not empty". Seen in a brig guest on
# the first start of a fresh home. The pattern matches only this mktemp home.
pkill -f "$home/" || true
i=0
while pgrep -f "$home/" >/dev/null; do
	i=$((i + 1))
	[ "$i" -le 50 ] || fail "codex processes under $home did not exit"
	sleep 0.1
done
rm -rf "$home"
echo "ok: codex app-server daemon starts as $(id -un)"
