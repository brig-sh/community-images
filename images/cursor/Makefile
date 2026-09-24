# Cursor Agent guest image. Everything lives in ../agent.mk; this file is just the
# per-agent data. See ../agent.mk for the targets and the knobs.

AGENT := cursor
CLI   := cursor-agent

# A rootless brig install needs the guest on root; see ALT_USERS in ../agent.mk.
# Nothing is published for this image (see the Cursor note in the README), so
# the variant is built and checked on every run and pushed on none. That is
# still worth having: it is what catches the root build breaking.
ALT_USERS := root

include ../agent.mk
