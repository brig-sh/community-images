# Claude Code on Ubuntu's own account. Everything lives in ../agent.mk; this
# file is just the per-agent data. See ../agent.mk for the targets and the knobs.

AGENT := claude-ubuntu
CLI   := claude

# Not read by this Dockerfile, which creates no user and takes whatever
# ubuntu:24.04 ships. It is set so `check` asserts the uid this image actually
# has -- and, unlike claude-code, the assertion holds for the bootable variant
# too, because nothing here depends on a build argument bunny would ignore.
AGENT_UID := 1000

# A rootless brig install needs the guest on root; see ALT_USERS in ../agent.mk.
# Published as claude-ubuntu-stock:<arch>-root, stock only, because bunny
# ignores --build-arg and the bootable image cannot take it.
ALT_USERS := root

include ../agent.mk
