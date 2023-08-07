#!/usr/bin/env bash

sudo kubeadm init --ignore-preflight-errors=NumCPU --pod-network-cidr=10.244.0.0/16
