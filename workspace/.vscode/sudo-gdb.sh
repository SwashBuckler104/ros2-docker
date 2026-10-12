#!/usr/bin/env bash
# gdb as root, for the "attach to running node" launch config only. Ubuntu
# hosts default to Yama ptrace_scope=1, which (being host-wide, not
# namespaced) also applies inside the container: a process may only ptrace
# its own descendants unless it holds CAP_SYS_PTRACE in its *effective* set.
# The dev container adds SYS_PTRACE to the container's bounding set, but the
# non-root `dev` user never has it effective, so plain gdb fails with "Could
# not attach to process". Root in the dev container does have it, and `dev`
# has passwordless sudo. Containers started without SYS_PTRACE (scripts/run.sh,
# plain compose) can't attach at all, even as root.
#
# -n: fail instead of hanging on a password prompt VS Code can't show.
exec sudo -n /usr/bin/gdb "$@"
