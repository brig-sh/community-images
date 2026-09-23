# Claude Code on Ubuntu's own account. Everything lives in ../agent.mk; this
# file is just the per-agent data. See ../agent.mk for the targets and the knobs.

AGENT := claude-ubuntu
CLI   := claude

# Not read by this Dockerfile, which creates no user and takes whatever
# ubuntu:24.04 ships. It is set so `check` asserts the uid this image actually
# has -- and, unlike claude-code, the assertion holds for the bootable variant
# too, because nothing here depends on a build argument bunny would ignore.
AGENT_UID := 1000

include ../agent.mk
