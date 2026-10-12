#!/usr/bin/env bash
# Host-side setup for the VS Code Dev Containers configs, run as their
# "initializeCommand" on the HOST (as you, not root) before the container
# is created or started:
#   1. records host UID/GID/dialout gid in the repo's ./.env, which Compose
#      reads automatically (bash does not export $UID/$GID, so
#      ${UID:-1000} etc. in docker-compose.yml would otherwise fall back to
#      the defaults);
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

# Set KEY=VALUE in ./.env, leaving any other lines (e.g. your own
# ENABLE_PX4=on) alone. Only rewrites the file when the value changes.
set_env() {
  local key="$1" value="$2" tmp
  if [ -f "${ENV_FILE}" ] && [ "$(grep "^${key}=" "${ENV_FILE}" || true)" = "${key}=${value}" ]; then
    return
  fi
  tmp="$(mktemp "${ENV_FILE}.XXXXXX")"
  if [ -f "${ENV_FILE}" ]; then
    grep -v "^${key}=" "${ENV_FILE}" > "${tmp}" || true
  else
    echo "# Host ids for docker-compose.yml, kept up to date by .devcontainer/initialize.sh." > "${tmp}"
  fi
  echo "${key}=${value}" >> "${tmp}"
  chmod 644 "${tmp}"
  mv "${tmp}" "${ENV_FILE}"
}

IFS=: read -r HOST_UID HOST_GID <<< "$(host_uid_gid)"
set_env UID "${HOST_UID}"
set_env GID "${HOST_GID}"
DIALOUT_GID="$(host_dialout_gid)"
if [ -n "${DIALOUT_GID}" ]; then
  set_env DIALOUT_GID "${DIALOUT_GID}"
fi

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
