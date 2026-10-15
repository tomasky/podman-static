#!/usr/bin/env bash

# Source this file to run the bundled Podman without modifying /usr or /etc.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'Error: source %s from Bash; do not execute it directly.\n' "$0" >&2
    exit 1
fi

podman_static_init() {
    local script_root config_root data_root runtime_root tmp_root

    if [[ -z "${PODMAN_HOME:-}" && -n "${PODMAN_DIR:-}" ]]; then
        PODMAN_HOME=$PODMAN_DIR
    fi
    PODMAN_HOME=${PODMAN_HOME:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}
    if [[ "$PODMAN_HOME" != /* ]]; then
        mkdir -p -- "$PODMAN_HOME" || return 1
        PODMAN_HOME=$(cd -- "$PODMAN_HOME" && pwd -P) || return 1
    fi
    export PODMAN_HOME

    config_root=${PODMAN_CONFIG_HOME:-$PODMAN_HOME/config}
    data_root=${PODMAN_DATA_HOME:-$PODMAN_HOME/data}
    runtime_root=${PODMAN_RUNTIME_DIR:-$PODMAN_HOME/run}
    tmp_root=${PODMAN_TMPDIR:-$PODMAN_HOME/tmp}
    export PODMAN_CONFIG_HOME=$config_root
    export PODMAN_DATA_HOME=$data_root
    export PODMAN_RUNTIME_DIR=$runtime_root
    export PODMAN_TMPDIR=$tmp_root

    script_root=$PODMAN_HOME/usr/local
    for required in \
        "$script_root/bin/podman" \
        "$script_root/bin/crun" \
        "$script_root/bin/fuse-overlayfs" \
        "$script_root/lib/podman/conmon" \
        "$script_root/lib/podman/netavark" \
        "$script_root/lib/podman/aardvark-dns" \
        "$script_root/bin/pasta"; do
        if [[ ! -x "$required" ]]; then
            printf 'Error: required bundled executable is missing: %s\n' "$required" >&2
            return 1
        fi
    done

    mkdir -p -- "$config_root/containers" "$data_root" "$runtime_root" "$tmp_root" \
        "$PODMAN_HOME/bin" || return 1
    chmod 700 -- "$runtime_root" || return 1

    if [[ ! -f "$config_root/containers/policy.json" ]]; then
        cp -- "$PODMAN_HOME/etc/containers/policy.json" "$config_root/containers/policy.json" || return 1
    fi

    local config_file=$config_root/containers/containers.conf
    if [[ ! -f "$config_file" ]]; then
        printf '%s\n' \
            '# Generated for this private Podman root.' \
            '[engine]' \
            'cgroup_manager = "cgroupfs"' \
            'events_logger = "file"' \
            'runtime = "crun"' \
            "conmon_path = [\"$script_root/lib/podman/conmon\"]" \
            "helper_binaries_dir = [\"$script_root/lib/podman\", \"$script_root/libexec/podman\"]" \
            '[containers]' \
            "init_path = \"$script_root/lib/podman/catatonit\"" \
            '[network]' \
            'network_backend = "netavark"' > "$config_file" || return 1
    fi

    local storage_file=$config_root/containers/storage.conf
    if [[ ! -f "$storage_file" ]]; then
        printf '%s\n' \
            '# Generated for this private Podman root.' \
            '[storage]' \
            'driver = "overlay"' \
            "runroot = \"$runtime_root/containers/storage\"" \
            "graphroot = \"$data_root/containers/storage\"" \
            '[storage.options.overlay]' \
            "mount_program = \"$script_root/bin/fuse-overlayfs\"" \
            'ignore_chown_errors = "true"' > "$storage_file" || return 1
    fi

    [[ -e "$PODMAN_HOME/bin/docker" ]] || \
        ln -s "$script_root/bin/podman" "$PODMAN_HOME/bin/docker" || return 1
    export PATH="$PODMAN_HOME/bin:$PODMAN_HOME/node/bin:$script_root/bin:$PATH"
    export XDG_CONFIG_HOME=$config_root
    export XDG_DATA_HOME=$data_root
    export XDG_RUNTIME_DIR=$runtime_root
    export TMPDIR=$tmp_root
    export CONTAINERS_CONF=$config_file
    export CONTAINERS_STORAGE_CONF=$storage_file
    export CONTAINERS_REGISTRIES_CONF="$PODMAN_HOME/etc/containers/registries.conf"
    export REGISTRY_AUTH_FILE="$data_root/auth.json"
    export PODMAN_CONNECTIONS_CONF="$data_root/podman-connections.json"
}

podman_static_init || return $?
unset -f podman_static_init
