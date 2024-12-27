#!/bin/bash

# 定义设备的IP地址、用户名和密码
declare -A DEVICE_INFO
DEVICE_INFO[m6]="192.168.64.135 sys Resnics@123"
DEVICE_INFO[m5]="192.168.64.142 root a"
DEVICE_INFO[s1]="192.168.64.149 admin resnics@123"

# 获取设备信息函数
get_device_info() {
    local device=$1
    IFS=' ' read -r ip user pass <<< "${DEVICE_INFO[$device]}"
    echo "$ip $user $pass"
}

# 检查输入参数
if [ $# -ne 4 ]; then
    echo "Usage: $0 -d <device_name> -a <action>"
    exit 1
fi

# 解析输入参数
while getopts "d:a:" opt; do
    case $opt in
        d) DEVICE_NAME=$OPTARG ;;
        a) ACTION=$OPTARG ;;
        *) echo "Invalid option"; exit 1 ;;
    esac
done

# 获取设备信息
device_info=$(get_device_info $DEVICE_NAME)
if [ -z "$device_info" ]; then
    echo "Invalid device name: $DEVICE_NAME"
    exit 1
fi

IFS=' ' read -r IP USER PASS <<< "$device_info"

# 执行对应的ipmitool命令
case $ACTION in
    cycle)
        ipmitool -I lanplus -H $IP -U $USER -P $PASS power cycle
        ;;
    status)
        ipmitool -I lanplus -H $IP -U $USER -P $PASS power status
        ;;
    on)
        ipmitool -I lanplus -H $IP -U $USER -P $PASS power on
        ;;
    off)
        ipmitool -I lanplus -H $IP -U $USER -P $PASS power off
        ;;
    *)
        echo "Invalid action: $ACTION"
        exit 1
        ;;
esac
