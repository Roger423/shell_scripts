#!/bin/bash

##########################################################
# Load rib dirver and set tos default value for rib dev
##########################################################

RIB=/home/rdma/rib_driver/rib.ko

load_mods() {
    echo "Load needed modules..."
    modprobe ib_core
    modprobe ib_uverbs
    modprobe ib_cm
    modprobe ib_umad
    modprobe iw_cm
    modprobe rdma_cm
    modprobe rdma_ucm
    modprobe virtio_net
}

remove_rib() {
    echo "Remove rib dirver..."
    if lsmod | grep -q rib; then
        rmmod rib
    fi
}

load_rib_mod() {
    remove_rib
    sleep 1
    echo "Load rib driver..."
    insmod $RIB
    sleep 1
}

load_rdma_drv() {
    load_mods
    load_rib_mod
    sleep 1
}

# Function to check if rib module is loaded
check_rib_module() {
    if ! lsmod | grep -q rib; then
        echo "rib module is not loaded. Please load the rib module and try again."
        exit 1
    fi
}

# Get parameters: device name and tos value
device=${1:-all}
tos_val=${2:-98}

# Get list of devices starting with rib
get_devices() {
    rdma link | grep '^link rib_' | awk '{print $2}' | cut -d '/' -f 1
}

# Set TOS
set_tos() {
    local dev=$1
    local tos=$2
    mkdir -p /sys/kernel/config/rdma_cm/${dev}
    echo $tos > /sys/kernel/config/rdma_cm/${dev}/ports/1/default_roce_tos
    # Get the current TOS value
    local current_tos=$(cat /sys/kernel/config/rdma_cm/${dev}/ports/1/default_roce_tos)
    echo "TOS value of ${dev} --> ${current_tos}"
}

load_rdma_drv
# Check if rib module is loaded
check_rib_module

# Configure TOS based on the parameter
if [ "$device" == "all" ]; then
    # Set TOS for all devices
    devices=$(get_devices)
    for dev in $devices; do
        set_tos $dev $tos_val
    done
else
    # Set TOS for a single device
    set_tos $device $tos_val
fi

echo "TOS configuration is complete."
