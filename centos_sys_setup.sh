#!/bin/bash

# 更新YUM源为阿里YUM源
update_yum_sources() {
    echo "更新YUM源为阿里YUM源..."
    cd /etc/yum.repos.d
    sed -i.bak \
        -e 's|^mirrorlist=|#mirrorlist=|' \
        -e 's|^#baseurl=|baseurl=|' \
        -e 's|http://mirror.centos.org|https://mirrors.aliyun.com|' \
        /etc/yum.repos.d/CentOS-*.repo

    sed -i 's/enabled=0/enabled=1/' /etc/yum.repos.d/CentOS-Linux-PowerTools.repo

    dnf makecache
}

# 升级libmodulemd
upgrade_libmodulemd() {
    echo "升级libmodulemd..."
    dnf upgrade libmodulemd -y
}

# 配置EPEL源
configure_epel() {
    echo "配置EPEL源..."
    dnf install epel-release -y

    sed -i.bak \
        -e 's|^metalink|#metalink|' \
        -e 's|^#baseurl=|baseurl=|' \
        -e 's|download.example/pub|mirrors.aliyun.com|' \
        /etc/yum.repos.d/epel*.repo

    dnf makecache
}

set_yum() {
    update_yum_sources
    upgrade_libmodulemd
    configure_epel
}

# 设置时区
set_timezone() {
    echo "设置时区..."
    timedatectl set-timezone Asia/Shanghai
}

# 设置时间同步
set_ntp() {
    echo "设置时间同步..."
    sudo timedatectl set-ntp true
    timedatectl status
}

# 安装开发工具包
install_dev_tools() {
    echo "安装开发工具包..."
    dnf groupinstall -y "Development Tools"
}

# 取消git安全验证
disable_git_ssl_verify() {
    echo "取消git安全验证..."
    git config --global http.sslVerify false
}

# 修改pip源
configure_pip() {
    echo "修改pip源..."
    mkdir -p ~/.pip/
    cat <<EOF > ~/.pip/pip.conf
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
EOF
}

# 主函数，调用所有封装好的函数
main() {
    set_yum
    set_timezone
    set_ntp
    install_dev_tools
    disable_git_ssl_verify
    configure_pip
    echo "所有操作完成。"
}

# 执行主函数
main
