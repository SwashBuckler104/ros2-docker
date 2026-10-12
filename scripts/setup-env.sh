#!/usr/bin/env bash
# Write the host's UID/GID and device-group gids (dialout, video, render) to
# the repo's ./.env, which docker-compose.yml needs and Compose reads
# automatically. Run once per clone (and again if your user or groups
# change) before using Compose directly; scripts/build.sh and the VS Code
# dev container run it for you. Your own lines in .env are kept.
#
# Usage: scripts/setup-env.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=lib/common.sh
source scripts/lib/common.sh

[ $# -eq 0 ] || die "Unknown argument: $1 (scripts/setup-env.sh takes no arguments)"

write_host_env .env
log "Wrote $(pwd)/.env:"
grep -E '^(HOST_UID|HOST_GID|DIALOUT_GID|VIDEO_GID|RENDER_GID)=' .env | sed 's/^/  /' >&2
