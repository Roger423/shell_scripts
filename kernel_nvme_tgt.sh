#!/bin/bash

SPLIT_LINE="-----------------------------------------------------------------------------------------------------------"
# Set the action for kernel nvmf, should be "setup"(setup configuration for kernel nvmf), or "teardown"(clear all 
# kernel nvmf configurations)
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

# Set function index list to use for kernel nvmf test, pf index start at 0, vf index of each pf start at 0.
# pf: pf0, pf1, pf2...
# vf: pf0vf0, pf0vf1, pf1vf0, pf1vf2...
FUNCTIONS="pf0"

# Set the IP address list for net device that corresponding to rdma device to use, IP addresses count should equal or 
# greater than the count of function device list in 'FUNCTIONS'
TGT_IP="10.0.0.1"

# Set the start port of kernel nvmf corresponding to each IP address in 'TGT_IP', the start port count should eqaul
# to the count of IP addresses count in 'TGT_IP', the number of port will increase by 1 for each nvme bdev whose 
# count is specified in 'NVME_CNT'
TGT_PORT="4420"

# Set the count of nvme bdev for each function device in 'FUNCTIONS'
NVME_CNT=2

# Set IP mask for each IP address in 'TGT_IP'
IP_MASK=16

# Set the MTU for each net device that corresponding to rdma devices
MTU=4200

declare -A RDMA_DEV_MAP
declare -A PF_MAP


print_help() {
    cat << EOF
$SPLIT_LINE
Setup or teardown the configuration of kernel NVMe-of target.

Usage:
    $0 -h or $0 help or $0 --help
    or
    $0 action=<setup or teardown> rib_drv=<rib driver path> load_drv=<whether to load rib \
driver(true/false)> tos=<tos value for each function> set_pfc=<whether to set pfc(true/false)> dev_type=<device \
type(rib/mlx)> func=<test function index> tgt_ip=<target ip list> ip_mask=<ip mask length> mtu=<interface mtu> \
tgt_port=<target port list> nvme_count=<nvme disk count for each function> echo_file=<echo file path>

Arguments:
    action:                the action of running this script(setup/teardown), default is $ACTION.

    rib_drv:               the rib driver path, default is $RIB.

    load_drv:              whether to load rdma driver before setup kernel nvme-of, default is $LOAD_DRV

    tos:                   the tos value for each function, default value is $TOS_VAL.

    set_pfc:               whether to configure pfc, the default is $SET_PFC.

    dev_type:              test device type(rib: use resnics device. mlx: use Mellanox device), default is $DEV_TYPE.

    func:                  the function index list to test, a string of one or multiple function index seperated by 
                           space. function index format is as: pf0, pf1, pf0vf0, pf1vf14..., such as "pf0 pf1", 
                           "pf0 pf0vf0". default is "$FUNCTIONS".

    tgt_ip:                target ip addresses,  a string of one or multiple ip addresses seperated by space. the ip 
                           addresses number should equal to that of the function index list, default is "$TGT_IP".

    ip_mask:               mask length for ip addresses, a integer number range from 0 to 32. default value is $IP_MASK.

    mtu:                   MTU value for net interfaces, default value is $MTU.

    tgt_port:              target initial port of each function for kernel nvme-of to listen to, a string of one or 
                           multiple port number seperated by space. For the reason that there may be multiple nmve disk
                           count for each function, each nvme disk will occupy a port number, the gap between each port
                           should larger than the value of NVME_CNT. default is "$TGT_PORT".

    nvme_count:            nvme disk count for each function index, default value is $NVME_CNT.

Examples:
    Setup kernel nvme-of with default value for every parameters.
        bash $0

    Setup kernel nvme-of with specified func list, ip list, and port list
        bash $0 func="pf0 pf0vf0 pf1 pf1vf0" tgt_ip="10.0.0.1 11.0.0.1 12.0.0.1 13.0.0.1" tgt_port="4420 4430 4440 4450"
    
    Clear all configurations of kernel nvme-of target:
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
			FUNCTIONS="${arg#*=}"
			;;
		tgt_ip=*)
			TGT_IP="${arg#*=}"
			;;
		ip_mask=*)
			IP_MASK="${arg#*=}"
			;;
		mtu=*)
			MTU="${arg#*=}"
			;;
		tgt_port=*)
			TGT_PORT="${arg#*=}"
			;;
		nvme_count=*)
			NVME_CNT="${arg#*=}"
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

IFS=' ' read -r -a FUNC_LIST <<< "$FUNCTIONS"
IFS=' ' read -r -a TGT_IP_LIST <<< "$TGT_IP"
IFS=' ' read -r -a TGT_PORT_LIST <<< "$TGT_PORT"
FC_CNT=${#FUNC_LIST[@]}
NULL_CNT=$(($FC_CNT * $NVME_CNT))


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

    modprobe nvmet
    modprobe nvme-rdma
    echo "Create $NULL_CNT null blk dev..."
    modprobe -r null_blk
    echo "modprobe null_blk nr_devices=$NULL_CNT"
    modprobe null_blk nr_devices=$NULL_CNT
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
    local ip=${TGT_IP_LIST[$idx]}
    local port=${TGT_PORT_LIST[$idx]}
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
            IFS=' ' read -r fcid ib_dev iface tgt_ip tgt_port rib_dev <<< "${RDMA_DEV_MAP[$fc]}"
        fi
        if [ "$DEV_TYPE" == "mlx" ]; then
            IFS=' ' read -r fcid ib_dev iface tgt_ip tgt_port <<< "${RDMA_DEV_MAP[$fc]}"
        fi
        echo "PCIe function ID:  $fcid"
        echo "IB device       :  $ib_dev"
        echo "Net interface   :  $iface"
        echo "Target IP       :  $tgt_ip"
        echo "Target port     :  $tgt_port"
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

create_kernel_nvme() {
    local nvme_name=$1
    local ns=10
    local null_blk=$2
    local ip=$3
    local port=$4

    echo "exec: mkdir /sys/kernel/config/nvmet/subsystems/$nvme_name"
    mkdir /sys/kernel/config/nvmet/subsystems/$nvme_name

    echo "exec: echo 1 > /sys/kernel/config/nvmet/subsystems/$nvme_name/attr_allow_any_host"
    echo 1 > /sys/kernel/config/nvmet/subsystems/$nvme_name/attr_allow_any_host

    echo "exec: mkdir /sys/kernel/config/nvmet/subsystems/$nvme_name/namespaces/$ns"
    mkdir /sys/kernel/config/nvmet/subsystems/$nvme_name/namespaces/$ns

    echo "exec: echo -n $null_blk > /sys/kernel/config/nvmet/subsystems/$nvme_name/namespaces/$ns/device_path"
    echo -n /dev/$null_blk > /sys/kernel/config/nvmet/subsystems/$nvme_name/namespaces/$ns/device_path

    echo "exec: echo 1 > /sys/kernel/config/nvmet/subsystems/$nvme_name/namespaces/$ns/enable"
    echo 1 > /sys/kernel/config/nvmet/subsystems/$nvme_name/namespaces/$ns/enable

    echo "exec: mkdir /sys/kernel/config/nvmet/ports/$port"
    mkdir /sys/kernel/config/nvmet/ports/$port

    echo "exec: echo $ip > /sys/kernel/config/nvmet/ports/$port/addr_traddr"
    echo $ip > /sys/kernel/config/nvmet/ports/$port/addr_traddr

    echo "exec: echo rdma > /sys/kernel/config/nvmet/ports/$port/addr_trtype"
    echo rdma > /sys/kernel/config/nvmet/ports/$port/addr_trtype

    echo "exec: echo $port > /sys/kernel/config/nvmet/ports/$port/addr_trsvcid"
    echo $port > /sys/kernel/config/nvmet/ports/$port/addr_trsvcid

    echo "exec: echo ipv4 > /sys/kernel/config/nvmet/ports/$port/addr_adrfam"
    echo ipv4 > /sys/kernel/config/nvmet/ports/$port/addr_adrfam

    echo "exec: ln -s /sys/kernel/config/nvmet/subsystems/$nvme_name \
/sys/kernel/config/nvmet/ports/$port/subsystems/$nvme_name"
    ln -s /sys/kernel/config/nvmet/subsystems/$nvme_name /sys/kernel/config/nvmet/ports/$port/subsystems/$nvme_name
}

create_func_kernel_nvmf() {
    local func_idx=$1
    local ip=$2
    local start_port=$3
    local max_idx=$(($NVME_CNT-1))
    for i in $(seq 0 "$max_idx"); do
        local port=$(($start_port+$i))
        local subsys="nvme_${func_idx}_$i"
        local null_blk_idx=$(($func_idx * $NVME_CNT + $i))
        local null_blk="nullb${null_blk_idx}"
        create_kernel_nvme $subsys $null_blk $ip $port
    done
}

set_kernel_nvmf() {
    local idx=0
    echo $SPLIT_LINE
    echo "Configure Kernel NVMF target..."

    for fc in ${FUNC_LIST[@]}; do
        echo $SPLIT_LINE
        echo "Configure Kernel NVMF for function $fc"
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
        create_func_kernel_nvmf $idx $tgt_ip $tgt_port
        idx=$(($idx+1))
    done
}

check_subsystem() {
    local subsystem=$1
    if [ -d "/sys/kernel/config/nvmet/subsystems/$subsystem" ]; then
        echo "Subsystem $subsystem is created"
    else
        echo "Subsystem $subsystem is not created"
    fi
}

check_allow_any_host() {
    local subsystem=$1
    local value=$(cat /sys/kernel/config/nvmet/subsystems/$subsystem/attr_allow_any_host 2>/dev/null)
    echo "Subsystem $subsystem attr_allow_any_host setting: $value"
}

check_namespace() {
    local subsystem=$1
    for namespace in /sys/kernel/config/nvmet/subsystems/$subsystem/namespaces/*; do
        if [ -d "$namespace" ]; then
            namespace_id=$(basename $namespace)
            echo "Namespace $namespace_id in subsystem $subsystem is created"
            check_device_path_and_enable $subsystem $namespace_id
        fi
    done
}

check_device_path_and_enable() {
    local subsystem=$1
    local namespace=$2
    local device_path=$(cat /sys/kernel/config/nvmet/subsystems/$subsystem/namespaces/$namespace/device_path 2>/dev/null)
    local enable=$(cat /sys/kernel/config/nvmet/subsystems/$subsystem/namespaces/$namespace/enable 2>/dev/null)
    echo "Namespace $namespace in subsystem $subsystem device_path: $device_path"
    echo "Namespace $namespace in subsystem $subsystem enable setting: $enable"
}

check_port() {
    for port in /sys/kernel/config/nvmet/ports/*; do
        if [ -d "$port" ]; then
            port_id=$(basename $port)
            echo "Port $port_id is created"
            check_port_settings $port_id
            check_subsystem_link $port_id
        fi
    done
}

check_port_settings() {
    local port=$1
    local traddr=$(cat /sys/kernel/config/nvmet/ports/$port/addr_traddr 2>/dev/null)
    local trtype=$(cat /sys/kernel/config/nvmet/ports/$port/addr_trtype 2>/dev/null)
    local trsvcid=$(cat /sys/kernel/config/nvmet/ports/$port/addr_trsvcid 2>/dev/null)
    local adrfam=$(cat /sys/kernel/config/nvmet/ports/$port/addr_adrfam 2>/dev/null)
    echo "Port $port addr_traddr setting: $traddr"
    echo "Port $port addr_trtype setting: $trtype"
    echo "Port $port addr_trsvcid setting: $trsvcid"
    echo "Port $port addr_adrfam setting: $adrfam"
}

check_subsystem_link() {
    local port=$1
    for subsystem in /sys/kernel/config/nvmet/ports/$port/subsystems/*; do
        if [ -L "$subsystem" ]; then
            subsystem_id=$(basename $subsystem)
            echo "Subsystem $subsystem_id is linked to port $port"
        fi
    done
}

get_kernel_nvmf_info() {
    for subsystem in /sys/kernel/config/nvmet/subsystems/*; do
        if [ -d "$subsystem" ]; then
            subsystem_id=$(basename $subsystem)
            check_subsystem $subsystem_id
            check_allow_any_host $subsystem_id
            check_namespace $subsystem_id
        fi
    done
    check_port
}

clear_kernel_nvmf() {
    echo "Starting cleanup of all NVMe-oF configurations..."
    local subsys_dir="/sys/kernel/config/nvmet/subsystems"
    local ports_dir="/sys/kernel/config/nvmet/ports"
    echo "Listing all NVMe subsystems:"
    if [ -d "$subsys_dir" ] && [ "$(ls -A $subsys_dir)" ]; then
        ls -l "$subsys_dir" | grep ^d | awk '{print $9}'
    else
        echo "No subsystems found in $subsys_dir"
    fi

    if [ -d "$ports_dir" ] && [ "$(ls -A $ports_dir)" ]; then
        for port in "$ports_dir"/*; do
            if [ -d "$port" ]; then
                port_name=$(basename "$port")
                echo "Processing port: $port_name"
                for link in "$port/subsystems"/*; do
                    if [ -L "$link" ]; then
                        unlink "$link"
                        echo "Removed link: $link"
                    fi
                done
                rmdir "$port" && echo "Removed port: $port_name"
            fi
        done
    else
        echo "No ports found in $ports_dir"
    fi

    if [ -d "$subsys_dir" ] && [ "$(ls -A $subsys_dir)" ]; then
        for subsys in "$subsys_dir"/*; do
            if [ -d "$subsys" ]; then
                subsys_name=$(basename "$subsys")
                echo "Processing subsystem: $subsys_name"
                for ns in "$subsys/namespaces"/*; do
                    if [ -d "$ns" ]; then
                        ns_id=$(basename "$ns")
                        echo "Disabling namespace $ns_id in $subsys_name"
                        echo 0 > "$ns/enable" 2>/dev/null || echo "Warning: Failed to disable namespace $ns_id"
                        rmdir "$ns" && echo "Removed namespace $ns_id"
                    fi
                done
                rmdir "$subsys" && echo "Removed subsystem: $subsys_name"
            fi
        done
    else
        echo "No subsystems to remove in $subsys_dir"
    fi
    echo "Cleanup complete!"
}

clear_interface_ip() {
    ifaces=$(rdma link |grep $DEV_TYPE | awk '/netdev/ {print $NF}')
    for iface in $ifaces; do
        echo "Flushing IP addresses for interface $iface"
        ip addr flush dev $iface
    done
}

teardown() {
    clear_kernel_nvmf
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
    set_kernel_nvmf
    echo $SPLIT_LINE
    get_kernel_nvmf_info
    echo $SPLIT_LINE

}

main
