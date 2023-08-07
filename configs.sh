#!/usr/bin/env bash

RESOURCE_GROUP_NAME='kubernetes'
VM_WORK_NAME='k8s'
VM_MASTER_NAME="${VM_WORK_NAME}-server"
VM_USERNAME="${USER:-dcheld}"
NSG_NAME="${VM_WORK_NAME}NSGTest"
VNET_NAME="k8sVNETTest"
SUBNET_NAME="k8sSubnetTest"
VM_RANCHER='master'
VM_SIZE='Standard_B1ms'
LOCATION='eastus'
VM_COUNT=0