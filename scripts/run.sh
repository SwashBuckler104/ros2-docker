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

# graphics,display on top of the default compute,utility makes the NVIDIA
# Container Toolkit also mount the driver's OpenGL/EGL libraries, so
# rviz2/Gazebo render on the GPU instead of Mesa's software fallback (also
# set in the GPU image; repeated here for a CPU image on a GPU host).
GPU_FLAGS=()
if [ "$(detect_gpu)" = "on" ]; then
  GPU_FLAGS=(--gpus all -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics,display)
fi

# The /dev bind-mount below only makes device nodes visible; the device
# cgroup still blocks opening them unless allowed by major number (also
# covers hot-plugged devices, and is harmless for devices the host doesn't
# have): 166 = /dev/ttyACM* (e.g. a CubeOrangePlus over USB), 188 =
# /dev/ttyUSB* (telemetry radios, USB-serial adapters), 81 = /dev/video*
# (V4L2 cameras), 226 = /dev/dri/* (GPU nodes for rviz2/Gazebo rendering).
DEVICE_FLAGS=()
for major in 166 188 81 226; do
  DEVICE_FLAGS+=(--device-cgroup-rule "c ${major}:* rmw")
done

# Those devices are normally group-owned on the host -- serial ports
# root:dialout 660, cameras and GPU card nodes root:video, GPU render nodes
# root:render -- so add the container to the host's gids for those groups,
# letting the non-root `dev` user open them without a manual chmod/sudo.
# Groups the host doesn't have are skipped.
GROUP_FLAGS=()
for group in dialout video render; do
  gid="$(host_group_gid "${group}")"
  if [ -n "${gid}" ]; then
    GROUP_FLAGS+=(--group-add "${gid}")
  fi
done

allow_x11_for_user

log "Running ${TAG} as ${NAME}"
# --init: tini as PID 1 forwards SIGTERM (an interactive bash as PID 1
# ignores it, so `docker stop` always waited 10 s, then SIGKILLed) and reaps
# processes orphaned by `ros2 launch`.
docker run -it --rm --init \
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
