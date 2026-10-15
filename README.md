# podman-static

Alpine-based Podman images and statically linked Podman binaries for Linux
amd64 and arm64. The dependency set follows the current upstream
`mgoltzsche/podman-static` build and uses Podman 6's Netavark/pasta networking
stack.

## Bundled dependency versions

| Component | Version |
| --- | --- |
| Podman | v6.1.4 |
| Go / Alpine | 1.27 / 3.24 |
| Rust | 1.98 |
| runc | v1.5.2 |
| conmon | v2.2.1 |
| crun | 1.30.1 |
| Netavark / aardvark-dns | v2.1.0 |
| pasta | 2026_10_02.cba3570 |
| libfuse / fuse-overlayfs | fuse-3.18.3 / v1.18 |
| catatonit | v0.2.1 |

Podman 6 no longer uses the old CNI/slirp4netns bundle here. The old i386
`Dockerfilex86` entry is intentionally fail-fast; build `Dockerfile` with
`PLATFORM=linux/amd64` or `PLATFORM=linux/arm64` instead.

## Container image

The image tags are:

| Tag | Description |
| --- | --- |
| `latest`, `<VERSION>` | Podman with rootful and rootless dependencies, including runc, crun, conmon, fuse-overlayfs, Netavark, pasta and aardvark-dns. |
| `minimal`, `<VERSION>-minimal` | Podman, crun, fuse-overlayfs and conmon, configured for host namespaces and disabled cgroups. |
| `remote`, `<VERSION>-remote` | The statically linked Podman remote client. |

Run Podman in a container:

```sh
docker run --privileged -u podman:podman \
  mgoltzsche/podman:minimal docker run alpine:3.24 echo hello
```

Non-remote Podman inside a container requires `--privileged`.

## Private host installation

The archive contains all bundled executables and configuration files. Install
it below a private root instead of copying files into `/usr` or `/etc`:

```sh
make tar
make install INSTALL_ROOT="$HOME/.local/podman"
```

The `pym3/bin/pods` wrapper can perform the same installation and generates an
environment file. Set `PODMAN_HOME` before running it to use another root:

```sh
PODMAN_HOME="$HOME/.local/podman" pods setup rootless
source "$PODMAN_HOME/env.bash"
podman run alpine:3.24 echo hello
```

The private root contains binaries, configs, image/container storage, runtime
state, temporary files and registry authentication data. Podman configuration
is selected with the documented `CONTAINERS_CONF`,
`CONTAINERS_STORAGE_CONF`, `CONTAINERS_REGISTRIES_CONF`, `XDG_DATA_HOME`,
`XDG_RUNTIME_DIR` and `TMPDIR` variables.

Rootless setup checks for `unshare`, `newuidmap` and `newgidmap`. If a required
tool is absent, Bash asks before running `sudo apt-get install -y util-linux
uidmap`. It separately asks before appending the requested `100000:65536`
entries to `/etc/subuid` and `/etc/subgid`; refusal or a failed verification
stops setup.

## System-wide installation (not recommended for private deployments)

For a conventional system installation, inspect the archive first:

```sh
tar -xzf build/podman-linux-amd64.tar.gz
sudo cp -r podman-linux-amd64/usr podman-linux-amd64/etc /
```

## Local build and test

```sh
make images
make test
```

Use `PLATFORM=linux/arm64` for an arm64 bundle. Docker Buildx is required for
the build targets.
