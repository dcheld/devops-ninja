#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "$SCRIPT_DIR/configs.sh"

function __create-resource() {
    if [ $(az group exists -n $RESOURCE_GROUP_NAME) = true ]; then 
        return 0
    fi
    az group create \
        -g $RESOURCE_GROUP_NAME \
        -l $LOCATION
}

function __create-nsg(){
    az network nsg create \
        -g $RESOURCE_GROUP_NAME \
        -l $LOCATION \
        -n $NSG_NAME

    az network nsg rule create \
        -g $RESOURCE_GROUP_NAME \
        --nsg-name $NSG_NAME \
        --name AllowAnyHTTPSInbound \
        --priority 100 \
        --source-address-prefixes '*' \
        --destination-port-ranges 80 443 \
        --access Allow \
        --protocol Tcp

    az network nsg rule create \
        -g $RESOURCE_GROUP_NAME \
        --nsg-name $NSG_NAME \
        --name AllowAnySSHInbound \
        --priority 110 \
        --source-address-prefixes `curl ifconfig.me` \
        --destination-port-ranges 22 \
        --access Allow \
        --protocol Tcp
}

function __create-vnet() {
    az network vnet create \
        -g $RESOURCE_GROUP_NAME \
        -n $VNET_NAME
}

function __create-subnet() {
    az network vnet subnet create \
        -g $RESOURCE_GROUP_NAME \
        --vnet-name $VNET_NAME \
        --nsg $NSG_NAME \
        -n $SUBNET_NAME \
        --address-prefixes '10.0.0.0/24'
}

function __create-master-vms() {
    az vm create -g $RESOURCE_GROUP_NAME \
        -l $LOCATION \
        -n $VM_MASTER_NAME \
        --size "$VM_SIZE" \
        --nsg "" \
        --nsg-rule SSH \
        --vnet-name $VNET_NAME \
        --subnet $SUBNET_NAME \
        --image Ubuntu2204
}

function __create-work-vms() {
    az vm create -g $RESOURCE_GROUP_NAME \
        -l $LOCATION \
        -n $VM_WORK_NAME \
        --size "$VM_SIZE" \
        --count $VM_COUNT \
        --nsg "" \
        --vnet-name $VNET_NAME \
        --subnet $SUBNET_NAME \
        --image Ubuntu2204

}

function __get-vm-names () {
    for i in $(seq 0 $(expr $VM_COUNT - 1));
    do
        echo "${VM_WORK_NAME}${i}"
    done
    echo "${VM_MASTER_NAME}"
}

function _create() {
    __create-resource
    __create-nsg
    __create-vnet
    __create-subnet

    __create-master-vms &
    __create-work-vms &
    wait
}

function _delete() {
    az group delete \
        -n $RESOURCE_GROUP_NAME \
        --force-deletion-types Microsoft.Compute/virtualMachines \
        --force-deletion-types Microsoft.Compute/virtualMachineScaleSets \
        --yes
}

function _deallocate-vms() {
    for name in $(__get-vm-names);
    do
        az vm deallocate -g $RESOURCE_GROUP_NAME -n "${name}" &
    done
    wait
}

function _start-vms() {
    for name in $(__get-vm-names);
    do
        az vm start -g $RESOURCE_GROUP_NAME -n "${name}" &
    done
    wait
}

function _ssh() {
    vm="${1:-$VM_MASTER_NAME}"
    vm_ip="$(az vm show -d -g $RESOURCE_GROUP_NAME -n $vm --query publicIps -o tsv)"
    user="${2:-$USER}"
    echo "${user}@${vm_ip}"
    ssh "${user}@${vm_ip}"
}

function main () {
    subcommand="${1}"
    shift;
    eval "_$subcommand $@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
    main "$@"
fi