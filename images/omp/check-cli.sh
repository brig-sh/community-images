#!/bin/sh
set -eu

# A fresh home and no network exercise first-run native addon extraction.
home=$(mktemp -d)
trap 'rm -rf "$home"' EXIT
export HOME="$home"
omp config path > /dev/null
test -s "$HOME/.omp/agent/agent.db"
find "$HOME/.omp/natives" -name 'pi_natives.linux-*.node' -type f -print -quit | grep -q .
