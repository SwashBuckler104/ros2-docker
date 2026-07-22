#!/usr/bin/env bash
# Build the humble/drone image. No manual edits needed: GPU/UID/GID are
# auto-detected unless overridden on the command line.
#
# Usage: scripts/build.sh [--gpu on|off] [--px4] [--tag TAG]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=lib/common.sh
source scripts/lib/common.sh

GPU="$(detect_gpu)"
ENABLE_PX4="off"
TAG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --gpu) GPU="$2"; shift 2 ;;
    --px4) ENABLE_PX4="on"; shift ;;
    --tag) TAG="$2"; shift 2 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

# Default tag is GPU/CPU-variant-specific (humble-drone-gpu / humble-drone-cpu)
# so building one variant doesn't silently overwrite the other on disk. We
# also (re)point the generic ros2-docker:humble-drone tag at whichever variant
# was just built, since that's the name docker-compose.yml and run.sh expect
# for "the currently active image". An explicit --tag opts out of both.
AUTO_TAG=0
if [ -z "${TAG}" ]; then
  AUTO_TAG=1
  VARIANT="cpu"
  [ "${GPU}" = "on" ] && VARIANT="gpu"
  TAG="ros2-docker:humble-drone-${VARIANT}"
fi

IFS=: read -r HOST_UID HOST_GID <<< "$(host_uid_gid)"

log "Building ${TAG} (GPU=${GPU}, ENABLE_PX4=${ENABLE_PX4}, UID=${HOST_UID}, GID=${HOST_GID})"
docker build \
  --build-arg GPU="${GPU}" \
  --build-arg ENABLE_PX4="${ENABLE_PX4}" \
  --build-arg HOST_UID="${HOST_UID}" \
  --build-arg HOST_GID="${HOST_GID}" \
  -t "${TAG}" .

if [ "${AUTO_TAG}" -eq 1 ]; then
  docker tag "${TAG}" ros2-docker:humble-drone
  log "Also tagged as ros2-docker:humble-drone (active image for compose/run.sh)"
fi
