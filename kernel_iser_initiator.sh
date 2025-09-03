#!/bin/bash

SPLIT_LINE="-----------------------------------------------------------------------------------------------------------"

# Set the action for kernel iser, should be "setup"(setup configuration for kernel iser), or "teardown"(clear all 
# kernel iser configurations)
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

# Set dev index list to use for kernel iser test, pf index start at 0, vf index of each pf start at 0.
# pf: pf0, pf1, pf2...
# vf: pf0vf0, pf0vf1, pf1vf0, pf1vf2...
FUNCTIONS="pf0"

# Set the target IP address list for net device that corresponding to rdma device to use, IP addresses count should 
# equal or greater than the count of function device list in 'FUNCTIONS'
TGT_IP="10.0.0.1"

# Set the initiator IP address list for net device that corresponding to rdma device to use, IP addresses count should 
# equal or greater than the count of function device list in 'FUNCTIONS'
INIT_IP="10.0.0.2"

# Set the start port of kernel iser corresponding to each IP address in 'TGT_IP', the start port count should eqaul
# to the count of IP addresses count in 'TGT_IP', the number of port will increase by 1 for each ISER disk whose 
# count is specified in 'DISK_CNT'
TGT_PORT="3260"

# Set the count of iser disk for each function device in 'FUNCTIONS'
DISK_CNT=2

# Set IP mask for each IP address in 'TGT_IP'
IP_MASK=16

# Set the MTU for each net device that corresponding to rdma devices
MTU=4200

# Set the fio software path
FIO_PATH=/opt/fio/fio

# Set the directory for fio result file to save to.
TEST_RESULT_DIR=/home/test_result/

# Set the prefix for sub test result dir
TEST_SUB_DIR_PREFIX="Test"

# Whether to execute fio test after setup kernel initiator
FIO_TEST=true

# Set the rw type list for fio test
RW="read write rw"

# Set the read percentage list for fio test in mixed read/write workloads
READ_PERCENT="10 50 90"

# Set the bs list for fio test or
BS="4k 1m"

# Set the io depth list for fio test or
IO_DEPTH="64 1024"

# Set the numjobs list for fio test
FIO_NUMJOB="1"

# Set the test time for fio test or
TEST_DURATION=30

declare -A RDMA_DEV_MAP
declare -A PF_MAP

TIME_STR=$(date '+%Y%m%d_%H%M%S')
TEST_RES_SUB_DIR="${TEST_RESULT_DIR}/${TEST_SUB_DIR_PREFIX}_${TIME_STR}"


print_help() {
    cat << EOF
$SPLIT_LINE
Setup or teardown the configuration of kernel iSER initiator.

Usage:
    $0 -h or $0 help or $0 --help
    or
    $0 action=<setup or teardown> rib_drv=<rib driver path> load_drv=<whether to load rib \
driver(true/false)> tos=<tos value for each function> set_pfc=<whether to set pfc(true/false)> dev_type=<device \
type(rib/mlx)> func=<test function index> tgt_ip=<target ip list> init_ip=<initiator ip list> ip_mask=<ip mask length> \
mtu=<interface mtu> tgt_port=<target port list> disk_count=<disk count for each function> \
res_dir=<test result file dir> dir_prefix=<sub dir name prefix> fio_test=<whether to execute fio test(true/false)> \
rw=<rw list> read_percent=<read percentage list> bs=<bs list> io_depth=<io_depth list> numjobs=<numjobs list> \
duration=<test duration>

Arguments:
    action:                the action of running this script(setup/teardown), default is $ACTION.

    rib_drv:               the rib driver path, default is $RIB.

    load_drv:              whether to load rdma driver before setup kernel iser, default is $LOAD_DRV

    tos:                   the tos value for each function, default value is $TOS_VAL.

    set_pfc:               whether to configure pfc, the default is $SET_PFC.

    dev_type:              test device type(rib: use resnics device. mlx: use Mellanox device), default is $DEV_TYPE.

    func:                  the function index list to test, a string of one or multiple function index, which are 
                           seperated by space. function index format is as: pf0, pf1, pf0vf0, pf1vf14..., such 
                           as "pf0 pf1", "pf0 pf0vf0". default is "$FUNCTIONS".

    tgt_ip:                target ip addresses,  a string of one or multiple ip addresses, which are seperated by space. 
                           the ip addresses number should equal to that of the function index list, default is "$TGT_IP".

    init_ip:               initiator ip addresses,  a string of one or multiple ip addresses, which are seperated by 
                           space. the ip addresses number should equal to that of the function index list, 
                           default is "$INIT_IP".

    ip_mask:               mask length for ip addresses, a integer number range from 0 to 32. default value is $IP_MASK.

    mtu:                   MTU value for net interfaces, default value is $MTU.

    tgt_port:              target initial port of each function for kernel iser to listen to, a string of one or 
                           multiple port number, which are seperated by space. For the reason that there may be multiple
                           nmve disk count for each function, each iser disk will occupy a port number, the gap between 
                           each port should larger than the value of DISK_CNT. default is "$TGT_PORT".

    nvme_count:            iser disk count for each function index, default value is $DISK_CNT.

    res_dir:               the directory for fio result file to save to. default is $TEST_RESULT_DIR.
    
    dir_prefix:            the prefix for sub test result dir. default is $TEST_SUB_DIR_PREFIX.

    fio_test:              whether to execute fio test after setup spdk initiator. default is $FIO_TEST.

    rw:                    rw type list for fio test. such as "read write rw". defautl is $RW.

    read_percent:          read percentage list for fio test in mixed read/write workloads, such as "10 20 30". 
                           default is "$READ_PERCENT".

    bs:                    bs list for fio test. such as "4k 1m". defautl is $BS.

    io_depth:              io_depth list for fio test. such as "64 128". defautl is $IO_DEPTH.

    numjobs:               numjobs list for fio test. such as "1 2 4". default is $FIO_NUMJOB.

    duration:              test duration for fio test. default is $TEST_DURATION.

Examples:
    Setup kernel iser initiator with default value for every parameters.
        bash $0

    Setup kernel iser initiator and fio test parameters:
        bash $0 func="pf0 pf0vf0 pf1 pf1vf0" tgt_ip="10.0.0.1 11.0.0.1 12.0.0.1 13.0.0.1" \
init_ip="10.0.0.2 11.0.0.2 12.0.0.2 13.0.0.2" tgt_port="4420 4430 4440 4450" fio_test=true rw="read write rw" \
bs="4k 1m" io_depth="64 1024" numjobs="1 8 16" duration=300

    Clear all configurations of kernel iser initiator:
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
		init_ip=*)
			INIT_IP="${arg#*=}"
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
		disk_count=*)
			DISK_CNT="${arg#*=}"
			;;
		res_dir=*)
			TEST_RESULT_DIR="${arg#*=}"
			;;
		dir_prefix=*)
			TEST_SUB_DIR_PREFIX="${arg#*=}"
			;;
		fio_test=*)
			FIO_TEST="${arg#*=}"
			;;
		rw=*)
			RW="${arg#*=}"
			;;
        read_percent=*)
            READ_PERCENT="${arg#*=}"
            ;;
		bs=*)
			BS="${arg#*=}"
			;;
		io_depth=*)
			IO_DEPTH="${arg#*=}"
			;;
		numjobs=*)
			FIO_NUMJOB="${arg#*=}"
			;;
		duration=*)
			TEST_DURATION="${arg#*=}"
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
IFS=' ' read -r -a INIT_IP_LIST <<< "$INIT_IP"
IFS=' ' read -r -a TGT_PORT_LIST <<< "$TGT_PORT"

IFS=' ' read -r -a RW_LIST <<< "$RW"
IFS=' ' read -r -a READ_PERCENT_LIST <<< "$READ_PERCENT"
IFS=' ' read -r -a BS_LIST <<< "$BS"
IFS=' ' read -r -a IO_DEPTH_LIST <<< "$IO_DEPTH"
IFS=' ' read -r -a FIO_NUMJOB_LIST <<< "$FIO_NUMJOB"


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

# load_rdma_drv() {
#     # load_mods
#     load_rib_mod
#     sleep 2
# }

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
    local tgt_ip=${TGT_IP_LIST[$idx]}
    local init_ip=${INIT_IP_LIST[$idx]}
    local port=${TGT_PORT_LIST[$idx]}
    local fc_info="$func_id $ib_dev $net_dev $tgt_ip $init_ip $port"
    if [ "$DEV_TYPE" == "rib" ]; then
        local rib_dev=${ib_dev/_/c}
        fc_info="$func_id $ib_dev $net_dev $tgt_ip $init_ip $port $rib_dev"
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
            IFS=' ' read -r fcid ib_dev iface tgt_ip init_ip tgt_port rib_dev <<< "${RDMA_DEV_MAP[$fc]}"
        fi
        if [ "$DEV_TYPE" == "mlx" ]; then
            IFS=' ' read -r fcid ib_dev iface tgt_ip init_ip tgt_port <<< "${RDMA_DEV_MAP[$fc]}"
        fi
        echo "PCIe function ID:  $fcid"
        echo "IB device       :  $ib_dev"
        echo "Net interface   :  $iface"
        echo "Target IP       :  $tgt_ip"
        echo "Initiator IP    :  $init_ip"
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

test_setup() {
    echo "Setup steps before test..."
    local idx=0
    for fc in ${FUNC_LIST[@]}; do
        if [ "$DEV_TYPE" == "rib" ]; then
            IFS=' ' read -r fcid ib_dev iface tgt_ip init_ip tgt_port rib_dev <<< "${RDMA_DEV_MAP[$fc]}"
        fi
        if [ "$DEV_TYPE" == "mlx" ]; then
            IFS=' ' read -r fcid ib_dev iface tgt_ip init_ip tgt_port <<< "${RDMA_DEV_MAP[$fc]}"
        fi
        set_interface_ip $iface $init_ip
        echo $SPLIT_LINE
        if [ "$DEV_TYPE" == "rib" ]; then
            set_tos $rib_dev $TOS_VAL
            echo $SPLIT_LINE
            if [ "$SET_PFC" == "true" ]; then
                apply_init_dcqcn_paras $rib_dev
                echo $SPLIT_LINE
                set_pfc  $rib_dev
                echo $SPLIT_LINE
            fi
        fi
        idx=$(($idx+1))
    done

    if [ ! -d "$TEST_RESULT_DIR" ]; then
        mkdir -p "$TEST_RESULT_DIR"
    fi
    mkdir -p "$TEST_RES_SUB_DIR"

}

logout_all_session() {
    echo "Logout all iser session."
    iscsiadm -m session --logout
}

get_portal_list() {
    local portal_list=()
    for i in "${!TGT_IP_LIST[@]}"; do
        local t_ip=${TGT_IP_LIST[$i]}
        local init_pt=${TGT_PORT_LIST[$i]}
        for ((j = 0; j < $DISK_CNT; j++)); do
            local pt=$((init_pt + j))
            local portal="${t_ip}:${pt}"
            portal_list+=($portal)
        done
    done
    echo "${portal_list[@]}"
}

discover_and_login_tgt() {
    logout_all_session
    echo $SPLIT_LINE
    local -n tgt_map_ref=$1
    local portals=($(get_portal_list))

    echo "Discovering iSER targets..."
    for portal in "${portals[@]}"; do
        echo "Discovering targets at $portal..."
        iscsiadm -m discovery -t st -p "$portal"
    done
    echo $SPLIT_LINE

    echo "Configuring iSER transport and logging in..."
    for portal in "${portals[@]}"; do
        echo "Updating transport type to iSER for $portal..."
        iscsiadm -m node -p "$portal" -o update -n iface.transport_name -v iser
        iscsiadm -m node -p "$portal" | grep transport
        echo "Logging in to target at $portal..."
        iscsiadm -m node -p "$portal" --login
    done

    # 🔽🔽🔽 STEP 1: Login 完成后，立即插入「等待 + 主动扫描」🔽🔽🔽
    echo $SPLIT_LINE
    echo "Waiting for iSCSI devices to initialize..."
    sleep 2  # 给设备初始化留出时间（保守值，可调为 1s）

    # 主动触发所有 SCSI host 扫描（关键！）
    echo "Triggering SCSI rescan..."
    for host in /sys/class/scsi_host/host*/scan; do
        if [ -w "$host" ]; then
            echo "- - -" > "$host" 2>/dev/null || true
        fi
    done

    # 再等一下让 udev 完成设备节点创建
    sleep 1
    # 🔼🔼🔼 结束：等待 + 扫描逻辑 🔼🔼🔼

    echo $SPLIT_LINE
    echo "Checking active iSCSI sessions..."
    iscsiadm -m session
    echo $SPLIT_LINE
    echo "Checking lsblk"
    lsblk
    echo $SPLIT_LINE

    # 🔽🔽🔽 STEP 2: 改进映射逻辑，增加重试或等待机制（可选增强）🔽🔽🔽
    sessions=$(iscsiadm -m session)
    echo "Mapping iSCSI sessions to block devices..."

    # 可选：最多重试 3 次，避免偶发失败
    local retry=0
    local max_retry=3
    local mapped=false

    while [ $retry -lt $max_retry ] && [ "$mapped" = false ]; do
                mapped=true

                # ✅ 正确解析：先生成 "IQN,Portal" 列表
                for session_entry in $(echo "$sessions" | awk '{print $4","$3}'); do
                        # ✅ 从 "IQN,Portal" 中提取
                        local target_iqn=$(echo "$session_entry" | awk -F',' '{print $1}')
                        local portal_with_sid=$(echo "$session_entry" | awk -F',' '{print $2}')
                        local portal=$(echo "$portal_with_sid" | cut -d',' -f1)

                        echo "DEBUG: target_iqn = [$target_iqn], portal = [$portal]"

                        # ✅ 用 IQN 查找设备（去掉 grep -v 'ip-*-'）
                        local device=$(ls -l /dev/disk/by-path/ 2>/dev/null | \
                                grep -F "$target_iqn" | \
                                grep -E 'lun-[0-9]+' | \
                                awk '{print $NF}' | \
                                sed 's|\.\./\.\./||' | \
                                head -1)

                        if [ -n "$device" ] && [ -b "/dev/$device" ]; then
                                tgt_map_ref["$target_iqn"]="/dev/$device"
                                echo "Mapped $target_iqn -> /dev/$device"
                        else
                                echo "Warning: Failed to map $target_iqn, retrying..."
                                mapped=false
                        fi
                done

        if [ "$mapped" = false ]; then
            retry=$((retry + 1))
            sleep 1
            # 重新获取 session（可能因重试变化）
            sessions=$(iscsiadm -m session)
        fi
    done

    if [ $retry -ge $max_retry ] && [ "$mapped" = false ]; then
        echo "Error: Failed to map all iSCSI devices after $max_retry retries."
        return 1
    fi
    # 🔼🔼🔼 结束：增强映射逻辑 🔼🔼🔼
}

# get_iser_disk() {
#     local -n tgt_map_refer=$1
#     local portals=($(get_portal_list))
#     local iser_disk_list=""
#     for portal in "${portals[@]}"; do
#         local disk_dev="/dev/${tgt_map_refer[$portal]}"
#         if [ -n $iser_disk_list ]; then
#             iser_disk_list="${iser_disk_list}:${disk_dev}"
#         else
#             iser_disk_list="${disk_dev}"
#         fi
#     done
#     iser_disk_list=$(echo $iser_disk_list | sed 's/^://')
#     echo $iser_disk_list
# }

get_iser_disk() {
    local -n tgt_map_ref=$1
    local devices=()
    # 直接遍历 map 的所有值（即 /dev/sdb, /dev/sdc）
    for dev in "${tgt_map_ref[@]}"; do
        devices+=("$dev")
    done
    # 用 : 拼接
    IFS=:; echo "${devices[*]}"
}

create_table_line() {
    local length=$1
    printf "%-${length}s" " " | tr ' ' '-'
}

parse_fio_result() {
    local res_dir=$1
    local res_file=$2
    header="RW          BS          IO_DEPTH     NUMJOBS      RWMIXREAD    READ IOPS          READ BW (MiB/s)    READ AVG LATENCY (usec)        WRITE IOPS         WRITE BW (MiB/s)   WRITE AVG LATENCY (usec)"
    header_line=$(printf "%-${#header}s" " " | tr ' ' '-')

    {
        echo "$header_line"
        printf "%-12s %-12s %-12s %-12s %-12s %-18s %-18s %-26s %-18s %-18s %-26s\n" "RW" "BS" "IO_DEPTH" "NUMJOBS" "RWMIXREAD" "READ IOPS" "READ BW (MiB/s)" "READ AVG LATENCY (usec)" "WRITE IOPS" "WRITE BW (MiB/s)" "WRITE AVG LATENCY (usec)"
        echo "$header_line"

        for json_file in "$res_dir"/*.json; do
            jq -r '
            . as $json |
            "\($json["global options"].rw) \($json["global options"].bs) \($json["global options"].iodepth) \($json["global options"].numjobs) \($json.jobs[0]["job options"].rwmixread // "N/A") \($json.jobs[0].read.iops) \($json.jobs[0].read.bw / 1024) \($json.jobs[0].read.lat_ns.mean / 1000) \($json.jobs[0].write.iops) \($json.jobs[0].write.bw / 1024) \($json.jobs[0].write.lat_ns.mean / 1000)"
            ' "$json_file" | while read -r line; do
                printf "%-12s %-12s %-12s %-12s %-12s %-18.2f %-18.2f %-26.2f %-18.2f %-18.2f %-26.2f\n" $line
            done
        done
        echo "$header_line"
    } | tee "$res_file"
}

fio_test() {
    local fio_echo="${TEST_RES_SUB_DIR}/fio_test.echo"
    local fio_res_file="${TEST_RES_SUB_DIR}/fio_res.txt"
    touch $fio_echo
    touch $fio_res_file
    local -n t_map_ref=$1
    local dev_list_str=$(get_iser_disk t_map_ref)
    echo "Fio test dev list: $dev_list_str"
    echo "$SPLIT_LINE"
    for rw_type in ${RW_LIST[@]}; do
        for bs in ${BS_LIST[@]}; do
            for io_dpt in ${IO_DEPTH_LIST[@]}; do
                for njob in ${FIO_NUMJOB[@]}; do
                    if [[ "$rw_type" == "rw" || "$rw_type" == "randrw" ]]; then
                        for read_pct in ${READ_PERCENT_LIST[@]}; do
                            echo $SPLIT_LINE >> $fio_echo
                            local res_json_filename="fio_rw_${rw_type}_rwmixread_${read_pct}_bs_${bs}_iodepth_${io_dpt}_numjobs_${njob}.json"
                            local res_json="${TEST_RES_SUB_DIR}/$res_json_filename"
                            fio_cmd="fio -filename=$dev_list_str -rw=$rw_type -bs=$bs -iodepth=$io_dpt -numjobs=$njob \
-runtime=$TEST_DURATION -ioengine=libaio -direct=1 -thread=1 -group_reporting -name=fio_test -norandommap -time_based \
-iodepth_batch=16 -iodepth_batch_complete=32 --rwmixread=$read_pct --output-format=json --output=$res_json"
                            echo "fio test cmd:" >> $fio_echo
                            echo "$fio_cmd" >> $fio_echo
                            echo "TEST PARAMETERS: RW: $rw_type, BS: $bs, IO_DEPTH: $io_dpt, NUMJOBS: $njob, RWMIXREAD: $read_pct" >> $fio_echo
                            echo "" >> $fio_echo
                            echo "fio test cmd:"
                            echo "$fio_cmd"
                            echo "$SPLIT_LINE"
                            echo "Start FIO test."
                            echo "TEST PARAMETERS: RW: $rw_type, BS: $bs, IO_DEPTH: $io_dpt, NUMJOBS: $njob, RWMIXREAD: $read_pct"
                            eval "$fio_cmd" | tee -a $fio_echo
                            echo "$SPLIT_LINE"
                            echo $SPLIT_LINE >> $fio_echo
                        done
                    else
                        echo $SPLIT_LINE >> $fio_echo
                        local res_json_filename="fio_rw_${rw_type}_bs_${bs}_iodepth_${io_dpt}_numjobs_${njob}.json"
                        local res_json="${TEST_RES_SUB_DIR}/$res_json_filename"
                        fio_cmd="fio -filename=$dev_list_str -rw=$rw_type -bs=$bs -iodepth=$io_dpt -numjobs=$njob \
-runtime=$TEST_DURATION -ioengine=libaio -direct=1 -thread=1 -group_reporting -name=fio_test -norandommap -time_based \
-iodepth_batch=16 -iodepth_batch_complete=32 --output-format=json --output=$res_json"
                        echo "fio test cmd:" >> $fio_echo
                        echo "$fio_cmd" >> $fio_echo
                        echo "TEST PARAMETERS: RW: $rw_type, BS: $bs, IO_DEPTH: $io_dpt, NUMJOBS: $njob" >> $fio_echo
                        echo "" >> $fio_echo
                        echo "fio test cmd:"
                        echo "$fio_cmd"
                        echo "$SPLIT_LINE"
                        echo "Start FIO test."
                        echo "TEST PARAMETERS: RW: $rw_type, BS: $bs, IO_DEPTH: $io_dpt, NUMJOBS: $njob"
                        eval "$fio_cmd" | tee -a $fio_echo
                        echo "$SPLIT_LINE"
                        echo $SPLIT_LINE >> $fio_echo
                    fi
                done
            done
        done
    done
    parse_fio_result $TEST_RES_SUB_DIR $fio_res_file
}

clear_interface_ip() {
    ifaces=$(rdma link |grep $DEV_TYPE | awk '/netdev/ {print $NF}')
    for iface in $ifaces; do
        echo "Flushing IP addresses for interface $iface"
        ip addr flush dev $iface
    done
}

teardown() {
    logout_all_session
    echo $SPLIT_LINE
    clear_interface_ip
}

main() {
    check_action
    start_time=$(date +%s)
    start_readable=$(date)
    echo $SPLIT_LINE
    if [ "$ACTION" == "teardown" ]; then
        teardown
        echo $SPLIT_LINE
        exit 0
    fi
    echo $SPLIT_LINE
    echo "Script started at: $start_readable"
    echo "Time str    :  $TIME_STR"
    echo "Test sub dir:  $TEST_RES_SUB_DIR"
    echo $SPLIT_LINE
    load_mods
    echo $SPLIT_LINE
    logout_all_session
    echo $SPLIT_LINE
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
    check_sriov pf_map
    echo $SPLIT_LINE
    get_test_func_map pf_map
    echo $SPLIT_LINE
    print_test_info
    echo $SPLIT_LINE
    test_setup
    declare -A tgt_map
    discover_and_login_tgt tgt_map
    if [ ${#tgt_map[@]} -eq 0 ]; then
        echo "Discover and login target failed!"
        exit 1
    fi
    echo $SPLIT_LINE
    echo "Discovered and login target info:"
    for key in "${!tgt_map[@]}"; do
        echo "$key --> ${tgt_map[$key]}"
    done
    echo $SPLIT_LINE
    if [ "$FIO_TEST" == true ]; then
        echo $SPLIT_LINE
        fio_test tgt_map
        echo $SPLIT_LINE
    fi

    end_time=$(date +%s)
    end_readable=$(date)
    echo "Script ended at: $end_readable"
    elapsed_time=$((end_time - start_time))
    hours=$((elapsed_time / 3600))
    minutes=$(( (elapsed_time % 3600) / 60 ))
    seconds=$((elapsed_time % 60))
    echo "Total elapsed time: ${hours}h:${minutes}m:${seconds}s"
}

main
