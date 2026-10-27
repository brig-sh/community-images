# herd guest image: claude-code plus a herdr server. Everything lives in
# ../agent.mk; this file is just the per-agent data. See ../agent.mk for the
# targets and the knobs.

AGENT := herd
CLI   := claude

# Root, and only root; see the account note in Dockerfile. Not read by the
# Dockerfile, which creates no user. Set so `check` and `check-stock` assert
# the uid the image actually has.
AGENT_UID := 0

# The Dockerfile ARG that picks the Claude Code release; see CLI_VERSION in
# ../agent.mk.
CLI_VERSION_ARG := CLAUDE_VERSION

include ../agent.mk
