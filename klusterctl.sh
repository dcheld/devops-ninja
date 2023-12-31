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

    local my_ip=`curl -s ifconfig.me` 
    az network nsg rule create \
        -g $RESOURCE_GROUP_NAME \
        --nsg-name $NSG_NAME \
        --name AllowAnySSHInbound \
        --priority 110 \
        --source-address-prefixes ${my_ip}\
        --destination-port-ranges 22 \
        --access Allow \
        --protocol Tcp

    az network nsg rule create \
        -g $RESOURCE_GROUP_NAME \
        --nsg-name $NSG_NAME \
        --name AllowKubernetes \
        --priority 120 \
        --source-address-prefixes ${my_ip} \
        --destination-port-ranges 6443 \
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

function __get-ca-cert-hash(){
   _ssh $VM_MASTER_NAME $VM_USERNAME -qn \
        -t "openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt \
            | openssl rsa -pubin -outform der 2>/dev/null \
            | openssl dgst -sha256 -hex | sed 's/^.* //'" \
        | tail -1
}

function __get-token(){
    _ssh $VM_MASTER_NAME $VM_USERNAME -qn \
        -t "kubeadm token list -o jsonpath='{.token}'" \
        | tail -1
}

function __get-vm-work-names () {
    for i in $(seq 0 $(expr $VM_COUNT - 1));
    do
        echo "${VM_WORK_NAME}${i}"
    done
}

function __get-vm-names () {
    __get-vm-work-names
    echo "${VM_MASTER_NAME}"
}

function __vm-create-script(){
    scripts=$(cat $1 | gzip -9 | base64 -w 0)
    cat <<< "{ \"script\": \"${scripts}\"} "
}

function __vm-apply-startup-server(){
    local script_path=$(mktemp)
    cat $SCRIPT_DIR/vm/common/*.sh $SCRIPT_DIR/vm/server/*.sh >> $script_path

    __replace-file $script_path \
        my_ip "$(__get-ip)" \
        user $"${VM_USERNAME}"

    local script=$(__vm-create-script $script_path)

    az vm extension set \
        -g $RESOURCE_GROUP_NAME \
        -n customScript \
        --vm-name $VM_MASTER_NAME \
        --extension-instance-name serverInstall \
        --publisher Microsoft.Azure.Extensions \
        --protected-settings "${script}"

    _restart-vms $VM_MASTER_NAME
}

function __vm-apply-startup-nodes(){
    local script_path=$(mktemp)
    cat $SCRIPT_DIR/vm/common/*.sh >> $script_path
    local script=$(__vm-create-script $script_path)
    local worker_names=$(__get-vm-work-names)
    for vm_name in ${worker_names}
    do
        az vm extension set \
            -g $RESOURCE_GROUP_NAME \
            -n customScript \
            --vm-name $vm_name \
            --extension-instance-name nodeInstall \
            --publisher Microsoft.Azure.Extensions \
            --protected-settings "${script}" &
    done
    wait

   _restart-vms ${worker_names}
}

function __vm-connect-cluster(){
    local script_path=$(mktemp)
    cat $SCRIPT_DIR/vm/nodes/*.sh >> $script_path

    __replace-file $script_path \
        vm_master_name $"${VM_MASTER_NAME}" \
        token "$(__get-token)" \
        ca_cert_hash $"$(__get-ca-cert-hash)"

    local script=$(__vm-create-script $script_path)

    for vm_name in $(__get-vm-work-names)
    do
        az vm extension set \
            -g $RESOURCE_GROUP_NAME \
            -n customScript \
            --vm-name $vm_name \
            --extension-instance-name nodeConnect \
            --publisher Microsoft.Azure.Extensions \
            --protected-settings "${script}" &
    done
    wait
}

function _create() {
    __create-resource
    __create-nsg
    __create-vnet
    __create-subnet

    __create-master-vms
    __create-work-vms

    __vm-apply-startup-server
    __vm-apply-startup-nodes
    __vm-connect-cluster
}



function _delete() {
    az group delete \
        -n $RESOURCE_GROUP_NAME \
        --force-deletion-types Microsoft.Compute/virtualMachines \
        --force-deletion-types Microsoft.Compute/virtualMachineScaleSets \
        --yes
}

function _deallocate-vms() {
    local vm_names=${@:-`__get-vm-names`}
    for name in ${vm_names};
    do
        az vm deallocate -g $RESOURCE_GROUP_NAME -n "${name}" &
    done
    wait
}

function _start-vms() {
    local vm_names=${@:-`__get-vm-names`}
    for name in ${vm_names};
    do
        az vm start -g $RESOURCE_GROUP_NAME -n "${name}" &
    done
    wait
}


function _restart-vms() {
    local vm_names=${@:-`__get-vm-names`}
    for name in ${vm_names};
    do
        az vm restart -g $RESOURCE_GROUP_NAME -n "${name}"  &
    done
    wait
}

function __get-ip() {
    vm="${1:-$VM_MASTER_NAME}"
    az vm show -d -g $RESOURCE_GROUP_NAME -n $vm --query publicIps -o tsv
}

function __replace-file(){
    local file_path=${1}
    shift

    local script="sed -i"
    while (($#))
    do
        local expr=$1
        shift
        
        local value=$1
        shift

        script="${script} -e 's/{{${expr}}}/${value}/g'"
    done
    script="$script $file_path"
    eval "$script"
}

function _ssh() {
    vm_ip="$(__get-ip $1)"
    user="${2:-$USER}"
    ssh -o "StrictHostKeyChecking=no" "${user}@${vm_ip}" "${@:3}"
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
