#!/usr/bin/env bash

set -euo pipefail

if [[ -z "${PODMAN_HOME:-}" && -n "${PODMAN_DIR:-}" ]]; then
    PODMAN_HOME=$PODMAN_DIR
fi
PODMAN_HOME=${PODMAN_HOME:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}
export PODMAN_HOME

abort() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

confirm() {
    local answer
    read -r -p "$1 [y/N] " answer || return 1
    [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

if [[ "$(id -u)" -eq 0 ]]; then
    SUDO=()
else
    command -v sudo >/dev/null 2>&1 || abort 'sudo is required to configure rootless UID/GID mappings'
    SUDO=(sudo)
fi

missing=()
command -v unshare >/dev/null 2>&1 || missing+=(util-linux)
command -v newuidmap >/dev/null 2>&1 || missing+=(uidmap)
command -v newgidmap >/dev/null 2>&1 || missing+=(uidmap)
if ((${#missing[@]})); then
    mapfile -t missing < <(printf '%s\n' "${missing[@]}" | sort -u)
    command -v apt-get >/dev/null 2>&1 || abort \
        "missing ${missing[*]}; this script only supports apt-get installation"
    confirm "Missing ${missing[*]}. Run sudo apt-get install -y ${missing[*]}?" || \
        abort 'rootless prerequisites were not installed'
    "${SUDO[@]}" apt-get install -y "${missing[@]}" || \
        abort 'apt-get failed while installing rootless prerequisites'
fi

for command_name in unshare newuidmap newgidmap; do
    command -v "$command_name" >/dev/null 2>&1 || abort \
        "required command is still missing after installation: $command_name"
done

user_name=$(id -un)
group_name=$(id -gn)
if ! grep -Fqx "$user_name:100000:65536" /etc/subuid 2>/dev/null; then
    confirm "Add $user_name:100000:65536 to /etc/subuid with sudo?" || \
        abort 'required user mapping was not added to /etc/subuid'
    "${SUDO[@]}" sh -c "echo $user_name:100000:65536 >> /etc/subuid" || \
        abort 'failed to update /etc/subuid'
fi
if ! grep -Fqx "$group_name:100000:65536" /etc/subgid 2>/dev/null; then
    confirm "Add $group_name:100000:65536 to /etc/subgid with sudo?" || \
        abort 'required group mapping was not added to /etc/subgid'
    "${SUDO[@]}" sh -c "echo $group_name:100000:65536 >> /etc/subgid" || \
        abort 'failed to update /etc/subgid'
fi

source "$PODMAN_HOME/podman-env.bash"
exec "${SHELL:-/bin/bash}" -l
