#!/usr/bin/env bash

sudo kubeadm join {{vm_master_name}}:6443 --token {{token}} --discovery-token-ca-cert-hash sha256:{{ca_cert_hash}}