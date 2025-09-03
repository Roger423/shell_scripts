#!/bin/bash

ACTION=""
NET_DEVICE=""
RDMA_DEVICE=""
VF_CNT=""
SPLIT_LINE="-----------------------------------------------------------------------------------------------------------"

usage() {
    echo $SPLIT_LINE
    echo "Usage: $0 -a <sriov action(enable/disable)> [-n <net function id>] [-r <rdma function id>] [-c <vf count>]"
    echo $SPLIT_LINE
    exit 1
}

enable_sriov() {
    local device=$1
    local vf_num=$2
    echo $SPLIT_LINE
    echo "Enabling SR-IOV for device: $device"

    max_vfs=$(cat /sys/bus/pci/devices/$device/sriov_totalvfs 2>/dev/null)

    if [ -z "$max_vfs" ] || [ "$max_vfs" -eq 0 ]; then
        echo "Device $device does not support SR-IOV"
        return
    fi

    if [ -z "$vf_num" ] || [ "$vf_num" -gt "$max_vfs" ]; then
        vf_num=$max_vfs
    fi

    echo "$vf_num" > /sys/bus/pci/devices/$device/sriov_numvfs
    echo "Enabled $vf_num VFs for device $device"
}

disable_sriov() {
    local device=$1
    echo "Disabling SR-IOV for device: $device"

    echo 0 > /sys/bus/pci/devices/$device/sriov_numvfs 2>/dev/null
    echo "Disabled SR-IOV for device $device"
}

init_devices() {
    if [ -z "$NET_DEVICE" ]; then
        net_devices=$(lspci -D | grep -i 'red' | awk '{print $1}')
    else
        net_devices=$NET_DEVICE
    fi

    if [ -z "$RDMA_DEVICE" ]; then
        rdma_devices=$(lspci -D | grep -i 'xi' | awk '{print $1}')
    else
        rdma_devices=$RDMA_DEVICE
    fi
}

show_pcie_devs() {
    lspci -D | grep -E -i 'red|xi'
}

net_sriov_ctl() {
    echo $SPLIT_LINE
    echo "$ACTION SRIOV for net devices"
    for net_dev in $net_devices; do
        case $ACTION in
            enable)
                enable_sriov "$net_dev" "$VF_CNT"
                ;;
            disable)
                disable_sriov "$net_dev"
                ;;
            *)
                echo "Invalid action. Please use 'enable' or 'disable'."
                exit 1
                ;;
        esac
    done
    echo $SPLIT_LINE
}

rdma_sriov_ctl() {
    echo $SPLIT_LINE
    echo "$ACTION SRIOV for RDMA devices"
    for rdma_dev in $rdma_devices; do
        case $ACTION in
            enable)
                enable_sriov "$rdma_dev" "$VF_CNT"
                ;;
            disable)
                disable_sriov "$rdma_dev"
                ;;
            *)
                echo "Invalid action. Please use 'enable' or 'disable'."
                exit 1
                ;;
        esac
    done
    echo $SPLIT_LINE
}

while getopts "a:n:r:c:" opt; do
    case "$opt" in
        a) ACTION="$OPTARG" ;;
        n) NET_DEVICE="$OPTARG" ;;
        r) RDMA_DEVICE="$OPTARG" ;;
        c) VF_CNT="$OPTARG" ;;
        *) usage ;;
    esac
done

init_devices
echo $SPLIT_LINE
echo "PCIe devices before setting SR-IOV:"
show_pcie_devs
echo $SPLIT_LINE
if [ "$ACTION" == "enable" ]; then
    net_sriov_ctl
    rdma_sriov_ctl
elif [ "$ACTION" == "disable" ]; then
    rdma_sriov_ctl
    net_sriov_ctl
fi
echo $SPLIT_LINE
echo "PCIe devices after setting SR-IOV:"
show_pcie_devs
