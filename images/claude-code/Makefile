# Claude Code guest image. Everything lives in ../agent.mk; this file is just the
# per-agent data. See ../agent.mk for the targets and the knobs.

AGENT := claude-code
CLI   := claude

# Also published for a Linux host, whose first human user is 1000 rather than
# macOS's 501. See the uid note in Dockerfile for why this image can take it
# and the other five cannot.
ALT_UIDS := 1000

# A rootless brig install needs the guest on root; see ALT_USERS in ../agent.mk.
# Published as claude-code-stock:<arch>-root, stock only, because bunny ignores
# --build-arg and the bootable image cannot take it.
ALT_USERS := root

include ../agent.mk
