#!/usr/bin/env bash

#install
sudo apt update 
sudo apt install -y containerd

# configure
sudo mkdir -p /etc/containerd/
containerd config default | \
    sed 's#SystemdCgroup\s*=\s*false#SystemdCgroup = true#g' | \
    sudo tee /etc/containerd/config.toml >/dev/null

sudo systemctl restart containerd
