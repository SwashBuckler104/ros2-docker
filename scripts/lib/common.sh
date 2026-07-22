#!/usr/bin/env bash
# Shared helpers sourced by scripts/build.sh, run.sh, enter.sh on every
# branch. Copied verbatim into each branch; re-sync from main if this
# changes.

# Detect whether an NVIDIA GPU + the NVIDIA container runtime are usable.
# Echoes "on" or "off".
detect_gpu() {
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    if docker info 2>/dev/null | grep -qi nvidia; then
      echo "on"
      return
    fi
  fi
  echo "off"
}

# Echo "UID:GID" for the invoking host user, for build-arg passthrough.
host_uid_gid() {
  echo "$(id -u):$(id -g)"
}

log()  { printf '\033[1;34m[ros2-docker]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[ros2-docker]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ros2-docker]\033[0m %s\n' "$*" >&2; exit 1; }
