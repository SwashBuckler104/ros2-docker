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
- [VS Code](#vs-code)
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

## VS Code

VS Code runs **on the host** and talks to a VS Code Server **inside the
container** through the [Dev
Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
extension. Do not install VS Code (the `code` apt package) inside the
container: it is a GUI app, and even when it starts it is a second,
separate VS Code that has none of your extensions or settings.

**Host prerequisites** (once per machine):

- Docker Engine with Compose v2 **2.24 or newer** (`docker compose
  version`). Use Docker Engine (`docker-ce`), not Docker Desktop or the
  `docker` snap: they run containers inside a VM or sandbox, which breaks
  the `/dev` passthrough, the X11 socket mount and (depending on version)
  host networking that this repo relies on.
- Your user in the `docker` group, so VS Code can run `docker` without
  sudo: `sudo usermod -aG docker $USER`, then log out and back in. Check
  with `docker ps`.
- [VS Code](https://code.visualstudio.com/) (snap, `.deb` or tarball) and
  the Dev Containers extension (`ms-vscode-remote.remote-containers`).

### Open the repo in a container (recommended)

```bash
git clone https://github.com/SwashBuckler104/ros2-docker.git -b humble/drone
code ros2-docker
```

Then **Dev Containers: Reopen in Container** (VS Code also offers it in a
notification) and pick **ros2-docker humble/drone (CPU)**, or **(NVIDIA
GPU)** if `nvidia-smi` and the [NVIDIA Container
Toolkit](#gpu-support) work on your host. Behind the scenes:

- `.devcontainer/initialize.sh` runs on the host: it writes your UID/GID
  and the host's `dialout` gid to a gitignored `.env`, runs `xhost
  +local:docker` for X11, and, if `ros2-docker:humble-drone` doesn't exist
  yet, builds it with `scripts/build.sh` (one-time, long). No second image
  is built: the dev container reuses the `drone` service from
  `docker-compose.yml`, so it has the same image and runtime flags (host
  network/IPC, X11, `/dev`, `dialout`) as `docker compose up` and
  `scripts/run.sh`.
- The container is `ros2-docker-humble-drone-devcontainer` (or `...-gpu`),
  separate from the `scripts/run.sh` / Compose one, so both can run at
  once. Closing VS Code stops it; reopening restarts it.
- VS Code opens `/home/dev/ws` (your `./workspace`) as user `dev`, installs
  the recommended extensions (C/C++, Python + Pylance, [ROS 2
  tools](https://marketplace.visualstudio.com/items?itemName=ranch-hand-robotics.rde-ros-2),
  XML, YAML) and runs `rosdep update`. The VS Code Server and extensions
  are kept in the `ros2-docker-vscode-server` volume, so a rebuild doesn't
  download them again.

Inside the container window:

- **Terminal > New Terminal** gives a bash shell with ROS 2, the
  `/opt/overlay_ws` overlay and `~/ws/install` already sourced. `code
  <file>` / `code .` work there and open in the same VS Code.
- **Ctrl+Shift+B** runs the `colcon: build` task (`--symlink-install`,
  `RelWithDebInfo`, `compile_commands.json`). Run it once after opening:
  C/C++ IntelliSense reads `build/compile_commands.json`. Other tasks:
  `colcon: test`, `rosdep: install workspace dependencies`, `colcon: clean`.
- **Run and Debug** has `C++: launch ROS 2 node (gdb)` (prompts for
  package and executable), `C++: attach to running node (gdb)`, and
  `Python: current file`.
- The settings live in `workspace/.vscode/` and use container paths only.
  Packages under `src/` that are their own git repos show up in Source
  Control. This repo itself (Dockerfile, scripts) isn't mounted in the
  container, so commit changes to it from the host.

The image and the container are separate: after `./scripts/build.sh`,
run **Dev Containers: Rebuild Container** to switch to the new image. It
only recreates the container and never rebuilds the image. Don't add
`features` to `devcontainer.json`, since they would build a second image.

### Attach to a container you already started

If you started the container with `./scripts/run.sh` or `docker compose
up`, run **Dev Containers: Attach to Running Container...**, pick
`ros2-docker-humble-drone`, then **File > Open Folder** `/home/dev/ws`.
`workspace/.vscode/` gives you the same settings, tasks and launch
configs, and VS Code suggests the extensions from `extensions.json`. To
make VS Code reopen that folder and install the extensions on its own,
run **Dev Containers: Open Named Container Configuration File...** on
`ros2-docker-humble-drone` and add:

```json
{
  "workspaceFolder": "/home/dev/ws",
  "remoteUser": "dev",
  "extensions": ["ms-vscode.cpptools", "ms-python.python", "ms-python.vscode-pylance",
                 "ranch-hand-robotics.rde-ros-2", "redhat.vscode-xml", "redhat.vscode-yaml"]
}
```

Limits of attaching: `scripts/run.sh` uses `--rm`, so the VS Code Server
is downloaded again for every new container. gdb can also launch nodes
but not attach to running ones, because those containers don't get
`SYS_PTRACE`.

**`code .` from `scripts/enter.sh` / `docker exec` doesn't work, by
design.** `code` inside the container is a small client that VS Code puts
on the `PATH` of its own integrated terminals and connects to the window
that owns them through `VSCODE_IPC_HOOK_CLI`. A plain `docker exec` shell
has neither, so open files from a VS Code terminal or with **File > Open**
instead.

### Troubleshooting

- **"Cannot reach the Docker daemon"** from `initialize.sh`: Docker isn't
  running, or you haven't logged out and back in since joining the
  `docker` group.
- **"predates VS Code Dev Containers support"**: your image is older than
  this setup and has no `~/.vscode-server` directory or `gdb`. Run
  `./scripts/build.sh`, then reopen.
- **`!reset` / "unknown tag" error**: your Docker Compose is older than
  2.24. Upgrade `docker-compose-plugin`.
- **GUI apps (rviz2, Gazebo) can't open a display**: check that
  `echo $DISPLAY` inside the container isn't empty. VS Code passes along the
  `DISPLAY` it was started with, so start VS Code from your desktop session,
  not from a bare SSH shell. `initialize.sh` runs `xhost +local:docker`
  every time the container is opened; if it warns that `xhost` is missing,
  install `x11-xserver-utils` on the host.
- **Files in `workspace/` owned by the wrong user**: images built by
  `scripts/build.sh` already use your UID. If yours wasn't, Dev Containers
  maps `dev` to your UID on its own, in the thin `vsc-...-uid` image it
  always layers on top. For Compose, `.env` now holds the right
  `UID`/`GID`.
- **Start over**: **Dev Containers: Rebuild Container**, or remove
  everything VS Code-specific with `docker rm -f
  ros2-docker-humble-drone-devcontainer` and `docker volume rm
  ros2-docker-vscode-server`.

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
.devcontainer/
  devcontainer.json       VS Code dev container (CPU / any host), reuses the compose `drone` service
  gpu/devcontainer.json   same, plus docker-compose.gpu.yml
  docker-compose.devcontainer.yml  dev-container-only compose overrides (no build, vscode-server volume)
  initialize.sh           host-side prep: .env with UID/GID/DIALOUT_GID, xhost, build image if missing
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
workspace/.vscode/        in-container VS Code settings, tasks, debug configs
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
