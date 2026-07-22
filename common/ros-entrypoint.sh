#!/usr/bin/env bash
# Canonical entrypoint stanza, shared across every branch. Copied verbatim
# into each branch and pinned; re-sync from main if this changes.
#
# Sources the ROS2 base install, then the workspace overlay if it has been
# built, then execs whatever command the container was given.
set -e

# shellcheck disable=SC1090
source "/opt/ros/${ROS_DISTRO}/setup.bash"

if [ -f "${WORKSPACE_DIR:-/home/dev/ws}/install/setup.bash" ]; then
  # shellcheck disable=SC1091
  source "${WORKSPACE_DIR:-/home/dev/ws}/install/setup.bash"
fi

exec "$@"
