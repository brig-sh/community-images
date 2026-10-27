# Asserts what a herd box adds to claude-code. agent.mk pipes this into the
# built image as its runtime user, with no network, so it is plain sh and
# reads nothing from the host.

set -eu

fail() {
	echo "herd: $*" >&2
	exit 1
}

command -v herdr >/dev/null || fail "herdr is not on the runtime user PATH"
herdr --version >/dev/null || fail "herdr does not run"
[ -s /usr/share/licenses/herdr/LICENSE ] || fail "no herdr LICENSE"

[ -x /usr/sbin/sshd ] || fail "no sshd"
[ -x /usr/local/sbin/herd-sshd ] || fail "no herd-sshd"

# A host key in the image would be the same key in every herd box.
! ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1 || fail "the image carries ssh host keys"

# The settings that let the host in with no key and keep its agent out,
# read from sshd's effective config rather than from herd.conf: sshd takes the
# first value it reads, so an earlier file could override ours. -T needs a
# host key to load, so it gets a throwaway one.
tmp=$(mktemp -d)
ssh-keygen -q -t ed25519 -N '' -f "$tmp/k"
mkdir -p /run/sshd
cfg=$(/usr/sbin/sshd -T -h "$tmp/k") || fail "sshd -T rejects the config"
rm -rf "$tmp"
for want in 'permitrootlogin yes' 'passwordauthentication yes' \
	'permitemptypasswords yes' 'allowagentforwarding no' 'allowtcpforwarding no'; do
	echo "$cfg" | grep -qix "$want" || fail "sshd is not configured with: $want"
done

# sshd accepts an empty password only for an account that has one.
[ -z "$(getent shadow root | cut -d: -f2)" ] || fail "root has a password, so sshd will ask for a key"

# The bashrc hook, by behaviour: an interactive shell with SSH_CONNECTION set,
# as in a herdr pane, reads /run/herd/env, and one without, as from `brig sh`,
# does not. Without the hook a pane never sees the environment brig forwarded;
# without the gate `brig sh` would swap its fresh session token for a stale one.
mkdir -p /run/herd
had_env=no
[ -e /run/herd/env ] && had_env=yes && mv /run/herd/env /run/herd/env.check-cli
echo 'export HERD_CHECK=sourced' >/run/herd/env
got=$(SSH_CONNECTION='UNKNOWN 65535 UNKNOWN 65535' bash -ic 'echo "${HERD_CHECK:-unset}"' 2>/dev/null)
[ "$got" = sourced ] || fail "an SSH session does not read /run/herd/env"
got=$(env -u SSH_CONNECTION bash -ic 'echo "${HERD_CHECK:-unset}"' 2>/dev/null)
[ "$got" = unset ] || fail "a shell outside SSH reads /run/herd/env"
rm -f /run/herd/env
[ "$had_env" = no ] || mv /run/herd/env.check-cli /run/herd/env

echo "ok: $(herdr --version), sshd needs no key, no baked host keys"
