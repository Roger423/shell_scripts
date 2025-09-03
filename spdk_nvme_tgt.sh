#!/bin/bash

SPLIT_LINE="-----------------------------------------------------------------------------------------------------------"
# Set the action for spdk nvmf, should be "setup"(setup configuration for spdk nvmf), or "teardown"(clear all spdk nvmf
# configurations)
ACTION="setup"

# Set the count of 2M hugepages for spdk to use
HUGEPAGES=32000

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

# Set function index list to use for spdk nvmf test, pf index start at 0, vf index of each pf start at 0.
# pf: pf0, pf1, pf2...
# vf: pf0vf0, pf0vf1, pf1vf0, pf1vf2...
FUNCTIONS="pf0"

# Set the IP address list for net device that corresponding to rdma device to use, IP addresses count should equal or 
# greater than the count of function device list in 'FUNCTIONS'
TGT_IP="10.0.0.1"

# Set the start port of spdk nvmf corresponding to each IP address in 'TGT_IP', the start port count should eqaul
# to the count of IP addresses count in 'TGT_IP', the number of port will increase by 1 for each nvme bdev whose 
# count is specified in 'NVME_CNT'
TGT_PORT="4420"

# Set the count of nvme bdev for each function device in 'FUNCTIONS'
NVME_CNT=2

# Set IP mask for each IP address in 'TGT_IP'
IP_MASK=16

# Set the MTU for each net device that corresponding to rdma devices
MTU=4200

# Set the path of SPDK software
SPDK_HOME=/opt/spdk

# Set the path of SPDK config file
SPDK_CONFIG_FILE=/home/rdma/spdk_config.json

# Set the command of nvmf_create_transport
# CREATE_TRANSPORT_CMD="nvmf_create_transport -t RDMA -u 8192 -i 32768 -c 8192 -q 4096 -s 4096 -m 32 -d 4096"
CREATE_TRANSPORT_CMD="nvmf_create_transport -t RDMA -u 8192 -i 131072 -c 8192"

# Set whether to enable the SRQ function, true or false
SRQ="true"

declare -A RDMA_DEV_MAP
declare -A PF_MAP


print_help() {
    cat << EOF
$SPLIT_LINE
Setup or teardown the configuration of SPDK NVMe-of target.

Usage:
    $0 -h or $0 help or $0 --help
    or
    $0 action=<setup or teardown> hugepages=<the number of 2m hugepages> rib_drv=<rib driver path>  \
load_drv=<whether to load rib driver(true/false)> tos=<tos value for each function> set_pfc=<whether to set \
pfc(true/false)> dev_type=<device type(rib/mlx)> func=<test function index> tgt_ip=<target ip list> ip_mask=<ip mask \
length> mtu=<interface mtu> tgt_port=<target port list> nvme_count=<nvme disk count for each function> spdk_home=<spdk \
software path> spdk_config_file=<spdk config file path> create_transport_cmd=<create transport command>

Arguments:
    action:                the action of running this script(setup/teardown), default is $ACTION.

    hugepages:             number of 2m hugepages to setup, default value is $HUGEPAGES.

    rib_drv:               the rib driver path, default is $RIB.

    load_drv:              whether to load rdma driver before setup spdk nvme-of, default is $LOAD_DRV

    tos:                   the tos value for each function, default value is $TOS_VAL.

    set_pfc:               whether to configure pfc, the default is $SET_PFC.

    dev_type:              the test device type(rib: use resnics device. mlx: use Mellanox device), default is $DEV_TYPE.

    func:                  the function index list to test, a string of one or multiple function index, which are 
                           seperated by space. function index format is as: pf0, pf1, pf0vf0, pf1vf14..., such 
                           as "pf0 pf1", "pf0 pf0vf0". default is "$FUNCTIONS".

    tgt_ip:                target ip addresses,  a string of one or multiple ip addresses, which are seperated by space. 
                           the ip addresses number should equal to that of the function index list, default is "$TGT_IP".

    ip_mask:               mask length for ip addresses, a integer number range from 0 to 32. default value is $IP_MASK.

    mtu:                   MTU value for net interfaces, default value is $MTU.

    tgt_port:              target initial port of each function for spdk nvme-of to listen to, a string of one or 
                           multiple port number, which are seperated by space. For the reason that there may be multiple
                           nmve disk count for each function, each nvme disk will occupy a port number, the gap between 
                           each port should larger than the value of NVME_CNT. default is "$TGT_PORT".

    nvme_count:            nvme disk count for each function index, default value is $NVME_CNT.

    srq:                   whether to enable srq function, default value is $SRQ.

    spdk_home:             the spdk software absolute path, default is $SPDK_HOME.

    spdk_config_file:      the spdk configure file absolute path, default is $SPDK_CONFIG_FILE.

    create_transport_cmd:  the command line while execute create transport command for spdk nvme-of. 
                           default is $CREATE_TRANSPORT_CMD


Examples:
    Setup spdk nvme-of with default value for every parameters.
        bash $0

    Setup spdk nvme-of with specified func list, ip list, and port list
        bash $0 func="pf0 pf0vf0 pf1 pf1vf0" tgt_ip="10.0.0.1 11.0.0.1 12.0.0.1 13.0.0.1" tgt_port="4420 4430 4440 4450"

    Setup spdk nvme-of with specified hugepages, load_drv is true, func list, ip list, and port list
        bash $0  hugepages=32000 load_drv=true func="pf0 pf0vf14 pf1 pf1vf14" \
tgt_ip="10.0.0.1 20.0.0.1 30.0.0.1 40.0.0.1" tgt_port="4420 4430 4440 4450"
    
    Clear all configurations of spdk nvme-of target:
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
		hugepages=*)
			HUGEPAGES="${arg#*=}"
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
		srq=*)
			SRQ="${arg#*=}"
			;;
		spdk_home=*)
			SPDK_HOME="${arg#*=}"
			;;
		spdk_config_file=*)
			SPDK_CONFIG_FILE="${arg#*=}"
			;;
		create_transport_cmd=*)
			CREATE_TRANSPORT_CMD="${arg#*=}"
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

if [ "$SRQ" == "false" ]; then
    CREATE_TRANSPORT_CMD="$CREATE_TRANSPORT_CMD -r"
fi

check_action() {
    if [ "$ACTION" != "setup" ] && [ "$ACTION" != "teardown" ]; then
        echo "Invalid action: $ACTION. Should be \"setup\" or \"teardown\""
        exit 1
    fi
}

get_all_pcie_dev() {
    # echo "Get all $DEV_TYPE function devices..."
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

kill_all_nvmf_tgt() {
    echo "Kill all tgt processes..."
    pkill -9 -f nvmf_tgt
    pkill -9 -f spdk_tgt
    pkill -9 -f iscsi_tgt
}

start_spdk_tgt() {
    echo "Start spdk nvmf_tgt process..."
    kill_all_nvmf_tgt
    sleep 3
    NRHUGE=$HUGEPAGES $SPDK_HOME/scripts/setup.sh
    sleep 3
    $SPDK_HOME/build/bin/nvmf_tgt -m 0xff0 -c $SPDK_CONFIG_FILE &
    sleep 5
}

clear_nvmf() {
    echo "Clear all tgt processes"
    if ! pgrep -f nvmf_tgt > /dev/null && \
       ! pgrep -f spdk_tgt > /dev/null && \
       ! pgrep -f iscsi_tgt > /dev/null; then
        echo "None of nvmf_tgt, spdk_tgt, iscsi_tgt processes are running. No need to clear nvmf"
        return
    fi

    rpc_path=$SPDK_HOME/scripts/rpc.py
    subsystems=$($rpc_path nvmf_get_subsystems | grep nqn | awk -F'"' '{print $4}')
    echo "All spdk nvmf subsystems:"
    echo $subsystems
    if [ -n "$subsystems" ]; then
        for nqn in $subsystems; do
            echo "nqn of subsystem: $nqn"
            subtype=$($rpc_path nvmf_get_subsystems | grep -A 5 $nqn | grep subtype | awk -F'"' '{print $4}')
            if [ "$subtype" == "Discovery" ]; then
                echo "Skipping discovery subsystem: $nqn"
                continue
            fi
            echo "Deleting subsystem $nqn ..."
            $rpc_path nvmf_delete_subsystem $nqn
        done
    fi
    echo "Check SPDK subsystems after clear all subsystems..."
    echo $($rpc_path nvmf_get_subsystems)
}

create_null_bdev() {
    # local idx=$1
    local ip=$1
    local port=$2
    local bdev=$3
    local nqn=$4
    echo "-----------------------------------"
    echo "Create null bdev and subsystem:"
    # echo "idx ----> $idx"
    echo "ip ----> $ip"
    echo "port ----> $port"
    echo "bdev ----> $bdev"
    echo "nqn ----> $nqn"
    echo "-----------------------------------"
    echo "Creating null bdev $bdev..."
    $rpc_path bdev_null_create "$bdev" 10240 512
    echo "Creating subsystem $nqn..."
    local subsys_name=$(printf "%012d" $((RANDOM)))
    local subsys_no=$(printf "%d" $((RANDOM)))
    $rpc_path nvmf_create_subsystem "$nqn" -a -s "SPDK$subsys_name" -d "SPDK_Controller$subsys_no"
    echo "Adding $bdev to subsystem $nqn..."
    $rpc_path nvmf_subsystem_add_ns "$nqn" "$bdev"
    echo "Adding listener to subsystem $nqn..."
    $rpc_path nvmf_subsystem_add_listener "$nqn" -f ipv4 -t rdma -a $ip -s "$port"
    sleep 3
}

create_func_spdk_nvmf() {
    local func_idx=$1
    local ip=$2
    local start_port=$3
    local max_idx=$(($NVME_CNT-1))
    for i in $(seq 0 "$max_idx"); do
        local port=$(($start_port+$i))
        local bdev="null_${func_idx}_$i"
        local nqn="nqn.2016-06.io.spdk:cnode_${func_idx}_$i"
        create_null_bdev $ip $port $bdev $nqn
    done
}

set_spdk_nvmf() {
    start_spdk_tgt
    local idx=0
    echo $SPLIT_LINE
    echo "Configure SPDK NVMF target..."
    clear_nvmf
    echo "Creating RDMA transport..."
    rpc_path=$SPDK_HOME/scripts/rpc.py
    echo "CMD --> $CREATE_TRANSPORT_CMD"
    $rpc_path $CREATE_TRANSPORT_CMD

    for fc in ${FUNC_LIST[@]}; do
        echo $SPLIT_LINE
        echo "Configure SPDK NVMF for function $fc"
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
        create_func_spdk_nvmf $idx $tgt_ip $tgt_port
        idx=$(($idx+1))
    done
}

get_spdk_nvmf_info() {
    rpc_path=$SPDK_HOME/scripts/rpc.py
    echo "Getting all SPDK NVMf information..."
    echo "1. NVMf Transports:"
    $rpc_path nvmf_get_transports
    echo $SPLIT_LINE
    echo "2. NVMf Subsystems:"
    $rpc_path nvmf_get_subsystems
    echo $SPLIT_LINE
    echo "3. NVMf Listeners:"
    subsystems=$($rpc_path nvmf_get_subsystems | jq -r '.[].nqn')
    for nqn in $subsystems; do
        echo "Listeners for Subsystem: $nqn"
        $rpc_path nvmf_subsystem_get_listeners $nqn
        echo $SPLIT_LINE
    done
}

clear_hugepages() {
    echo "Clear hugepages"
    sudo sysctl -w vm.nr_hugepages=0
    grep Huge /proc/meminfo
}

clear_interface_ip() {
    echo "Clear interface IP addresses"
    ifaces=$(rdma link |grep $DEV_TYPE | awk '/netdev/ {print $NF}')
    for iface in $ifaces; do
        echo "Flushing IP addresses for interface $iface"
        ip addr flush dev $iface
    done
}

teardown() {
    check_action
    clear_nvmf
    echo $SPLIT_LINE
    kill_all_nvmf_tgt
    echo $SPLIT_LINE
    clear_interface_ip
    echo $SPLIT_LINE
    clear_hugepages
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
    clear_nvmf
    echo $SPLIT_LINE
    kill_all_nvmf_tgt
    sleep 3
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
    clear_nvmf
    sleep 2
    echo $SPLIT_LINE
    kill_all_nvmf_tgt
    sleep 2
    echo $SPLIT_LINE
    set_spdk_nvmf
    echo $SPLIT_LINE
    get_spdk_nvmf_info
    echo $SPLIT_LINE
}

main
