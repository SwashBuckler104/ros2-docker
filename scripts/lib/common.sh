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

# Echo the gid of host group $1, or nothing if the host has no such group.
host_group_gid() {
  getent group "$1" 2>/dev/null | cut -d: -f3 || true
}

# Echo the host's `dialout` group gid (owns serial devices like
# /dev/ttyACM0 on most Linux distros), or nothing if there isn't one --
# callers should skip --group-add entirely in that case rather than fail.
host_dialout_gid() {
  host_group_gid dialout
}

# Refuse to run as root (directly or via sudo). The host UID/GID are baked
# into the image's `dev` user and recorded in .env, and as root they'd be
# 0:0: create-user.sh would turn root itself into `dev`, and everything
# written to ./workspace would be root-owned on the host.
require_non_root() {
  if [ "$(id -u)" -eq 0 ]; then
    die "Don't run this as root or with sudo: it maps your host UID/GID into the container. Run it as your normal user; if docker then says permission denied, add yourself to the docker group (sudo usermod -aG docker \$USER, then log out and back in)."
  fi
}

# Set KEY=VALUE in env file $1, leaving every other line (e.g. your own
# ENABLE_PX4=on or BUILD_JOBS=2) alone. Only rewrites the file when
# something changes.
env_file_set() {
  local file="$1" key="$2" value="$3" tmp
  if [ -f "${file}" ] && [ "$(grep "^${key}=" "${file}" || true)" = "${key}=${value}" ]; then
    return 0
  fi
  tmp="$(mktemp "${file}.XXXXXX")"
  if [ -f "${file}" ]; then
    grep -v "^${key}=" "${file}" > "${tmp}" || true
  else
    echo "# Host ids for docker-compose.yml, kept up to date by scripts/setup-env.sh." > "${tmp}"
  fi
  echo "${key}=${value}" >> "${tmp}"
  chmod 644 "${tmp}"
  mv "${tmp}" "${file}"
}

# Remove KEY=... from env file $1, if present.
env_file_unset() {
  local file="$1" key="$2" tmp
  [ -f "${file}" ] && grep -q "^${key}=" "${file}" || return 0
  tmp="$(mktemp "${file}.XXXXXX")"
  grep -v "^${key}=" "${file}" > "${tmp}" || true
  chmod 644 "${tmp}"
  mv "${tmp}" "${file}"
}

# The one place host ids reach Compose: records the host user's UID/GID and
# the gids of the groups that own serial ports (dialout), cameras and GPU
# card nodes (video) and GPU render nodes (render) in env file $1 (default
# ./.env, which Compose reads automatically). Used by scripts/setup-env.sh,
# scripts/build.sh and .devcontainer/initialize.sh. bash and zsh don't
# export $UID/$GID, so Compose can't see them otherwise -- and
# docker-compose.yml refuses to start without these rather than silently
# falling back to 1000.
#
# A host without one of those groups gets its own primary gid in its place:
# a harmless duplicate for group_add, where an empty value would be an error.
write_host_env() {
  local file="${1:-.env}" uid gid group key value
  require_non_root
  IFS=: read -r uid gid <<< "$(host_uid_gid)"
  env_file_set "${file}" HOST_UID "${uid}"
  env_file_set "${file}" HOST_GID "${gid}"
  for group in dialout video render; do
    key="$(printf '%s' "${group}" | tr '[:lower:]' '[:upper:]')_GID"
    value="$(host_group_gid "${group}")"
    if [ -z "${value}" ]; then
      warn "Host has no '${group}' group; using your primary gid ${gid} for ${key}"
      value="${gid}"
    fi
    env_file_set "${file}" "${key}" "${value}"
  done
  # Written as UID/GID by earlier versions of .devcontainer/initialize.sh;
  # Compose now reads HOST_UID/HOST_GID instead.
  env_file_unset "${file}" UID
  env_file_unset "${file}" GID
}

log()  { printf '\033[1;34m[ros2-docker]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[ros2-docker]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ros2-docker]\033[0m %s\n' "$*" >&2; exit 1; }
