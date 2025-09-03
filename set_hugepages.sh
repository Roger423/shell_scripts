#!/bin/bash

# 检查是否提供了参数
if [ -z "$1" ]; then
    echo "Usage: $0 <number_of_hugepages>"
    exit 1
fi

# 获取输入的HugePages数量
num_hugepages=$1

# 设置HugePages数量
echo "Setting HugePages to $num_hugepages"
sudo sysctl -w vm.nr_hugepages=$num_hugepages

# 验证设置是否成功
echo "Current HugePages configuration:"
grep Huge /proc/meminfo

echo "Done."
