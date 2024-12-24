#!/bin/bash

# 检查是否以root权限运行脚本
if [ "$EUID" -ne 0 ]; then
  echo "请以root权限运行此脚本。"
  exit 1
fi

# 检查是否提供了参数
if [ -z "$1" ]; then
  echo "用法: $0 <governor>"
  echo "示例: $0 performance"
  exit 1
fi

# 要设置的调频策略
GOVERNOR=$1

# 遍历所有CPU核
for CPU_PATH in /sys/devices/system/cpu/cpu[0-9]*; do
  SCALING_GOVERNOR_PATH="$CPU_PATH/cpufreq/scaling_governor"

  # 检查scaling_governor文件是否存在
  if [ -f "$SCALING_GOVERNOR_PATH" ]; then
    # 设置调频策略
    echo "$GOVERNOR" > "$SCALING_GOVERNOR_PATH"

    # 验证设置是否成功
    CURRENT_GOVERNOR=$(cat "$SCALING_GOVERNOR_PATH")
    if [ "$CURRENT_GOVERNOR" == "$GOVERNOR" ]; then
      echo "成功将 $SCALING_GOVERNOR_PATH 设置为 $GOVERNOR。"
    else
      echo "未能将 $SCALING_GOVERNOR_PATH 设置为 $GOVERNOR。"
    fi
  else
    echo "找不到 $SCALING_GOVERNOR_PATH 文件。跳过 $CPU_PATH。"
  fi
done
