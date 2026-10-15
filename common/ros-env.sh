# shellcheck shell=bash
# ROS environment for every shell in the container.
#
# The single source of truth for what a shell in the container needs
# sourced. The Dockerfile installs it at /etc/ros2-docker/ros-env.sh and it
# is *sourced* (never executed) from exactly two places, so they can't drift:
#   - /entrypoint.sh (common/ros-entrypoint.sh): PID 1 and anything started
#     through the entrypoint (`docker run`, `docker compose up`/`run`).
#   - /etc/bash.bashrc: every interactive bash that does NOT go through the
#     entrypoint -- `docker exec -it <c> bash`, scripts/enter.sh, `docker
#     exec -u root`, `sudo -i`, VS Code Dev Containers terminals and the VS
#     Code server's userEnvProbe (an interactive login shell, which reaches
#     /etc/bash.bashrc via /etc/profile).
# Before this file existed only the entrypoint sourced ROS, so only PID 1 had
# it: exec'd shells inherited the image ENV (ROS_DISTRO=humble) but never
# ran the entrypoint, leaving `ros2` off PATH and ament_cmake invisible to
# colcon (GitHub issue #1).
#
# Sources, in order, each prefix's setup.bash -- not local_setup.bash, which
# only adds that one prefix and skips the underlays it was built against:
#   1. /opt/ros/${ROS_DISTRO}   required; failure returns 1
#   2. ${OVERLAY_WS}/install    if built (prebuilt overlay; absent on
#                               branches without one, which is fine)
#   3. ${WORKSPACE_DIR}/install if built (your bind-mounted colcon workspace)
# 2 and 3 are re-checked every time this is sourced, so any shell opened
# after `colcon build` picks up the workspace overlay automatically; in a
# shell that was already open, re-run `source /etc/ros2-docker/ros-env.sh`.
#
# Safe to source from any bash, under any caller options:
#   - nounset is suspended while ROS's generated setup scripts run (they
#     read unset variables such as $AMENT_TRACE_SETUP_FILES) and restored
#     afterwards.
#   - each setup.bash is sourced as an `if` condition, which exempts it from
#     the caller's errexit -- so the entrypoint's `set -e` turns only a
#     broken ROS base install into a failed start, while a broken or stale
#     workspace overlay just warns and you can still get a shell in to fix
#     it (e.g. `rm -rf ~/ws/build ~/ws/install && colcon build`).
#   - every default below is a fallback for an environment stripped of the
#     image's ENV, e.g. a root shell via `sudo -i`/`sudo bash`, whose
#     env_reset drops ROS_DISTRO, OVERLAY_WS and WORKSPACE_DIR.

_ros_env_nounset=0
case $- in *u*) _ros_env_nounset=1; set +u ;; esac
_ros_env_status=0

_ros_env_distro="${ROS_DISTRO:-}"
if [ -z "${_ros_env_distro}" ]; then
  # No ROS_DISTRO (see sudo note above): use the only installed distro.
  for _ros_env_dir in /opt/ros/*/; do
    if [ -f "${_ros_env_dir}setup.bash" ]; then
      _ros_env_distro="$(basename "${_ros_env_dir}")"
      break
    fi
  done
fi

# shellcheck disable=SC1090
if [ -f "/opt/ros/${_ros_env_distro}/setup.bash" ] \
    && source "/opt/ros/${_ros_env_distro}/setup.bash"; then
  for _ros_env_ws in "${OVERLAY_WS:-/opt/overlay_ws}" "${WORKSPACE_DIR:-/home/dev/ws}"; do
    [ -f "${_ros_env_ws}/install/setup.bash" ] || continue
    # shellcheck disable=SC1090,SC1091
    if ! source "${_ros_env_ws}/install/setup.bash"; then
      echo "ros-env: warning: failed to source ${_ros_env_ws}/install/setup.bash" \
        "(stale build? rebuild that workspace)" >&2
    fi
  done
else
  echo "ros-env: error: could not source /opt/ros/${_ros_env_distro:-<ROS_DISTRO unset>}/setup.bash" >&2
  _ros_env_status=1
fi

if [ "${_ros_env_nounset}" = 1 ]; then set -u; fi
unset _ros_env_nounset _ros_env_distro _ros_env_dir _ros_env_ws
if [ "${_ros_env_status}" = 0 ]; then
  unset _ros_env_status
  return 0
fi
unset _ros_env_status
return 1
