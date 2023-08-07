#!/usr/bin/env bash

mkdir -p /home/dcheld/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/dcheld/.kube/config
sudo chown '1000:1000' /home/dcheld/.kube/config
