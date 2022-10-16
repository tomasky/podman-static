#!/usr/bin/env bash

command -v sudo > /dev/null && sudo=sudo
$sudo apt install -y procps uidmap dnsmasq &>/dev/null
$sudo yum install -y procps shadow-utils dnsmasq &>/dev/null

$sudo sysctl -w "net.ipv4.ping_group_range=0 65536" 
uname=$(id -un)
gname=$(id -gn)
HOME=$HOME
if [[ "$uname" = "root" ]]; then
  HOME="/home/podman"
  useradd --create-home --shell /bin/bash -d $HOME -u 1001 -m podman
  chown -R podman:podman $HOME 
  uname=podman
  gname=podman
fi

if ! grep -q "$uname:100000:65536" /etc/subuid; then
  $sudo sh -c "echo $uname:100000:65536 >> /etc/subuid"
  $sudo sh -c "echo $gname:100000:65536 >> /etc/subgid"
fi

su $uname -c '
mkdir -p $HOME/.local/
mkdir -p $HOME/.local/podman && cp -r * $HOME/.local/podman

mkdir -p $HOME/.config && cp -r $HOME/.local/podman/etc/containers $HOME/.config/
cd $HOME/.config/containers
rm storage.conf && mv crun-containers.conf containers.conf
sed -i "s|\$HOME|$HOME|g" containers.conf

if test -f $HOME/.bashrc && ! grep -q "export PATH=\"\$HOME/.local/podman" $HOME/.bashrc; then
  echo -e "\nexport PATH=\"\$HOME/.local/podman/usr/local/bin:\$PATH\"" >> $HOME/.bashrc
fi
'

if [[ "$uname" != "root" ]]; then
  su $uname
fi
