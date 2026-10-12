# ros2-docker :: `humble/drone`

[![CI](https://github.com/SwashBuckler104/ros2-docker/actions/workflows/ci.yml/badge.svg?branch=humble%2Fdrone)](https://github.com/SwashBuckler104/ros2-docker/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
![ROS2](https://img.shields.io/badge/ROS2-Humble-22314E)
![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04-E95420)

A self-contained Docker image for a ROS2 Humble drone stack, built around
**ArduPilot** — developed and tested against a **CubeOrangePlus running
ArduPilot Copter** — via **MAVROS**, with VINS-Fusion (visual-inertial
odometry), Gazebo (Fortress), and a GPU-ready RL stack (PyTorch / Gymnasium /
Stable-Baselines3) alongside it. PX4 is also supported as an opt-in addon.

Builds `FROM osrf/ros:humble-desktop` (CPU) or
`FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04` with ROS2 Humble layered
on top (GPU) — no dependency on any other branch or a GHCR base image. Runs
on any Linux host: CPU-only, integrated-GPU-only, or with a discrete NVIDIA
GPU.

## Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [Connecting a CubeOrangePlus](#connecting-a-cubeorangeplus-or-any-ardupilot-flight-controller)
- [GPU support](#gpu-support)
- [Configuration](#configuration)
- [PX4 (optional addon)](#px4-optional-addon)
- [Pinned sources](#pinned-sources)
- [Project layout](#project-layout)
- [Testing](#testing-against-a-sitl-manual-not-run-in-ci)
- [Contributing](#contributing)
- [License](#license)

## Features

- **ArduPilot-first**: MAVROS + ArduPilot's `apm.launch`/`apm_config.yaml`
  ship by default — built for a real CubeOrangePlus, not just simulation.
- **VINS-Fusion** visual-inertial odometry, built from source against a
  pinned, upstream-verified commit.
- **Gazebo (Fortress)** via `ros_gz`, and an optional **PX4** bridge
  (`px4_msgs`/`px4_ros_com` + Micro XRCE-DDS Agent) for teams that need both
  autopilots.
- **GPU-ready RL stack** (PyTorch, Gymnasium, Stable-Baselines3) with real
  CPU/GPU wheel selection — not just a CUDA base image with the wrong
  wheels installed.
- **Runs anywhere**: the same image and Compose files work unmodified on a
  headless CPU-only CI runner, a laptop with only an integrated GPU, or a
  workstation with an NVIDIA GPU — hardware-specific requirements are
  opt-in overlays, never hard requirements.
- **Non-root by default**, host UID/GID-mapped, with serial-device
  (`dialout`) access wired up automatically for flight-controller hardware.

## Prerequisites

- Docker Engine ([install guide](https://docs.docker.com/engine/install/))
- Docker Compose v2 (bundled with recent Docker Engine installs), if you
  prefer Compose over `scripts/*.sh`
- **Optional**, only for GPU acceleration of the RL stack: an NVIDIA GPU +
  driver, and the [NVIDIA Container
  Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
  — see [GPU support](#gpu-support)

## Quick start

```bash
./scripts/build.sh          # GPU/HOST_UID/HOST_GID auto-detected; CPU-safe on any PC
./scripts/run.sh
./scripts/enter.sh          # from a second terminal, if needed
```

Or via Compose (works on any PC as-is — CPU-only, integrated GPU, or a
discrete GPU you haven't wired up yet):

```bash
docker compose up --build
```

Neither path requires an NVIDIA GPU or the NVIDIA Container Toolkit — both
degrade to a CPU-only container automatically. See [GPU
support](#gpu-support) for what it takes to turn CUDA on.

## Connecting a CubeOrangePlus (or any ArduPilot flight controller)

MAVROS ships unconditionally in this image — `ros-humble-mavros` +
`ros-humble-mavros-extras`, with ArduPilot's launch/config files
(`apm.launch`, `apm_config.yaml`, `apm_pluginlists.yaml`) included. Plug the
Cube in via USB (or a telemetry radio), start the container, then:

```bash
./scripts/run.sh
# inside the container, once you know the device path (usually /dev/ttyACM0
# for a direct USB connection -- baud is ignored over USB-CDC):
ros2 launch mavros apm.launch fcu_url:=/dev/ttyACM0:57600
# or over a telemetry radio / serial adapter, baud matters:
ros2 launch mavros apm.launch fcu_url:=/dev/ttyUSB0:57600

# from another terminal (scripts/enter.sh), confirm MAVROS sees the FCU:
ros2 topic echo /mavros/state
```

`/dev:/dev` is bind-mounted into the container (`scripts/run.sh` and
`docker-compose.yml` both do this) so any `/dev/ttyACM*`/`/dev/ttyUSB*` the
host enumerates is visible inside. Visible isn't enough on its own: the
container's device cgroup blocks opening bind-mounted device nodes (EPERM,
even as root), so both also allow character-device majors 166
(`/dev/ttyACM*`) and 188 (`/dev/ttyUSB*`) via `--device-cgroup-rule` /
`device_cgroup_rules:`. This also covers boards plugged in after the
container started. Serial devices are normally owned
`root:dialout` on the host; both `scripts/run.sh` and `docker-compose.yml`
add the container to that gid automatically (`--group-add`/`group_add:`, gid
auto-detected via `getent group dialout`, override with the `DIALOUT_GID`
environment variable for Compose if your host's gid isn't 20) so the
non-root `dev` user can open them without extra steps.

> **PX4 addon**: if built with `ENABLE_PX4=on`, the equivalent commands are
> `ros2 launch mavros px4.launch fcu_url:="udp://:14540@127.0.0.1:14557"`
> (or the Micro XRCE-DDS Agent for the native PX4 ROS2 bridge) — see [PX4
> (optional addon)](#px4-optional-addon).

## GPU support

Two separate things determine whether this image actually gets GPU
acceleration, and it's easy to conflate them:

1. **Does your host have a working NVIDIA driver?** Check with
   `nvidia-smi`. This is independent of Docker entirely — if this works,
   your GPU is being used fine by anything you run directly on the host.
2. **Can Docker containers reach the GPU?** This needs the **NVIDIA
   Container Toolkit** installed on the host. Without it, containers are
   sandboxed away from the GPU device even if step 1 works — this is the
   actual gate for `--gpus all` / `GPU=on` in this repo. (`scripts/build.sh`
   and `scripts/run.sh` verify this with `nvidia-container-cli info`, not by
   checking `docker info` for a registered runtime — recent toolkit
   versions make `--gpus all` work without ever registering one there.)

To install the toolkit (Ubuntu/Debian; adjust for other distros — see
[NVIDIA's docs](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)):

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# verify:
docker run --rm --gpus all nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04 nvidia-smi
```

Once that's done:

```bash
./scripts/build.sh --gpu on && ./scripts/run.sh   # both auto-detect; explicit here for clarity
# or:
GPU=on docker compose -f docker-compose.yml -f docker-compose.gpu.yml up --build
```

`docker-compose.gpu.yml` is a separate overlay file, not a flag in the base
`docker-compose.yml` — Compose has no way to make a GPU device reservation
conditional, so requesting one unconditionally would make `docker compose
up` fail outright on any host without the toolkit. `scripts/run.sh` doesn't
have this problem: it detects both conditions above at runtime
(`detect_gpu()` in `scripts/lib/common.sh`) and only adds `--gpus all` when
both are actually true.

**What `GPU=on` actually accelerates**: the RL stack (PyTorch/Stable-
Baselines3 training), via `cu124` wheels instead of CPU wheels. It does
**not** accelerate VINS-Fusion's odometry pipeline — its Ceres Solver
backend builds without CUDA support in this image regardless of the GPU
flag, because the `nvidia/cuda:...-cudnn-runtime` base is a *runtime* image
(no `nvcc`/CUDA compiler), so Ceres's CMake auto-detection always disables
it. VINS-Fusion runs CPU/multi-threaded either way — turning GPU on won't
change its performance.

## Configuration

Build args (`docker build --build-arg ...`, or `scripts/build.sh` flags):

| ARG | Default | Effect |
|---|---|---|
| `GPU` | `off` | `on` selects the CUDA 12.4.1/cuDNN base + installs PyTorch's `cu124` wheels; `off` uses `osrf/ros:humble-desktop` + CPU-only PyTorch wheels (`download.pytorch.org/whl/cpu`, not PyPI's default CUDA-bundled Linux wheel) |
| `ENABLE_PX4` | `off` | *(PX4 addon)* `on` adds `px4_msgs`/`px4_ros_com` + the Micro XRCE-DDS Agent alongside MAVROS |
| `HOST_UID` / `HOST_GID` | `1000` / `1000` | mapped onto the in-container `dev` user so bind-mounted `workspace/` keeps host ownership. Named `HOST_*` rather than `UID`/`GID` deliberately: Docker exports every declared `ARG` as an env var for later `RUN` instructions, and a bare `UID`/`GID` env var silently shadows bash's readonly `$UID`/`$GID` builtins — which broke the MAVROS GeographicLib installer's root check when this was tried |

MAVROS ships unconditionally (it's the default, primary autopilot bridge for
this branch); PX4 is an additive addon, not a replacement, so both can be
present at once if `ENABLE_PX4=on`.

`scripts/build.sh` flags: `--gpu on|off`, `--px4`, `--tag TAG`. Compose
equivalents: `GPU`, `ENABLE_PX4`, `UID`, `GID` environment variables.

Without `--tag`, `build.sh` tags the image `ros2-docker:humble-drone-gpu` or
`-cpu` (matching whichever `GPU` value was used) so building one variant
doesn't overwrite the other on disk, then also re-points the generic
`ros2-docker:humble-drone` tag at it — that generic tag is what
`docker-compose.yml` and `scripts/run.sh` run, i.e. "whichever variant you
built most recently."

## PX4 (optional addon)

Not needed for ArduPilot/CubeOrangePlus users — skip this section entirely
unless you specifically want the native PX4 ROS2 bridge alongside MAVROS.

```bash
./scripts/build.sh --px4
./scripts/run.sh
# inside the container:
ros2 launch mavros px4.launch fcu_url:="udp://:14540@127.0.0.1:14557"
# from a PX4 SITL / QGroundControl instance on the host (or another
# container on the same host network), confirm MAVROS reports FCU connected:
ros2 topic echo /mavros/state
```

`ENABLE_PX4=on` additionally clones/builds `px4_msgs` (tag `v1.14.0`) and
`px4_ros_com` (`release/v1.14`) into the overlay workspace, and builds the
Micro XRCE-DDS Agent (tag `v2.4.3`) for the native PX4↔ROS2 DDS bridge — see
[Pinned sources](#pinned-sources) for exact commits.

## Pinned sources

Verified against upstream before pinning:

| Component | Source | Ref |
|---|---|---|
| VINS-Fusion | [fanhong-li/VINS-Fusion-ROS2-Humble](https://github.com/fanhong-li/VINS-Fusion-ROS2-Humble) | commit `8993f55` — explicitly targets Humble/Ubuntu 22.04, OpenCV4, Ceres 2.1.0, Eigen 3.3.9 |
| Ceres Solver | [ceres-solver/ceres-solver](https://github.com/ceres-solver/ceres-solver) | tag `2.1.0` (commit `f68321e`), built from source |
| px4_msgs *(PX4 addon)* | [PX4/px4_msgs](https://github.com/PX4/px4_msgs) | tag `v1.14.0` (commit `ffb6e80`) — only cloned when `ENABLE_PX4=on` |
| px4_ros_com *(PX4 addon)* | [PX4/px4_ros_com](https://github.com/PX4/px4_ros_com) | `release/v1.14` (commit `e18248d`) — pairs with the px4_msgs tag above |
| Micro XRCE-DDS Agent *(PX4 addon)* | [eProsima/Micro-XRCE-DDS-Agent](https://github.com/eProsima/Micro-XRCE-DDS-Agent) | tag `v2.4.3` — only built when `ENABLE_PX4=on` |
| PyTorch / torchvision | PyPI / `download.pytorch.org` | `2.5.1` / `0.20.1`; CPU wheels by default, `cu124` wheels when `GPU=on` |

Base images are pinned by digest in the `Dockerfile` (`osrf/ros:humble-desktop`
and `nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04`).

## Project layout

```
Dockerfile               multi-stage: base-off / base-on (GPU) -> base -> image
docker-compose.yml        hardware-agnostic base: X11, /dev, dialout group, workspace bind-mount
docker-compose.gpu.yml    optional overlay: /dev/dri + NVIDIA GPU reservation (needs the toolkit)
entrypoint.sh             sources ROS2 -> overlay ws (/opt/overlay_ws) -> user ws
LICENSE                   Apache-2.0
deps/
  apt-packages.txt        system + Ceres build deps
  rosdep.yaml              custom rosdep keys (empty -- none needed yet)
  requirements.txt         pinned RL/Python deps
scripts/
  build.sh                builds the image (GPU/HOST_UID/HOST_GID auto-detected)
  run.sh                   runs it with the right GPU/X11/device/dialout-group flags
  enter.sh                 execs a shell into the running container
workspace/src/            your colcon workspace (bind-mounted at runtime);
                          ships with `minimal_pkg`, a trivial ament_cmake
                          package CI and scripts/build.sh use as a smoke test
```

`/opt/overlay_ws` (inside the image) holds the prebuilt VINS-Fusion [+ PX4
bridge] packages, built at image-build time with `colcon build
--merge-install`. `workspace/` is yours — bind-mounted over whatever was
baked in at build time.

## Testing against a SITL (manual, not run in CI)

CI's smoke test only checks that MAVROS/VINS packages are importable and
that a minimal package colcon-builds — it does not spin up a simulator or
require real flight-controller hardware. For ArduPilot SITL or a real
CubeOrangePlus, see [Connecting a
CubeOrangePlus](#connecting-a-cubeorangeplus-or-any-ardupilot-flight-controller);
for PX4 SITL, see [PX4 (optional addon)](#px4-optional-addon).

For VINS-Fusion, run `ros2 run vins vins_node <path-to-a-vins-config.yaml>`
against a recorded rosbag or live camera/IMU topics; a working config for
your camera is required (VINS ships sample configs under
`/opt/overlay_ws/src/VINS-Fusion-ROS2-Humble/config`).

For the RL stack, a trivial GPU smoke test (expect `False` unless you built
with `GPU=on` on a host with the NVIDIA Container Toolkit installed — see
[GPU support](#gpu-support)):

```bash
python3 -c "import torch; print(torch.cuda.is_available(), torch.rand(3))"
```

## Contributing

This repo uses [Conventional Commits](https://www.conventionalcommits.org/)
(`feat:`, `fix:`, `build:`, `ci:`, `docs:`, ...). Before opening a PR:

- Run `./scripts/build.sh` locally and confirm it builds clean.
- If you touch `common/create-user.sh` or anything else shared with `main`,
  re-sync the change into the other branches (`humble/ground`,
  `jazzy/ground`) per the comments in those files.
- CI (`.github/workflows/ci.yml`) builds with `GPU=off`/`ENABLE_PX4=off` and
  runs the smoke test described in [Testing](#testing-against-a-sitl-manual-not-run-in-ci)
  above; it does not cover the GPU or PX4 build paths, so please test those
  manually if you change them.

## License

[Apache License 2.0](LICENSE).
