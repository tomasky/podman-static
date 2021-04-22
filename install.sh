#!/usr/bin/env bash

curl -fsSL -o podman-linux-amd64.tar.gz https://download.fastgit.org/tomasky/podman-static/releases/latest/download/podman-linux-amd64.tar.gz
tar -xzf podman-linux-amd64.tar.gz
sudo cp -r podman-linux-amd64/usr podman-linux-amd64/etc /


sudo sh -c "echo $(id -un):100000:200000 >> /etc/subuid"
sudo sh -c "echo $(id -gn):100000:200000 >> /etc/subgid"
