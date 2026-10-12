#!/usr/bin/env bash
# Host-side setup for the VS Code Dev Containers configs, run as their
# "initializeCommand" on the HOST (as you, not root) before the container
# is created or started:
#   1. records host UID/GID and device-group gids in the repo's ./.env via
#      write_host_env (same as scripts/setup-env.sh), which Compose reads
#      automatically and docker-compose.yml requires;
#   2. allows local X11 clients, same as scripts/run.sh;
#   3. makes sure the ros2-docker:humble-drone image exists (building it via
#      scripts/build.sh if not) and is new enough for the dev container.
#
# Usage: .devcontainer/initialize.sh [cpu|gpu]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=../scripts/lib/common.sh
source scripts/lib/common.sh

VARIANT="${1:-cpu}"
IMAGE="ros2-docker:humble-drone"
ENV_FILE=".env"

case "${VARIANT}" in
  cpu|gpu) ;;
  *) die "Unknown variant: ${VARIANT} (expected cpu or gpu)" ;;
esac

docker info >/dev/null 2>&1 \
  || die "Cannot reach the Docker daemon as $(id -un). Is Docker running, and are you in the docker group? (see README \"VS Code\")"

write_host_env "${ENV_FILE}"

xhost +local:docker >/dev/null 2>&1 || warn "xhost not available; X11 forwarding may not work"

if [ "${VARIANT}" = "gpu" ] && [ "$(detect_gpu)" != "on" ]; then
  die "GPU dev container selected, but no NVIDIA GPU + NVIDIA Container Toolkit detected. Use the CPU config, or see README \"GPU support\"."
fi

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  log "${IMAGE} not found; building it once with scripts/build.sh (this takes a while)"
  if [ "${VARIANT}" = "gpu" ]; then
    scripts/build.sh --gpu on
  else
    scripts/build.sh
  fi
fi

# Images built before the dev container support lack ~/.vscode-server, and
# the named volume mounted there would come up root-owned. Fail here with a
# clear message instead of a permission error halfway through VS Code's
# server install.
docker run --rm --network none --entrypoint /usr/bin/test "${IMAGE}" -d /home/dev/.vscode-server \
  || die "${IMAGE} predates VS Code Dev Containers support. Rebuild it with ./scripts/build.sh, then reopen."

if [ "${VARIANT}" = "gpu" ] \
    && [ "$(docker image inspect -f '{{.Id}}' "${IMAGE}")" != "$(docker image inspect -f '{{.Id}}' ros2-docker:humble-drone-gpu 2>/dev/null || true)" ]; then
  warn "${IMAGE} is not the GPU build, so PyTorch will not see CUDA. Run ./scripts/build.sh --gpu on, then rebuild the container."
fi
