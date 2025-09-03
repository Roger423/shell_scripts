#!/bin/bash

SPLIT_LINE="-----------------------------------------------------------------------------------------------------------"
# Set the action for NFS, should be "setup"(setup configuration for NFS), or "teardown"(clear all kernel NFS 
# configurations)
ACTION="setup"

# Set the path of rib driver
RIB=/home/rdma/rib_driver/rib.ko

# Whether to load rib driver
LOAD_DRV="true"

# Set the tos value to set to be for rib devices 
TOS_VAL=98

# Set whether to set PFC for rib devices
SET_PFC="true"

# Set the device type, should be 'rib'(use rib devices) or 'mlx'(use Mallenox devices)
DEV_TYPE="rib"

# Set function index to use for NFS test, pf index start at 0, vf index of each pf start at 0.
# pf: pf0, pf1, pf2...
# vf: pf0vf0, pf0vf1, pf1vf0, pf1vf2...
FUNCTION="pf0"

# Set the IP address for net device that corresponding to rdma device to use
SRV_IP="10.0.0.1"

# Set the port of NFS corresponding to each IP address in 'SRV_IP'
SRV_PORT="20049"

# Set the count of NFS file for function device in 'FUNCTION'
NFS_CNT=2

# Set IP mask for IP address in 'SRV_IP'
IP_MASK=16

# Set the MTU for each net device that corresponding to rdma devices
MTU=4200

declare -A RDMA_DEV_MAP
declare -A PF_MAP


print_help() {
    cat << EOF
$SPLIT_LINE
Setup or teardown the configuration of kernel NFS server.

Usage:
    $0 -h or $0 help or $0 --help
    or
    $0 action=<setup or teardown> rib_drv=<rib driver path> load_drv=<whether to load rib \
driver(true/false)> tos=<tos value for each function> set_pfc=<whether to set pfc(true/false)> dev_type=<device \
type(rib/mlx)> func=<test function index> srv_ip=<target ip list> ip_mask=<ip mask length> mtu=<interface mtu> \
srv_port=<target port list> nfs_count=<nfs file count for each function>

Arguments:
    action:                the action of running this script(setup/teardown), default is $ACTION.

    rib_drv:               the rib driver path, default is $RIB.

    load_drv:              whether to load rdma driver before setup kernel NFS, default is $LOAD_DRV

    tos:                   the tos value for each function, default value is $TOS_VAL.

    set_pfc:               whether to configure pfc, the default is $SET_PFC.

    dev_type:              test device type(rib: use resnics device. mlx: use Mellanox device), default is $DEV_TYPE.

    func:                  the function index to test, a string of one function index. function index format is as: 
                           pf0, pf1, pf0vf0, pf1vf14... default is "$FUNCTION".

    srv_ip:                server ip addresses,  a string of one ip address, default is "$SRV_IP".

    ip_mask:               mask length for ip addresses, a integer number range from 0 to 32. default value is $IP_MASK.

    mtu:                   MTU value for net interfaces, default value is $MTU.

    srv_port:              NFS server port. default is "$SRV_PORT".

    nfs_count:             NFS file count, default value is $NFS_CNT.

Examples:
    Setup kernel NFS with default value for every parameters.
        bash $0

    Setup kernel NFS with specified func list, ip list, and port list
        bash $0 func="pf0" srv_ip="10.0.0.1" srv_port="20049"
        bash $0 func="pf0vf0" srv_ip="10.0.0.1" srv_port="20049"

    Clear all configurations of kernel nfs server:
        bash $0 action=teardown

$SPLIT_LINE
EOF
}

for arg in "$@"
do
	case $arg in
		action=*)
			ACTION="${arg#*=}"
			;;
		rib_drv=*)
			RIB="${arg#*=}"
			;;
		load_drv=*)
			LOAD_DRV="${arg#*=}"
			;;
		tos=*)
			TOS_VAL="${arg#*=}"
			;;
		set_pfc=*)
			SET_PFC="${arg#*=}"
			;;
		dev_type=*)
			DEV_TYPE="${arg#*=}"
			;;
		func=*)
			FUNCTION="${arg#*=}"
			;;
		srv_ip=*)
			SRV_IP="${arg#*=}"
			;;
		ip_mask=*)
			IP_MASK="${arg#*=}"
			;;
		mtu=*)
			MTU="${arg#*=}"
			;;
		srv_port=*)
			SRV_PORT="${arg#*=}"
			;;
		nfs_count=*)
			NFS_CNT="${arg#*=}"
			;;
		help|-h|--help)
			print_help
			exit 0
			;;
		*)
			echo "Invalid argument: $arg"
			print_help
			exit 1
			;;
	esac
done

IFS=' ' read -r -a FUNC_LIST <<< "$FUNCTION"
IFS=' ' read -r -a SRV_IP_LIST <<< "$SRV_IP"
IFS=' ' read -r -a SRV_PORT_LIST <<< "$SRV_PORT"


check_action() {
    if [ "$ACTION" != "setup" ] && [ "$ACTION" != "teardown" ]; then
        echo "Invalid action: $ACTION. Should be \"setup\" or \"teardown\""
        exit 1
    fi
}

get_all_pcie_dev() {
    if [ "$DEV_TYPE" == "rib" ]; then
        local devices=$(lspci -D | grep -i 'Xi' | grep -v bridge | awk '{print $1}')
    elif [ "$DEV_TYPE" == "mlx" ]; then
        local devices=$(lspci -D | grep -i 'Mellanox' | grep -v bridge | awk '{print $1}')
    else
        echo "Error: Invalid DEV_TYPE, should be 'rib' or 'mlx'"
        exit 1
    fi
    echo $devices
}

get_func_type() {
    local device=$1
    local func_type="pf"
    if [ -L /sys/bus/pci/devices/$device/physfn ]; then
        func_type="vf"
    fi
    echo $func_type
}

get_ib_dev() {
    local pcie_function_id=$1
    for ib_device in /sys/class/infiniband/*; do
        if [[ -d $ib_device/device ]] && [[ -L $ib_device/device ]]; then
            # Get the PCIe function ID of the Infiniband device
            ib_pcie_function_id=$(readlink -f $ib_device/device)
            ib_pcie_function_id=$(basename $ib_pcie_function_id)
            
            if [[ $ib_pcie_function_id == $pcie_function_id ]]; then
                echo $(basename $ib_device)
                return
            fi
        fi
    done
    
    echo "Error: Device with PCIe function ID $pcie_function_id not found."
}

get_net_dev() {
    local ib_device=$1
    rdma_link_output=$(rdma link)
    netdev=$(echo "$rdma_link_output" | grep -E "\<${ib_device}\>" | awk '{print $8}')
    
    if [[ -n $netdev ]]; then
        echo "$netdev"
    else
        echo "Error: Netdev for Infiniband device $ib_device not found."
    fi
}

get_net_pcie_func_id() {
    local iface=$1
    local netdev_pcie_func_id=$(ethtool -i $iface |grep bus-info |awk '{print $2}')
    echo $netdev_pcie_func_id
}

get_pf_map() {
    echo "Get all pf of $DEV_TYPE function devices..."
    local -n pf_map_ref=$1
    local devices=$2
    local pf_counter=0
    for device in $devices; do
        local device_type=$(get_func_type $device)
        if [ "$device_type" == "pf" ]; then
            local key="pf${pf_counter}"
            local ib_dev_id=$(get_ib_dev $device)
            local net_iface=$(get_net_dev $ib_dev_id)
            local net_func_id=$(get_net_pcie_func_id $net_iface)
            pf_map_ref[$key]="$device $net_func_id"
            pf_counter=$((pf_counter + 1))
        fi
    done
}

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

    echo "Create $NFS_CNT null blk dev..."
    modprobe -r null_blk
    modprobe null_blk nr_devices=$NFS_CNT
    echo $SPLIT_LINE
    lsblk
    echo $SPLIT_LINE
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

set_sriov() {
    local rdma_func=$1
    local net_func=$2
    local vf_num=$3
    echo $SPLIT_LINE
    echo "Enabling SR-IOV for device: RDMA: $rdma_func, Net: $net_func"

    max_vfs=$(cat /sys/bus/pci/devices/$rdma_func/sriov_totalvfs 2>/dev/null)
    if [ -z "$max_vfs" ] || [ "$max_vfs" -eq 0 ]; then
        echo "Device $device does not support SR-IOV"
        return
    fi

    current_vfs=$(cat /sys/bus/pci/devices/$rdma_func/sriov_numvfs 2>/dev/null)
    if [ "$vf_num" -eq "$current_vfs" ]; then
        echo "SR-IOV for device $rdma_func is already set to $vf_num VFs, no changes needed"
        return
    elif [ ! "$vf_num" -eq "$current_vfs" ]; then
        echo 0 > /sys/bus/pci/devices/$rdma_func/sriov_numvfs
        echo 0 > /sys/bus/pci/devices/$net_func/sriov_numvfs
        echo "Disabled SR-IOV for device '$rdma_func $net_func'"
    fi

    if [ -z "$vf_num" ] || [ "$vf_num" -gt "$max_vfs" ]; then
        vf_num=$max_vfs
    fi

    echo "$vf_num" > /sys/bus/pci/devices/$net_func/sriov_numvfs
    echo "$vf_num" > /sys/bus/pci/devices/$rdma_func/sriov_numvfs
    echo "Enabled $vf_num VFs for device '$rdma_func $net_func'"
}

check_sriov() {
    local -n pf_dev_map=$1
    declare -A pf_sriov_map
    for func in "${FUNC_LIST[@]}"; do
        if [[ $func =~ vf ]]; then
            pf_dev=${func%%vf*}
            vf_idx=$(echo $func | grep -oP '(?<=vf)\d+')
            if [[ -v pf_sriov_map["$pf_dev"] ]]; then
                if [[ $vf_idx -gt ${pf_sriov_map["$pf_dev"]} ]]; then
                    pf_sriov_map["$pf_dev"]="$((vf_idx + 1))"
                fi
            else
                pf_sriov_map["$pf_dev"]="$((vf_idx + 1))"
            fi
        fi
    done

    for pf in "${!pf_sriov_map[@]}"; do
        IFS=' ' read -r rdma_fc net_fc <<< "${pf_dev_map[$pf]}"
        set_sriov "${rdma_fc}" "${net_fc}" "${pf_sriov_map[$pf]}"
    done
}

get_vf_map() {
    local pf_func=$1
    local -n vf_map_ref=$2

    if [[ -d /sys/bus/pci/devices/$pf_func ]]; then
        for vf_link in /sys/bus/pci/devices/$pf_func/virtfn*; do
            if [[ -L $vf_link ]]; then
                local vf_func=$(readlink -f $vf_link)
                local vf_func=$(basename $vf_func)
                local vf_idx=$(basename $vf_link | grep -oP '(?<=virtfn)\d+')
                vf_map_ref["vf${vf_idx}"]=$vf_func
            fi
        done
    else
        echo "Error: Device $pf_func does not exist."
    fi
}

init_fc_info() {
    local func_id=$1
    local idx=$2
    local ib_dev=$(get_ib_dev $func_id)
    local net_dev=$(get_net_dev $ib_dev)
    local ip=${SRV_IP_LIST[$idx]}
    local port=${SRV_PORT}
    local fc_info="$func_id $ib_dev $net_dev $ip $port"
    if [ "$DEV_TYPE" == "rib" ]; then
        local rib_dev=${ib_dev/_/c}
        fc_info="$func_id $ib_dev $net_dev $ip $port $rib_dev"
    fi
    echo "$fc_info"
}

get_test_func_map() {
    local -n pf_dev_map=$1
    local idx=0
    for fc in "${FUNC_LIST[@]}"; do
        local fc_info=""
        local pf_idx=$(echo $fc | grep -oP 'pf\d+')
        local pf_fc_id=${pf_dev_map[$pf_idx]}
        local pf_rdma_fc_id=$(echo $pf_fc_id |awk '{print $1}')
        if [[ $fc =~ vf ]]; then
            declare -A vf_map
            local vf_idx=$(echo $fc | grep -oP 'vf\d+')
            get_vf_map $pf_rdma_fc_id vf_map
            local vf_fc_id=${vf_map[$vf_idx]}
            fc_info=$(init_fc_info $vf_fc_id $idx)
        else
            fc_info=$(init_fc_info $pf_rdma_fc_id $idx)
        fi
        RDMA_DEV_MAP[$fc]="$fc_info"
        idx=$((idx + 1))
    done
}

print_test_info() {
    echo "TEST DEVICE INFO:"
    echo "Test function list: $(IFS=, ; echo "${FUNC_LIST[*]}")"
    echo "-----------------------------------"

    local idx=0
    for fc in ${FUNC_LIST[@]}; do
        echo "$fc:"
        if [ "$DEV_TYPE" == "rib" ]; then
            IFS=' ' read -r fcid ib_dev iface s_ip s_port rib_dev <<< "${RDMA_DEV_MAP[$fc]}"
        fi
        if [ "$DEV_TYPE" == "mlx" ]; then
            IFS=' ' read -r fcid ib_dev iface s_ip s_port <<< "${RDMA_DEV_MAP[$fc]}"
        fi
        echo "PCIe function ID:  $fcid"
        echo "IB device       :  $ib_dev"
        echo "Net interface   :  $iface"
        echo "Target IP       :  $s_ip"
        echo "Target port     :  $s_port"
        if [ "$DEV_TYPE" == "rib" ]; then
            echo "RIB device      :  $rib_dev"
        fi
        echo ""
        idx=$(($idx+1))
    done
    echo "-----------------------------------"
}

set_tos() {
    local dev=$1
    local tos=$2
    echo "Set tos to be $tos for $dev"
    echo 1 >/sys/class/ribc/$dev/tos_global_en
    echo $tos >/sys/class/ribc/$dev/tos_global_val
    # Get the current TOS value
    local current_tos=$(cat /sys/class/ribc/$dev/tos_global_val)
    echo "TOS value of ${dev} --> ${current_tos}"
}

apply_init_dcqcn_paras() {
    local dev=$1
    echo "Apply initial parameter for RoCE DCQCN for $dev"
    rqos rcm enable $dev
    # rqos rcm set $dev rl cbs 0x00003400
    # rqos rcm set $dev rl log_time 0x00000000
    # rqos rcm set $dev np min_time_cnps 0x00000004
    # rqos rcm set $dev rp max_rate 0x000186a0
    # rqos rcm set $dev rp min_rate 0x0000000a
    # rqos rcm set $dev rp alpha 0x000003ff
    # rqos rcm set $dev rp g 0x000003fb
    # rqos rcm set $dev rp ai_rate 0x00000005
    # rqos rcm set $dev rp hai_rate 0x00000032
    # rqos rcm set $dev rp k 0x00000001
    # rqos rcm set $dev rp timer 0x0000012c
    # rqos rcm set $dev rp byte_count 0x00004000
    # rqos rcm set $dev rp f 0x00000001

    rqos rcm enable $dev
    rqos rcm set $dev np min_time_cnps 4
    rqos rcm set $dev rp min_rate 10
    rqos rcm set $dev rp max_rate 100000
    rqos rcm set $dev rp alpha 1023
    rqos rcm set $dev rp g 1022
    rqos rcm set $dev rp k 1
    rqos rcm set $dev rp f 1
    rqos rcm set $dev rp ai_rate 5
    rqos rcm set $dev rp hai_rate 50 
    rqos rcm set $dev rp timer 300 
    rqos rcm set $dev rp byte_count 16000

    rqos rcm get $dev state
}

set_pfc() {
    local dev=$1
    echo "Config pfc for $dev"
    # rqos pfc  enable  $dev lossless
    # rqos pfc set $dev tx_policy 1
    # rqos pfc set $dev high_limit 0x30
    # rqos pfc set $dev low_limit 0x10
    # rqos pfc set $dev tc 3 send_slop 0x333 idle_slop 0xccd tx_xon 0x18000 tx_xoff 0x10000 rx_xon 0x18000 rx_xoff 0x10000

    rqos pfc enable $dev lossless
    rqos pfc set $dev tx_policy 1
    rqos pfc set $dev low_limit 0x00000010
    rqos pfc set $dev high_limit 0x00000030
    rqos pfc set $dev tc 3 send_slop 0x333 idle_slop 0xccd tx_xon 0x180 tx_xoff 0x180 rx_xon 0x4000 rx_xoff 0x8000

    rqos pfc get $dev config
}

set_interface_ip() {
    local iface=$1
    local ip_addr=$2
    echo "Set ip address for interface $iface: ip address: $ip_addr"
    ip addr add $ip_addr/$IP_MASK dev $iface
    # ifconfig $iface $ip_addr/$IP_MASK mtu $MTU
    ip link set dev $iface mtu $MTU
    ifconfig $iface
}

create_nullblk_soft_link(){
    rm -rf /mnt/nfs_test
    mkdir -p /mnt/nfs_test
    local max_null_idx=$(($NFS_CNT - 1))
    for i in $(seq 0 $max_null_idx); do
        echo "Create a soft link for /dev/nullb$i to dir /mnt/nfs_test/"
        echo "ln -s /dev/nullb$i /mnt/nfs_test/"
        ln -s /dev/nullb$i /mnt/nfs_test/
    done
    echo "Files in /mnt/nfs_test/:"
    ls /mnt/nfs_test
    echo $SPLIT_LINE
}

stop_services() {
    echo "Stop nfs-server service and rpcbind service"
    systemctl stop nfs-server
    systemctl stop rpcbind
}

start_services() {
    echo "Start nfs-server service and rpcbind service"
    systemctl start rpcbind
    systemctl start nfs-server
}

show_service_status() {
    echo "Show status of nfs-server service and rpcbind service"
    systemctl status rpcbind
    systemctl status nfs-server
}

export_fs() {
    echo "Clear exports: echo > /etc/exports"
    echo > /etc/exports

    echo "Set /mnt/nfs_test to be shared dir"
    echo 'echo "/mnt/nfs_test *(rw,async,insecure,no_root_squash,no_subtree_check)" > /etc/exports'
    echo "/mnt/nfs_test *(rw,async,insecure,no_root_squash,no_subtree_check)" > /etc/exports

    echo "Confirm exportfs: exportfs -a"
    exportfs -a

    echo "Show exportfs: exportfs -v"
    exportfs -v

    start_services

    echo "Refresh exportfs: exportfs -r"
    exportfs -r

    echo "Set RDMA port: echo \"rdma $SRV_PORT\" | tee /proc/fs/nfsd/portlist"
    echo "rdma $SRV_PORT" | tee /proc/fs/nfsd/portlist
}

setup_kernel_nfs() {
    echo "Configure Kernel NFS target..."
    stop_services
    create_nullblk_soft_link
    echo $SPLIT_LINE
    for fc in ${FUNC_LIST[@]}; do
        echo $SPLIT_LINE
        if [ "$DEV_TYPE" == "rib" ]; then
            IFS=' ' read -r func_id ib_device interface tgt_ip tgt_port rib_device <<< "${RDMA_DEV_MAP[$fc]}"
        fi
        if [ "$DEV_TYPE" == "mlx" ]; then
            IFS=' ' read -r func_id ib_device interface tgt_ip tgt_port <<< "${RDMA_DEV_MAP[$fc]}"
        fi
        echo $SPLIT_LINE
        set_interface_ip $interface $tgt_ip
        echo $SPLIT_LINE
        if [ "$DEV_TYPE" == "rib" ]; then
            echo $SPLIT_LINE
            set_tos $rib_device $TOS_VAL
            echo $SPLIT_LINE
            if [ "$SET_PFC" == "true" ]; then
                apply_init_dcqcn_paras $rib_device
                echo $SPLIT_LINE
                set_pfc  $rib_device
                echo $SPLIT_LINE
            fi
        fi
    done
    export_fs
    show_service_status
}

clear_kernel_nfs(){
    echo "Clear shared dir: echo > /etc/exports"
    echo > /etc/exports
    exportfs -r

    echo "Delete /mnt/nfs_test"
    rm -rf /mnt/nfs_test

    stop_services
    show_service_status
}

clear_interface_ip() {
    ifaces=$(rdma link |grep $DEV_TYPE | awk '/netdev/ {print $NF}')
    for iface in $ifaces; do
        echo "Flushing IP addresses for interface $iface"
        ip addr flush dev $iface
    done
}

teardown() {
    clear_kernel_nfs
    echo $SPLIT_LINE
    clear_interface_ip
}

main() {
    check_action
    echo $SPLIT_LINE
    if [ $ACTION == "teardown" ]; then
        teardown
        echo $SPLIT_LINE
        exit 0
    fi
    load_mods
    if [ "$DEV_TYPE" == "rib" ] && [ "$LOAD_DRV" == "true" ]; then
        echo $SPLIT_LINE
        load_rib_mod
    fi
    echo $SPLIT_LINE
    local all_fc=$(get_all_pcie_dev)
    declare -A pf_map
    get_pf_map pf_map "$all_fc"
    echo $SPLIT_LINE
    echo "All pf:"
    for pf in "${!pf_map[@]}"; do
        IFS=' ' read -r rdma_func net_func <<< "${pf_map[$pf]}"
        echo "$pf: RDMA function --> ${rdma_func}, Net function --> ${net_func}"
    done
    echo $SPLIT_LINE
    check_sriov pf_map
    get_test_func_map pf_map
    echo $SPLIT_LINE
    print_test_info
    echo $SPLIT_LINE
    setup_kernel_nfs
    echo $SPLIT_LINE
}

main
