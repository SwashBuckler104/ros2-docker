# syntax=docker/dockerfile:1
#
# ros2-docker :: humble/drone
# VINS-Fusion (VIO) + MAVROS/PX4 + Gazebo + Stable-Baselines3 RL, on ROS2
# Humble / Ubuntu 22.04. Self-contained: builds FROM an upstream ROS/CUDA
# base only, no dependency on another branch or a GHCR base image.
#
# Build args:
#   GPU          off|on   (default off) -- off: osrf/ros:humble-desktop
#                                          on:  nvidia/cuda + ROS2 installed
#   ENABLE_PX4   off|on   (default off) -- adds px4_msgs/px4_ros_com + Micro
#                                          XRCE-DDS Agent on top of MAVROS
#   UID/GID      host user/group ids to map onto the in-container `dev` user

ARG GPU=off

# ---------------------------------------------------------------------------
# Base: GPU=off -> plain ROS2 Humble desktop image
# ---------------------------------------------------------------------------
FROM osrf/ros:humble-desktop@sha256:3d87cf339919a85cff7743ec9ba5e7ec81ccc26c9f722f1c7a6af5008dfdc128 AS base-off

# ---------------------------------------------------------------------------
# Base: GPU=on -> CUDA/cuDNN runtime image with ROS2 Humble desktop layered
# on top the same way osrf/ros builds it, so both stages end up equivalent.
# ---------------------------------------------------------------------------
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04@sha256:2fcc4280646484290cc50dce5e65f388dd04352b07cbe89a635703bd1f9aedb6 AS base-on

ARG ROS_DISTRO=humble
ENV ROS_DISTRO=${ROS_DISTRO} \
    DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
      locales curl gnupg2 lsb-release ca-certificates software-properties-common \
    && locale-gen en_US en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    && curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
      -o /usr/share/keyrings/ros-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" \
      > /etc/apt/sources.list.d/ros2.list \
    && apt-get update && apt-get install -y --no-install-recommends \
      ros-humble-desktop ros-dev-tools \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Select base per GPU arg, then everything below is identical for both.
# ---------------------------------------------------------------------------
# base-off/base-on are internal stages pinned by digest above (lines 20/26),
# not a registry pull -- there's no further tag to add here.
# hadolint ignore=DL3006
FROM base-${GPU} AS base

ARG GPU=off
ARG ROS_DISTRO=humble
# Named HOST_UID/HOST_GID, not UID/GID: Docker exports every declared ARG as
# an env var for subsequent RUN instructions, and an inherited UID/GID env
# var silently overrides bash's readonly $UID/$GID builtins in every RUN
# after this point -- including inside install_geographiclib_datasets.sh
# below, which checks $UID==0 to detect root and fails if it's shadowed.
ARG HOST_UID=1000
ARG HOST_GID=1000
ARG ENABLE_PX4=off

ENV ROS_DISTRO=${ROS_DISTRO} \
    DEBIAN_FRONTEND=noninteractive \
    WORKSPACE_DIR=/home/dev/ws \
    OVERLAY_WS=/opt/overlay_ws

# pipefail so a failing `grep`/`cmake`/etc. earlier in a pipe (e.g. the
# apt-packages.txt filter below) fails the RUN instead of being masked by
# the last command's exit code -- /bin/sh's default shell doesn't do this.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# --- Layer: common system + build-toolchain packages -----------------------
COPY deps/apt-packages.txt /tmp/apt-packages.txt
RUN apt-get update \
    && grep -vE '^\s*#|^\s*$' /tmp/apt-packages.txt | xargs apt-get install -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* /tmp/apt-packages.txt

# --- Layer: ROS2 dev tools (colcon, rosdep) + rosdep init ------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3-colcon-common-extensions python3-rosdep \
    && rm -rf /var/lib/apt/lists/* \
    && (rosdep init || true) && rosdep update

# --- Layer: non-root dev user, UID/GID-mapped to the host -----------------
COPY common/create-user.sh /tmp/create-user.sh
# `env FOO=bar cmd`, not `FOO=bar cmd`: now that SHELL is bash (for pipefail
# above), a bare `UID=... cmd` prefix-assignment fails outright ("readonly
# variable") because bash rejects assigning to its own $UID builtin even in
# prefix-assignment form -- it only ever *inherits* UID from an environment,
# never lets you assign it directly. Routing through the external `env`
# sets the child's environment without going through bash's assignment
# syntax at all, so create-user.sh (itself bash, which does inherit env UID
# into its own read-only $UID at startup) still sees the intended value.
#
# rosdep keeps its cache per user (~/.ros/rosdep), and `rosdep update` above
# ran as root, so `dev` gets a copy: otherwise every rosdep command as `dev`
# fails with "your rosdep installation has not been initialized yet".
RUN chmod +x /tmp/create-user.sh \
    && env DEV_USER=dev UID=${HOST_UID} GID=${HOST_GID} /tmp/create-user.sh \
    && rm /tmp/create-user.sh \
    && mkdir -p ${WORKSPACE_DIR}/src ${OVERLAY_WS}/src /home/dev/.ros \
    && cp -r /root/.ros/rosdep /home/dev/.ros/rosdep \
    && chown -R ${HOST_UID}:${HOST_GID} /home/dev ${OVERLAY_WS}

# --- Layer: Ceres Solver 2.1.0, built from source (VINS-Fusion dependency) -
ARG CERES_COMMIT=f68321e7de8929fbcdb95dd42877531e64f72f66
# hadolint ignore=DL3003
RUN git clone https://github.com/ceres-solver/ceres-solver.git /tmp/ceres-solver \
    && cd /tmp/ceres-solver \
    && git checkout ${CERES_COMMIT} \
    && mkdir build && cd build \
    && cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /tmp/ceres-solver

# --- Layer: VINS-Fusion (ROS2 Humble port), pinned commit ------------------
# fanhong-li/VINS-Fusion-ROS2-Humble: OpenCV4 + Ceres 2.1.0 + Eigen 3.3.9,
# explicitly targets Humble/Ubuntu 22.04 (verified against upstream before
# pinning -- see README "Pinned sources").
ARG VINS_REPO=https://github.com/fanhong-li/VINS-Fusion-ROS2-Humble.git
ARG VINS_COMMIT=8993f559d93f7235c7cefe8f4951ef349d8cf245
# hadolint ignore=DL3003
RUN git clone ${VINS_REPO} ${OVERLAY_WS}/src/VINS-Fusion-ROS2-Humble \
    && cd ${OVERLAY_WS}/src/VINS-Fusion-ROS2-Humble \
    && git checkout ${VINS_COMMIT}

# --- Layer: MAVROS (default-on autopilot bridge) + GeographicLib datasets --
RUN apt-get update && apt-get install -y --no-install-recommends \
      ros-humble-mavros ros-humble-mavros-extras \
    && rm -rf /var/lib/apt/lists/* \
    && /opt/ros/${ROS_DISTRO}/lib/mavros/install_geographiclib_datasets.sh

# --- Layer: PX4 bridge (opt-in via ENABLE_PX4=on) --------------------------
# px4_msgs v1.14.0 tag + px4_ros_com release/v1.14 branch head: the pairing
# matching PX4 firmware v1.14, the release line with mature ROS2 Humble
# support (verified against upstream refs before pinning).
ARG PX4_MSGS_COMMIT=ffb6e80e1c17e5714395611a020c282a87af8fa4
ARG PX4_ROS_COM_COMMIT=e18248db6211350e6a418cb08ae38f64c314a2f4
ARG MICRO_XRCE_DDS_AGENT_TAG=v2.4.3
# hadolint ignore=DL3003
RUN if [ "${ENABLE_PX4}" = "on" ]; then \
      git clone https://github.com/PX4/px4_msgs.git ${OVERLAY_WS}/src/px4_msgs \
        && git -C ${OVERLAY_WS}/src/px4_msgs checkout ${PX4_MSGS_COMMIT} \
      && git clone https://github.com/PX4/px4_ros_com.git ${OVERLAY_WS}/src/px4_ros_com \
        && git -C ${OVERLAY_WS}/src/px4_ros_com checkout ${PX4_ROS_COM_COMMIT} \
      && git clone --branch ${MICRO_XRCE_DDS_AGENT_TAG} --depth 1 \
        https://github.com/eProsima/Micro-XRCE-DDS-Agent.git /tmp/micro-xrce-dds-agent \
      && cd /tmp/micro-xrce-dds-agent && mkdir build && cd build \
      && cmake .. -DCMAKE_BUILD_TYPE=Release && make -j"$(nproc)" && make install && ldconfig \
      && rm -rf /tmp/micro-xrce-dds-agent ; \
    fi

# --- Layer: Gazebo (Fortress via ros_gz, paired with Humble) --------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      ros-humble-ros-gz \
    && rm -rf /var/lib/apt/lists/*

# --- Layer: resolve remaining overlay deps via rosdep from package.xml ----
# No -r: an unresolvable or uninstallable key must fail here, not surface
# later as a confusing CMake error (or not at all).
RUN apt-get update \
    && rosdep install --from-paths ${OVERLAY_WS}/src --ignore-src -y \
    && rm -rf /var/lib/apt/lists/*

# --- Layer: build the overlay workspace (VINS [+ PX4 bridge]) -------------
# WORKDIR matters here, not just --base-paths: colcon writes build/install/log
# to the current directory regardless of --base-paths (which only controls
# source *discovery*). Without this, colcon build silently wrote those
# directories to the image root (/build, /install, /log) instead of under
# ${OVERLAY_WS}, leaving /opt/overlay_ws/install/setup.bash missing and
# VINS-Fusion unusable despite colcon reporting a clean build.
WORKDIR ${OVERLAY_WS}
RUN source /opt/ros/${ROS_DISTRO}/setup.bash \
    && colcon build --merge-install --cmake-args -DCMAKE_BUILD_TYPE=Release \
      --base-paths ${OVERLAY_WS} \
    && chown -R ${HOST_UID}:${HOST_GID} ${OVERLAY_WS}

# --- Layer: Python RL stack (own layer, own cache line) -------------------
# torch/torchvision go in FIRST, from the CUDA-matched (cu124) or CPU wheel
# index, and everything else is then resolved against them with
# requirements.txt itself as a constraints file (-c). The other order let pip
# satisfy stable-baselines3's unpinned `torch` requirement from PyPI's
# newest CUDA build, whose dependencies (~3.4 GB of nvidia-*/triton wheels,
# and setuptools 83) stayed behind after the pinned torch replaced it. That
# setuptools shadowed apt's 59.6 and broke `colcon build` of every
# ament_python package (setuptools<80 in requirements.txt now guards it).
# `pip check` fails the build on any conflict the resolver let through.
COPY deps/requirements.txt /tmp/requirements.txt
RUN if [ "${GPU}" = "on" ]; then TORCH_INDEX=cu124; else TORCH_INDEX=cpu; fi \
    && python3 -m pip install --no-cache-dir \
      --index-url "https://download.pytorch.org/whl/${TORCH_INDEX}" \
      -r <(grep -E '^(torch|torchvision)==' /tmp/requirements.txt) \
    && python3 -m pip install --no-cache-dir -c /tmp/requirements.txt \
      -r <(grep -vE '^(torch|torchvision)==' /tmp/requirements.txt) \
    && python3 -m pip check \
    && rm /tmp/requirements.txt

# --- Layer: VS Code Dev Containers support (.devcontainer/) ---------------
# Kept here, after the heavy layers, rather than in deps/apt-packages.txt so
# changing it never invalidates the Ceres/VINS/RL cache. gdb backs the C/C++
# extension's debugger. ~/.vscode-server is pre-created as `dev` because the
# devcontainer mounts a named volume there: a new volume copies the
# ownership of the image directory it shadows, and Docker would otherwise
# create it root-owned, so the VS Code server could not install.
RUN apt-get update && apt-get install -y --no-install-recommends gdb \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /home/dev/.vscode-server \
    && chown ${HOST_UID}:${HOST_GID} /home/dev/.vscode-server

# --- Layer: user workspace -- baked in only as a CI/first-run fallback; a
# real bind-mount of ./workspace (see docker-compose.yml) shadows this. -----
COPY workspace/src ${WORKSPACE_DIR}/src
RUN chown -R ${HOST_UID}:${HOST_GID} ${WORKSPACE_DIR}

# --- Entrypoint + ROS shell environment -------------------------------------
# common/ros-env.sh is the one place the ROS environment is defined (ROS2
# base -> ${OVERLAY_WS} -> ${WORKSPACE_DIR}, each via its setup.bash), and two
# things source it: the entrypoint, for PID 1 and `docker run`/`docker
# compose` commands, and /etc/bash.bashrc, for every interactive shell that
# bypasses the entrypoint (`docker exec -it <c> bash`, scripts/enter.sh, VS
# Code terminals). Before the bashrc hook those shells only inherited the
# image ENV -- ROS_DISTRO=humble, but no `ros2` on PATH and no ament_cmake
# for colcon to find (GitHub issue #1).
#
# Why /etc/bash.bashrc and not ~/.bashrc or /etc/profile.d:
#   - bash reads it for every interactive non-login shell of any user (dev,
#     `docker exec -u root`, an arbitrary `--user UID` with no home dir), and
#     interactive login shells reach it via /etc/profile, which covers the VS
#     Code server's userEnvProbe. Ubuntu's copy returns early for
#     non-interactive shells, so appending at the end leaves scripts and
#     `bash -c` untouched.
#   - ~/.bashrc is per-user (misses root and other UIDs) and is lost if the
#     home directory is bind-mounted or replaced by someone's dotfiles.
#   - /etc/profile.d is only read by login shells, and `docker exec ... bash`
#     is not one.
# A non-interactive `docker exec <c> ros2 ...` reads no rc file at all and
# can't be fixed from inside the image; run it as `docker exec <c>
# /entrypoint.sh ros2 ...` instead (see README).
#
# Deliberately the last layers, so editing these files never invalidates the
# heavy Ceres/overlay/PyTorch layers above.
COPY common/ros-env.sh /etc/ros2-docker/ros-env.sh
COPY common/ros-entrypoint.sh /entrypoint.sh
RUN chmod 0644 /etc/ros2-docker/ros-env.sh \
    && chmod 0755 /entrypoint.sh \
    && printf '%s\n' '' \
      '# ros2-docker: ROS env for interactive shells that bypass /entrypoint.sh' \
      '# (docker exec, VS Code terminals) -- see /etc/ros2-docker/ros-env.sh.' \
      'if [ -f /etc/ros2-docker/ros-env.sh ]; then . /etc/ros2-docker/ros-env.sh; fi' \
      >> /etc/bash.bashrc

USER dev
WORKDIR ${WORKSPACE_DIR}

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
