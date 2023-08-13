#!/usr/bin/env bash

mkdir -p /home/{{user}}/.kube
sudo cp /etc/kubernetes/admin.conf /home/{{user}}/.kube/config
sudo chown {{user}}:{{user}} -R /home/{{user}}/.kube
