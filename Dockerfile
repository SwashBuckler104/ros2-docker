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
RUN chmod +x /tmp/create-user.sh \
    && env DEV_USER=dev UID=${HOST_UID} GID=${HOST_GID} /tmp/create-user.sh \
    && rm /tmp/create-user.sh \
    && mkdir -p ${WORKSPACE_DIR}/src ${OVERLAY_WS}/src \
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
RUN apt-get update \
    && rosdep install --from-paths ${OVERLAY_WS}/src --ignore-src -r -y \
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
COPY deps/requirements.txt /tmp/requirements.txt
RUN python3 -m pip install --no-cache-dir -r <(grep -vE '^(torch|torchvision)==' /tmp/requirements.txt) \
    && if [ "${GPU}" = "on" ]; then \
      python3 -m pip install --no-cache-dir torch==2.5.1 torchvision==0.20.1 \
        --index-url https://download.pytorch.org/whl/cu124 ; \
    else \
      python3 -m pip install --no-cache-dir torch==2.5.1 torchvision==0.20.1 \
        --index-url https://download.pytorch.org/whl/cpu ; \
    fi \
    && rm /tmp/requirements.txt

# --- Layer: user workspace -- baked in only as a CI/first-run fallback; a
# real bind-mount of ./workspace (see docker-compose.yml) shadows this. -----
COPY workspace/src ${WORKSPACE_DIR}/src
RUN chown -R ${HOST_UID}:${HOST_GID} ${WORKSPACE_DIR}

# --- Entrypoint / X11 -------------------------------------------------------
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER dev
WORKDIR ${WORKSPACE_DIR}

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
