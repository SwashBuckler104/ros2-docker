#!/usr/bin/env bash
# Shared helpers sourced by scripts/build.sh, run.sh, enter.sh on every
# branch. Copied verbatim into each branch; re-sync from main if this
# changes.

# Detect whether an NVIDIA GPU + the NVIDIA Container Toolkit are usable.
# Echoes "on" or "off".
#
# Deliberately does NOT check `docker info` for a registered "nvidia"
# runtime -- recent nvidia-container-toolkit versions (verified: 1.19.1)
# make `docker run --gpus all` work without registering a distinct runtime
# in /etc/docker/daemon.json at all, so that check silently reports "off"
# even when GPU passthrough actually works. `nvidia-container-cli info` is
# the toolkit's own functional check: it talks to the driver *and* confirms
# containers can actually reach the GPU, without spinning up a container or
# needing network access.
detect_gpu() {
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1 \
      && command -v nvidia-container-cli >/dev/null 2>&1 \
      && nvidia-container-cli info >/dev/null 2>&1; then
    echo "on"
    return
  fi
  echo "off"
}

# Echo "UID:GID" for the invoking host user, for build-arg passthrough.
host_uid_gid() {
  echo "$(id -u):$(id -g)"
}

# Echo a default for the BUILD_JOBS build arg: one compile job per 3 GiB of
# total RAM (each Ceres/VINS compiler process can peak at 1-2 GB, plus
# headroom for whatever else the machine is doing), capped at the CPU count.
# Uses MemTotal rather than MemAvailable so the value -- and with it the
# Docker build cache -- stays the same from one build to the next.
default_build_jobs() {
  local mem_kib jobs cpus
  mem_kib="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || true)"
  cpus="$(nproc 2>/dev/null || echo 1)"
  jobs=$(( ${mem_kib:-0} / (3 * 1024 * 1024) ))
  [ "${jobs}" -lt 1 ] && jobs=1
  [ "${jobs}" -gt "${cpus}" ] && jobs="${cpus}"
  echo "${jobs}"
}

# Echo the host's `dialout` group gid (owns serial devices like
# /dev/ttyACM0 on most Linux distros), or nothing if there isn't one --
# callers should skip --group-add entirely in that case rather than fail.
host_dialout_gid() {
  getent group dialout 2>/dev/null | cut -d: -f3 || true
}

log()  { printf '\033[1;34m[ros2-docker]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[ros2-docker]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ros2-docker]\033[0m %s\n' "$*" >&2; exit 1; }
