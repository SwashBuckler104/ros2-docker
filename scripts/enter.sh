#!/usr/bin/env bash
# Exec an interactive shell into an already-running humble/drone container.
#
# Usage: scripts/enter.sh [--name NAME]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=lib/common.sh
source scripts/lib/common.sh

NAME="ros2-docker-humble-drone"

while [ $# -gt 0 ]; do
  case "$1" in
    --name) require_value "$@"; NAME="$2"; shift 2 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

docker ps --format '{{.Names}}' | grep -qx "${NAME}" \
  || die "No running container named ${NAME}. Start one with scripts/run.sh first."

log "Entering ${NAME}"
docker exec -it "${NAME}" bash
