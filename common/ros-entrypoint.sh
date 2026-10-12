#!/usr/bin/env bash
# Canonical entrypoint stanza, shared across every branch. Copied verbatim
# into each branch and pinned; re-sync from main if this changes.
#
# Sources the ROS environment (ROS2 base install -> prebuilt overlay
# workspace, if any -> user workspace, if built) via
# /etc/ros2-docker/ros-env.sh (common/ros-env.sh), then execs whatever
# command the container was given. That file is also what /etc/bash.bashrc
# sources for shells that never pass through here (`docker exec`, VS Code
# terminals), so PID 1 and exec'd shells always get the same environment.
#
# Doubles as a one-shot wrapper for non-interactive commands that bypass the
# entrypoint and so read no bashrc, e.g.
#   docker exec <container> /entrypoint.sh ros2 topic list
set -e

# shellcheck source=ros-env.sh
source /etc/ros2-docker/ros-env.sh

exec "$@"
