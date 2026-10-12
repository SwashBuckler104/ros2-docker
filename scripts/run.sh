#!/usr/bin/env bash
# Run the humble/drone container with the correct GPU/X11/device/volume
# flags. No manual edits needed.
#
# Usage: scripts/run.sh [--tag TAG] [--name NAME] [-- extra docker args]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=lib/common.sh
source scripts/lib/common.sh

TAG="ros2-docker:humble-drone"
NAME="ros2-docker-humble-drone"
EXTRA_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --) shift; EXTRA_ARGS=("$@"); break ;;
    *) die "Unknown argument: $1" ;;
  esac
done

GPU_FLAGS=()
if [ "$(detect_gpu)" = "on" ]; then
  GPU_FLAGS=(--gpus all)
fi

# /dev/dri (GPU render nodes, integrated or discrete) doesn't exist on
# headless hosts -- only pass it through when present, so this still runs
# on any PC (CPU-only cloud VM, laptop with just an iGPU, etc).
DEVICE_FLAGS=()
if [ -e /dev/dri ]; then
  DEVICE_FLAGS+=(--device /dev/dri:/dev/dri)
fi

# The /dev bind-mount below only makes device nodes visible; the device
# cgroup still blocks opening them unless allowed by major number (also
# covers hot-plugged devices): 166 = /dev/ttyACM* (e.g. a CubeOrangePlus
# over USB), 188 = /dev/ttyUSB* (telemetry radios, USB-serial adapters).
DEVICE_FLAGS+=(--device-cgroup-rule 'c 166:* rmw' --device-cgroup-rule 'c 188:* rmw')

# Serial devices (e.g. a CubeOrangePlus on /dev/ttyACM0) are normally
# root:dialout 660 on the host; add the container to that gid so the
# non-root `dev` user can open them without a manual chmod/sudo.
GROUP_FLAGS=()
DIALOUT_GID="$(host_dialout_gid)"
if [ -n "${DIALOUT_GID}" ]; then
  GROUP_FLAGS+=(--group-add "${DIALOUT_GID}")
fi

xhost +local:docker >/dev/null 2>&1 || warn "xhost not available; X11 forwarding may not work"

log "Running ${TAG} as ${NAME}"
docker run -it --rm \
  --name "${NAME}" \
  --network host \
  --ipc host \
  -e DISPLAY="${DISPLAY:-}" \
  -e QT_X11_NO_MITSHM=1 \
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
  -v "$(pwd)/workspace:/home/dev/ws:rw" \
  -v /dev:/dev \
  "${DEVICE_FLAGS[@]}" \
  "${GROUP_FLAGS[@]}" \
  "${GPU_FLAGS[@]}" \
  "${EXTRA_ARGS[@]}" \
  "${TAG}"
