#!/usr/bin/env bash
# Canonical non-root dev-user creation stanza, shared across every branch.
# Copied verbatim into each branch's Dockerfile build context and invoked
# with `ARG UID`/`ARG GID` (default 1000) so bind-mounted workspaces keep
# host file ownership. If you edit this file on main, re-copy it into
# humble/drone, humble/ground, and jazzy/ground.
set -euo pipefail

USERNAME="${DEV_USER:-dev}"
USER_UID="${UID:-1000}"
USER_GID="${GID:-1000}"

if ! getent group "${USER_GID}" >/dev/null; then
  groupadd --gid "${USER_GID}" "${USERNAME}"
else
  groupmod -n "${USERNAME}" "$(getent group "${USER_GID}" | cut -d: -f1)"
fi

if ! getent passwd "${USER_UID}" >/dev/null; then
  useradd --uid "${USER_UID}" --gid "${USER_GID}" -m -s /bin/bash "${USERNAME}"
else
  usermod -l "${USERNAME}" -d "/home/${USERNAME}" -m "$(getent passwd "${USER_UID}" | cut -d: -f1)"
fi

echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}"
chmod 0440 "/etc/sudoers.d/${USERNAME}"
