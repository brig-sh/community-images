# Grok CLI guest image. Everything lives in ../agent.mk; this file is just the
# per-agent data. See ../agent.mk for the targets and the knobs.

AGENT := grok
CLI   := grok

# A rootless brig install needs the guest on root; see ALT_USERS in ../agent.mk.
# Published as grok-stock:<arch>-root, stock only, because bunny ignores
# --build-arg and the bootable image cannot take it.
ALT_USERS := root

include ../agent.mk
