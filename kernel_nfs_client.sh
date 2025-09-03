#!/bin/bash

SPLIT_LINE="-----------------------------------------------------------------------------------------------------------"

# Set the action for kernel nfs client, should be "setup"(setup configuration for kernel nfs), or "teardown"(clear all 
# kernel nfs configurations)
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

# Set dev index to use for kernel nfs test, pf index start at 0, vf index of each pf start at 0.
# pf: pf0, pf1, pf2...
# vf: pf0vf0, pf0vf1, pf1vf0, pf1vf2...
FUNCTION="pf0"

# Set the server IP address for net device that corresponding to rdma device to use
SRV_IP="10.0.0.1"

# Set the client IP address for net device that corresponding to rdma device to use
CLT_IP="10.0.0.2"

# Set the port of kernel nfs corresponding to each IP address in 'SRV_IP'
SRV_PORT="20049"

# Set the count of NFS files for function device in 'FUNCTION'
NFS_CNT=2

# Set IP mask for IP address in 'SRV_IP'
IP_MASK=16

# Set the MTU for net device that corresponding to rdma devices
MTU=4200

# Set the fio software path
FIO_PATH=/opt/fio/fio

# Set the directory for fio result file to save to.
TEST_RESULT_DIR=/home/test_result/

# Set the prefix for sub test result dir
TEST_SUB_DIR_PREFIX="Test"

# Whether to execute fio test after setup kernel nfs client
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
Setup or teardown the configuration of kernel NVMe-of initiator.

Usage:
    $0 -h or $0 help or $0 --help
    or
    $0 action=<setup or teardown> rib_drv=<rib driver path> load_drv=<whether to load rib \
driver(true/false)> tos=<tos value for each function> set_pfc=<whether to set pfc(true/false)> dev_type=<device \
type(rib/mlx)> func=<test function index> srv_ip=<target ip list> clt_ip=<initiator ip list> ip_mask=<ip mask length> \
mtu=<interface mtu> srv_port=<target port list> nfs_count=<nfs file count for each function> \
res_dir=<test result file dir> dir_prefix=<sub dir name prefix> fio_test=<whether to execute fio test(true/false)> \
rw=<rw list> read_percent=<read percentage list> bs=<bs list> io_depth=<io_depth list> numjobs=<numjobs list> \
duration=<test duration>

Arguments:
    action:                the action of running this script(setup/teardown), default is $ACTION.

    rib_drv:               the rib driver path, default is $RIB.

    load_drv:              whether to load rdma driver before setup kernel nvme-of, default is $LOAD_DRV

    tos:                   the tos value for each function, default value is $TOS_VAL.

    set_pfc:               whether to configure pfc, the default is $SET_PFC.

    dev_type:              test device type(rib: use resnics device. mlx: use Mellanox device), default is $DEV_TYPE.

    func:                  the function index list to test, a string of one function index. function index format is 
                           as: pf0, pf1, pf0vf0, pf1vf14..., default is "$FUNCTION".

    srv_ip:                server ip addresses, default is "$SRV_IP".

    clt_ip:                client ip addresses, default is "$CLT_IP".

    ip_mask:               mask length for ip addresses, a integer number range from 0 to 32. default value is $IP_MASK.

    mtu:                   MTU value for net interfaces, default value is $MTU.

    srv_port:              server port of each function for kernel NFS to listen to, default is "$SRV_PORT".

    nfs_count:             NFS file count for each function index, default value is $NFS_CNT.

    res_dir:               the directory for spdk nvme perf test and fio result file to save to. default is 
                           $TEST_RESULT_DIR.
    
    dir_prefix:            the prefix for sub test result dir. default is $TEST_SUB_DIR_PREFIX.

    fio_test:              whether to execute fio test after setup spdk initiator. default is $FIO_TEST.

    rw:                    rw type list for spdk nvme perf test and fio test. such as "read write rw". defautl is $RW.

    read_percent:          read percentage list for fio test in mixed read/write workloads, such as "10 20 30". 
                           default is "$READ_PERCENT".

    bs:                    bs list for spdk nvme perf test and fio test. such as "4k 1m". defautl is $BS.

    io_depth:              io_depth list for spdk nvme perf test and fio test. such as "64 128". defautl is $IO_DEPTH.

    numjobs:               numjobs list for fio test. such as "1 2 4". default is $FIO_NUMJOB.

    duration:              test duration for spdk nvme perf test and fio test. default is $TEST_DURATION.

Examples:
    Setup kernel NFS client with default value for every parameters.
        bash $0

    Setup kernel NFS client with specified func, ip, and port, and fio test parameters:
        bash $0 func="pf0" srv_ip="10.0.0.1" clt_ip="10.0.0.2" srv_port="20049" fio_test=true rw="read write rw" \
bs="4k 1m" io_depth="64 1024" numjobs="1 8 16" duration=300
        bash $0 func="pf0vf0" srv_ip="10.0.0.1" clt_ip="10.0.0.2" srv_port="20049" fio_test=true rw="read write rw" \
bs="4k 1m" io_depth="64 1024" numjobs="1 8 16" duration=300

    Clear all configurations of kernel nfs client:
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
		clt_ip=*)
			CLT_IP="${arg#*=}"
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
			NVME_CNT="${arg#*=}"
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

check_action() {
    if [ "$ACTION" != "setup" ] && [ "$ACTION" != "teardown" ]; then
        echo "Invalid action: $ACTION. Should be \"setup\" or \"teardown\""
        exit 1
    fi
}

IFS=' ' read -r -a FUNC_LIST <<< "$FUNCTION"
IFS=' ' read -r -a SRV_IP_LIST <<< "$SRV_IP"
IFS=' ' read -r -a CLT_IP_LIST <<< "$CLT_IP"
# IFS=' ' read -r -a SRV_PORT_LIST <<< "$SRV_PORT"

IFS=' ' read -r -a RW_LIST <<< "$RW"
IFS=' ' read -r -a READ_PERCENT_LIST <<< "$READ_PERCENT"
IFS=' ' read -r -a BS_LIST <<< "$BS"
IFS=' ' read -r -a IO_DEPTH_LIST <<< "$IO_DEPTH"
IFS=' ' read -r -a FIO_NUMJOB_LIST <<< "$FIO_NUMJOB"


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
    sleep 2
    echo "Load rib driver..."
    insmod $RIB
    sleep 2
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
    local srv_ip=${SRV_IP_LIST[$idx]}
    local clt_ip=${CLT_IP_LIST[$idx]}
    local port=${SRV_PORT}
    local fc_info="$func_id $ib_dev $net_dev $srv_ip $clt_ip $port"
    if [ "$DEV_TYPE" == "rib" ]; then
        local rib_dev=${ib_dev/_/c}
        fc_info="$func_id $ib_dev $net_dev $srv_ip $clt_ip $port $rib_dev"
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
            IFS=' ' read -r fcid ib_dev iface s_ip c_ip s_port rib_dev <<< "${RDMA_DEV_MAP[$fc]}"
        fi
        if [ "$DEV_TYPE" == "mlx" ]; then
            IFS=' ' read -r fcid ib_dev iface s_ip c_ip s_port <<< "${RDMA_DEV_MAP[$fc]}"
        fi
        echo "PCIe function ID:  $fcid"
        echo "IB device       :  $ib_dev"
        echo "Net interface   :  $iface"
        echo "Target IP       :  $s_ip"
        echo "Initiator IP    :  $c_ip"
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

test_setup() {
    echo "Setup steps before test..."
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
    done

    if [ ! -d "$TEST_RESULT_DIR" ]; then
        mkdir -p "$TEST_RESULT_DIR"
    fi
    mkdir -p "$TEST_RES_SUB_DIR"

}

get_server_export_list() {
    local srv_exp_list=()
    showmount_output=$(showmount -e $SRV_IP)
    while read -r line; do
        case "$line" in
            *'Export list for'*)
                continue
                ;;
            *'/mnt/'*)
                exp_dir=$(echo "$line" | awk '{print $1}')
                srv_exp_list+=($exp_dir)
                ;;
        esac
    done <<< $showmount_output
    revised_list=$(printf "%s\n" "${srv_exp_list[@]}" | sort | uniq)
    echo $revised_list
}

mount_nfs() {
    echo "Get export dir list of nfs server"
    srv_export_list=($(get_server_export_list))
    echo "server export list: $srv_export_list"
    local mt_sub_dir="/home/nfs_$TIME_STR"
    mkdir -p $mt_sub_dir
    for exp_dir in ${srv_export_list[@]}; do
        echo "Mount $SRV_IP:$exp_dir to local dir: $mt_sub_dir"
        local mt_cmd="mount -t nfs $SRV_IP:$exp_dir $mt_sub_dir -o rdma,port=$SRV_PORT"
        echo "Mount CMD: $mt_cmd"
        $mt_cmd
        echo "Check mount result:"
        local ck_output=$(mount |grep "$mt_sub_dir")
        echo "$ck_output"
    done
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
    # local -n dev_map_ref=$1
    # local fios_file_list=$(find "/home/nfs_$TIME_STR" -type l | paste -sd ":" -)
    local fios_file_list=$(find "/home/nfs_$TIME_STR" \( -type l -o -type f \) | paste -sd ":" -)
    echo "Fio file list: $fios_file_list"
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
                            fio_cmd="fio -filename=$fios_file_list -rw=$rw_type -bs=$bs -iodepth=$io_dpt -numjobs=$njob \
-runtime=$TEST_DURATION -size=1G -ioengine=libaio -direct=1 -thread=1 -group_reporting -name=fio_test -norandommap \
-time_based -iodepth_batch=16 -iodepth_batch_complete=32 --rwmixread=$read_pct --output-format=json --output=$res_json"
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
                        fio_cmd="fio -filename=$fios_file_list -rw=$rw_type -bs=$bs -iodepth=$io_dpt -numjobs=$njob \
-runtime=$TEST_DURATION -size=1G -ioengine=libaio -direct=1 -thread=1 -group_reporting -name=fio_test -norandommap \
-time_based -iodepth_batch=16 -iodepth_batch_complete=32 --output-format=json --output=$res_json"
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

# umount_nfs() {
#     echo "umount nfs server file ..."
#     umount ${SRV_IP}:/home/nfs_$TIME_STR
# }

umount_nfs() {
    echo "Get export dir list of nfs server"
    srv_export_list=($(get_server_export_list))
    echo "server export list: $srv_export_list"
    # local mt_sub_dir="/home/nfs_$TIME_STR"
    # mkdir -p $mt_sub_dir
    for exp_dir in ${srv_export_list[@]}; do
        echo "Umount $SRV_IP:$exp_dir"
        local umt_cmd="umount $SRV_IP:$exp_dir"
        echo "Umount CMD: $umt_cmd"
        $umt_cmd
    done
    echo "Check umount result:"
    mount
}

teardown() {
    umount_nfs
    clear_interface_ip
    rm -rf "/home/nfs_$TIME_STR"
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
    mount_nfs
    sleep 2
    echo $SPLIT_LINE
    if [ "$FIO_TEST" == true ]; then
        echo $SPLIT_LINE
        fio_test
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
