#!/usr/bin/env bash

sudo kubeadm init --ignore-preflight-errors=NumCPU \
    --pod-network-cidr=10.244.0.0/16 \
    --apiserver-cert-extra-sans={{my_ip}} \
    --kubernetes-version=1.26.7
