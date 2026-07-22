#!/usr/bin/env bash
# Synced from main's common/ros-entrypoint.sh, plus this branch's overlay
# workspace (VINS-Fusion / MAVROS / PX4 bridge, prebuilt at image-build time
# into /opt/overlay_ws) sourced ahead of the user's mounted workspace.
set -e

# shellcheck disable=SC1090
source "/opt/ros/${ROS_DISTRO}/setup.bash"

if [ -f /opt/overlay_ws/install/setup.bash ]; then
  # shellcheck disable=SC1091
  source /opt/overlay_ws/install/setup.bash
fi

if [ -f "${WORKSPACE_DIR:-/home/dev/ws}/install/setup.bash" ]; then
  # shellcheck disable=SC1091
  source "${WORKSPACE_DIR:-/home/dev/ws}/install/setup.bash"
fi

exec "$@"
