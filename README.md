# ros2-docker

Specialized, GPU-capable Docker images for ROS2 robot applications. Each image
is reproducible and buildable with a single command.

## Branch model

This repo has **no long-lived branch that builds an application image** —
`main` carries shared tooling only. Application images live on their own
self-contained branches:

| Branch | Base OS | ROS2 | Purpose |
|---|---|---|---|
| [`humble/drone`](../../tree/humble/drone) | Ubuntu 22.04 | Humble | Drone stack: VINS-Fusion + MAVROS/PX4 + RL + Gazebo |
| [`humble/ground`](../../tree/humble/ground) | Ubuntu 22.04 | Humble | Mobile robot / arm / combined platform: Nav2 + SLAM Toolbox + MoveIt2 + Gazebo |
| [`jazzy/ground`](../../tree/jazzy/ground) | Ubuntu 24.04 | Jazzy | Same ground-robot stack, on Jazzy |

Each branch builds `FROM osrf/ros:<distro>-desktop` or the matching
`nvidia/cuda:...-ubuntu<ver>` image (GPU toggled via build ARG). **No branch
builds `FROM` another branch's image** — check out the branch you need and
build it standalone:

```bash
git clone --branch humble/drone --single-branch <this-repo-url>
cd ros2-docker
./scripts/build.sh --gpu on --tag ros2-docker:humble-drone
./scripts/run.sh --tag ros2-docker:humble-drone
```

See each branch's own `README.md` for stack-specific build args, deps, and
run instructions.

### Why only three branches

Composable ground applications (mobile base + arm + SLAM) don't get their own
branch — a combined arm-on-mobile platform just uses `humble/ground`, which
already ships both Nav2 and MoveIt2. Adding a new ground capability means
adding packages to that branch's `deps/`, not creating a new branch. Drones
are split out because the flight stack (VINS, MAVROS/PX4) and the RL stack
are fundamentally different and heavier than the ground-robot toolset.

## What lives on `main`

`main` holds only tooling shared across every branch, merged **down** into
each one when it changes:

- `common/` — the canonical non-root-user-creation and ROS entrypoint
  stanzas. Each branch copies these in verbatim and pins them; if you change
  them here, re-sync into every branch.
- `scripts/lib/common.sh` — shell helpers (`build.sh`/`run.sh`/`enter.sh` on
  every branch source this).
- `.github/workflows/_reusable-image-ci.yml` — the reusable CI job
  (hadolint → build → smoke test) every branch's own workflow calls.
- `.devcontainer/` — VS Code devcontainer config for whichever branch is
  checked out.
- `LICENSE`, `.dockerignore`, this file.

No application `Dockerfile` lives on `main`.

## Reference

Build conventions (distro parametrization, GPU toggle via `nvidia/cuda` +
NVIDIA runtime, non-root UID/GID-mapped user, toggleable tool layers) are
adapted from [ppswaroopa/ros2-dockergen](https://github.com/ppswaroopa/ros2-dockergen)
and the official [docs.ros.org](https://docs.ros.org) / [`osrf/ros`](https://hub.docker.com/r/osrf/ros)
images.

## Conventional commits

This repo uses conventional commits (`feat:`, `fix:`, `build:`, `ci:`,
`docs:`). PRs should state their target branch and update that branch's
README.
