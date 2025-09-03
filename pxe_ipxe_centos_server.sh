#!/bin/bash

SPLIT_LINE="-----------------------------------------------------------------------------------------------------------"
iface=""
iso_image_path="/home/CentOS-8.4.2105-x86_64-dvd1.iso"
srv_ip="10.0.0.1"
srv_ip6="2023::1"
act=""
tftp_root="/var/lib/tftpboot"
mt_dir="/var/www/html/CentOS"

function print_help {
    echo "$SPLIT_LINE"
    cat <<EOF
Usage:
    pxe_ipxe_centos_server.sh interface=<interface name> action=<server action>
    or
    pxe_ipxe_centos_server.sh interface=<interface name> action=<server action> server_ip=<server ip>
    or
    pxe_ipxe_centos_server.sh interface=<interface name> action=<server action> server_ip=<server ip> 
                              server_ip6=<server ipv6>
    or
    pxe_ipxe_centos_server.sh interface=<interface name> action=<server action> server_ip=<server ip> 
                              server_ip6=<server ipv6> image_iso=<system image iso file path>

Arguments:
    help|-h|--help:    Print this help info.
    interface:         The interface to use on pxe/ipxe server for client to connect to. Mandatory argument.
    action:            The action of pxe/ipxe server, "install" or "start", "install" is to install all needed software 
                       and service, "start" is to only to start all service of pxe/ipxe server. Mandatory argument.
    server_ip:         The IPv4 address of pxe/ipxe server, optional argument, default value is $srv_ip
    server_ip6:        The IPv6 address of pxe/ipxe server, optional argument, default value is $srv_ip6, IPv6 address 
                       should be the form of <head::tail>, such as 2010::1 
    image_iso:         The path of system image iso file for pxe/ipxe client to boot from, optional argument, 
                       default value is $iso_image_path, make sure that the file exists.

Examples:
    # specify only interface and action:
    pxe_ipxe_centos_server.sh interface=eth0 action=install

    # specify interface, action and ipv4 address:
    pxe_ipxe_centos_server.sh interface=eth0 action=start server_ip=10.0.100.1

    # specify interface, action, ipv4 address and iso file path:
    pxe_ipxe_centos_server.sh interface=eth0 action=start server_ip=10.0.100.1 
                              image_iso=/home/CentOS-8.4.2105-x86_64-dvd1.iso

    # specify interface action, and ipv4/ipv6 address:
    pxe_ipxe_centos_server.sh interface=eth0 action=start server_ip=10.0.100.1 server_ip6=2001::1
EOF
    echo "$SPLIT_LINE"
}

function get_args {
    for arg in "$@"
    do
        case $arg in
            interface=*)
                iface="${arg#*=}"
                ;;
            server_ip=*)
                srv_ip="${arg#*=}"
                ;;
            server_ip6=*)
                srv_ip6="${arg#*=}"
                ;;
            action=*)
                act="${arg#*=}"
                ;;
            image_iso=*)
                iso_image_path="${arg#*=}"
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

    if [[ -z "$iface" ]]; then
        echo $SPLIT_LINE
        echo "Error: Interface must be specified."
        print_help
        exit 1
    fi
    if [[ -z "$act" ]]; then
        echo $SPLIT_LINE
        echo "Error: Action must be specified."
        print_help
        exit 1
    fi
    if [[ ! -e "$iso_image_path" ]]; then
        echo $SPLIT_LINE
        echo "Error: ISO image file $iso_image_path not exists"
        exit 1
    fi
}

function stop_firewall {
    echo "Stop firewall ...."
    systemctl stop firewalld.service
    systemctl disable firewalld.service
}

function install_dhcp {
    echo "Check installation of DHCP service"
    if ! command -v dhcpd &> /dev/null; then
        echo "DHCP not installed, install DHCP and RA ..."
        yum install -y dhcp-server
        yum install -y radvd

        sleep 1
        if ! command -v dhcpd &> /dev/null; then
            echo "DHCP install failed"
        else
            echo "DHCP install successed"
            systemctl stop dhcpd.service
            systemctl disable dhcpd.service
            systemctl stop dhcpd6.service
            systemctl disable dhcpd6.service
        fi

        if ! command -v radvd &> /dev/null; then
            echo "radvd install failed"
        else
            echo "radvd install successed"
            systemctl stop radvd.service
            systemctl disable radvd.service
        fi
    else
        echo "DHCP has already installed"
    fi
}

function install_tftp {
    echo "Check installation of TFTP service"
    tftp_installed=$(ls /usr/lib/systemd/system/ |grep tftp > /dev/null 2>&1 && echo yes || echo no)
    if [ $tftp_installed = "no" ]; then
        echo "TFTP not installed, install TFTP and xinetd ..."
        yum install -y tftp-server xinetd

        sleep 1
        tftp_installed=$(ls /usr/lib/systemd/system/ |grep tftp > /dev/null 2>&1 && echo yes || echo no)
        if [ $tftp_installed = "no" ]; then
            echo "TFTP install failed"
        else
            echo "TFTP install successed"
            systemctl stop tftp.service
            systemctl disable tftp.service
            systemctl stop tftp.socket
            systemctl disable tftp.socket
            systemctl stop xinetd.service
            systemctl disable xinetd.service
        fi
    else
        echo "TFTP has already installed"
    fi
}

function install_http {
    echo "Check installation of HTTP service"
    http_installed=$(ls /usr/lib/systemd/system/ |grep httpd > /dev/null 2>&1 && echo yes || echo no)
    if [ $http_installed = "no" ]; then
        echo "HTTP not installed, install HTTP ..."
        yum install -y httpd

        sleep 1
        http_installed=$(ls /usr/lib/systemd/system/ |grep httpd > /dev/null 2>&1 && echo yes || echo no)
        if [ $http_installed = "no" ]; then
            echo "HTTP install failed"
        else
            echo "HTTP install successed"
            systemctl stop httpd.service
            systemctl disable httpd.service
        fi
    else
        echo "HTTP has already installed"
    fi
}

function split_srv_ip {
    org_ifs=$IFS
    IFS='.' read -r ipseg1 ipseg2 ipseg3 ipseg4 <<< "$srv_ip"
    IFS=$org_ifs
}

function split_srv_ip6 {
    org_ifs=$IFS
    IFS='::' read -r ip6seg1 ip6seg2 <<< "$srv_ip6"
    ip6seg2="${ip6seg2#*:}"
    IFS=$org_ifs
}

function check_network_manager {
    echo "Check if NetworkManager is active ..."
    nm_active=$(systemctl status NetworkManager >> /dev/null 2>&1 && echo yes || echo no)
    if [ $nm_active = "no" ]; then
        echo "NetworkManager is not active, start NetworkManager"
        systemctl start NetworkManager
    else
        echo "NetworkManager is active"
    fi
}

function config_interface_ip {
    echo "Config IP for interface $iface ..."
    has_con=$(nmcli connection show $iface > /dev/null 2>&1 && echo yes || echo no)
    if [ $has_con = "yes" ]; then
        nmcli connection delete $iface
    fi
    nmcli connection add con-name $iface type ethernet ifname $iface
    nmcli connection modify $iface ipv4.method manual ipv4.addresses $srv_ip/24
    nmcli connection modify $iface ipv6.addresses $srv_ip6/64
    nmcli connection up $iface
    ifconfig $iface
}

function get_dhcp_ip_range {
    echo "Get ip range for DHCP4 and DHCP6 ..."
    ip4_st_tail=$(($ipseg4 + 1))
    ip4_ed_tail=$(($ip4_st_tail + 50))
    ip4_rg_st="$ipseg1.$ipseg2.$ipseg3.$ip4_st_tail"
    ip4_rg_ed="$ipseg1.$ipseg2.$ipseg3.$ip4_ed_tail"
    ip6_st_tail=$(($ip6seg2 + 1))
    ip6_ed_tail=$(($ip6_st_tail + 50))
    ip6_rg_st="$ip6seg1::$ip6_st_tail"
    ip6_rg_ed="$ip6seg1::$ip6_ed_tail"
    echo "DHCP4 range: $ip4_rg_st -- $ip4_rg_ed"
    echo "DHCP6 range: $ip6_rg_st -- $ip6_rg_ed"
}

function process_ip {
    split_srv_ip
    split_srv_ip6
    check_network_manager
    echo $SPLIT_LINE
    config_interface_ip
    echo $SPLIT_LINE
    get_dhcp_ip_range
}

function set_dhcp4_config_file {
    echo "Set DHCP4 config file ..."
    ip4_subnet="$ipseg1.$ipseg2.$ipseg3.0"
    cat <<EOF > /etc/dhcp/dhcpd.conf
subnet $ip4_subnet netmask 255.255.255.0 {
    range $ip4_rg_st $ip4_rg_ed;
    option routers $srv_ip;
    next-server $srv_ip;
    if exists user-class and option user-class = "iPXE" {
        filename "ipv4.ipxe";
    } else if exists vendor-class-identifier and substring(option vendor-class-identifier, 0, 9) = "PXEClient" {
        filename "bootx64.efi";
    } else {
        filename "bootx64.efi";
    }
}
EOF
}

function set_dhcp6_config_file {
    echo "Set DHCP6 config file ..."
    ip6_subnet="$ip6seg1::"
    cat <<EOF > /etc/dhcp/dhcpd6.conf
subnet6 $ip6_subnet/64 {
    range6 $ip6_rg_st $ip6_rg_ed;
    range6 $ip6_subnet temporary;
    if exists user-class and option user-class = "iPXE" {
        filename "ipv4.ipxe";
    } else if exists vendor-class-identifier and substring(option vendor-class-identifier, 0, 9) = "PXEClient" {
        filename "bootx64.efi";
    } else {
        filename "bootx64.efi";
    }
}
EOF
}

function set_ra_config_file {
    echo "Set RA config file ..."
    if [[ ! -e "/etc/radvd.conf" ]]; then
        touch /etc/radvd.conf
    fi
    ip6_subnet="$ip6seg1::"
    cat <<EOF > /etc/radvd.conf
interface $iface
{
    AdvSendAdvert on;
    prefix $ip6_subnet/64 {
        AdvOnLink on;
        AdvAutonomous on;
    };
    RDNSS $srv_ip6{
    };
};
EOF
}

function set_tftp_config_file {
    echo "Set TFTP config file ..."
    if [[ -d "$tftp_root" ]]; then
        mkdir -p $tftp_root
    fi
    if [[ ! -e "/etc/xinetd.d/tftp" ]]; then
        touch /etc/xinetd.d/tftp
    fi
    cat <<EOF > /etc/xinetd.d/tftp
service tftp
{
        socket_type = dgram
        protocol = udp
        wait = yes
        user = root
        server = /usr/sbin/in.tftpd
        server_args = -s $tftp_root --blocksize 1468
        disable = no
        per_source = 11
        cps = 100 2
        flags = IPv4
}
EOF
}

function process_config_file {
    set_dhcp4_config_file
    set_dhcp6_config_file
    set_ra_config_file
    set_tftp_config_file
}

function mount_image_iso_file {
    echo "Mount system image iso file ..."
    if [[ ! -e "$mt_dir" ]]; then
        mkdir -p $mt_dir
    fi
    iso_filename=$(basename "$iso_image_path")
    http_iso_file_path="/var/www/html/$iso_filename"
    if [[ ! -e "$http_iso_file_path" ]]; then
        cp $iso_image_path /var/www/html/
    fi
    iso_mounted=$(mount |grep $mt_dir >> /dev/null 2>&1 && echo yes || echo no)
    if [ $iso_mounted = "no" ]; then
        mount /var/www/html/$iso_filename $mt_dir
    elif [ $iso_mounted = "yes" ]; then
        rigth_iso_file=$(mount |grep $mt_dir |grep $iso_filename > /dev/null 2>&1 && echo yes || echo no)
        if [ $rigth_iso_file = "no" ]; then
            mount /var/www/html/$iso_filename $mt_dir
        fi
    fi
}

function cp_boot_file {
    echo "Copy all boot files to tftp root dir ..."
    yum install -y syslinux
    yum install -y grub2-efi-modules
    dnf install -y grub2-efi-x64-modules
    dnf install -y grub2-efi grub2-tools-efi

    efi_dir="/usr/lib/grub/x86_64-efi/"
    grub2-mkstandalone -d $efi_dir -O x86_64-efi --modules="tftp net efinet linux part_gpt efifwsetup" -o bootx64.efi
    cp bootx64.efi $tftp_root
    cp $mt_dir/images/pxeboot/{vmlinuz,initrd.img} $tftp_root
    cp $mt_dir/isolinux/{vesamenu.c32,boot.msg,splash.png} $tftp_root
    cp /usr/share/syslinux/{chain.c32,mboot.c32,menu.c32,memdisk} $tftp_root
    sleep 1
}

function set_ipv4_ipxe_boot_file {
    echo "Create and set IPv4 iPXE boot file ..."
    if [[ ! -e "$tftp_root/ipv4.ipxe" ]]; then
        touch $tftp_root/ipv4.ipxe
    fi
    cat <<EOF > "$tftp_root/ipv4.ipxe"
#!ipxe
set base http://$srv_ip/CentOS
kernel \${base}/images/pxeboot/vmlinuz initrd=initrd.img inst.repo=\${base}
initrd \${base}/images/pxeboot/initrd.img
boot
EOF
}

function set_ipv6_ipxe_boot_file {
    echo "Create and set IPv6 iPXE boot file ..."
    if [[ ! -e "$tftp_root/ipv6.ipxe" ]]; then
        touch $tftp_root/ipv6.ipxe
    fi
    cat <<EOF > "$tftp_root/ipv6.ipxe"
#!ipxe
set base http://$srv_ip6/CentOS
kernel \${base}/images/pxeboot/vmlinuz initrd=initrd.img inst.repo=\${base}
initrd \${base}/images/pxeboot/initrd.img
boot
EOF
}

function modify_grub_file {
    grub_file="$tftp_root/grub.cfg"
    if [[ ! -e "$tftp_root/grub.cfg.bak" ]]; then
        cp $grub_file $tftp_root/grub.cfg.bak
    fi
    sed -n '/^menuentry/=' $grub_file |head -1 |xargs -I {} sed -i '{},$d' $grub_file
    cat <<EOF >> "$grub_file"
menuentry 'Install CentOS Linux IPv4' --class fedora --class gnu-linux --class gnu --class os {
        linuxefi (tftp)/vmlinuz inst.repo=http://$srv_ip/CentOS/
        initrdefi (tftp)/initrd.img
}
menuentry 'Install CentOS Linux IPv6' --class fedora --class gnu-linux --class gnu --class os {
        linuxefi (tftp)/vmlinuz inst.repo=http://$srv_ip6/CentOS/
        initrdefi (tftp)/initrd.img
}
EOF
    sed -i 's/set default="1"/set default="0"/' $grub_file
}

function set_boot_file {
    echo "Set IPv4 and IPv6 iPXE boot file and modify grub.cfg ..."
    cp $mt_dir/EFI/BOOT/grub.cfg $tftp_root
    set_ipv4_ipxe_boot_file
    set_ipv6_ipxe_boot_file
    modify_grub_file
}

function start_services {
    echo "Start all related services ..."
    dhcp4_status=$(systemctl status dhcpd.service > /dev/null 2>&1 && echo yes || echo no)
    dhcp6_status=$(systemctl status dhcpd6.service > /dev/null 2>&1 && echo yes || echo no)
    ra_status=$(systemctl status radvd.service > /dev/null 2>&1 && echo yes || echo no)
    # tftp_status=$(systemctl status tftp.service > /dev/null 2>&1 && echo yes || echo no)
    xinet_status=$(systemctl status xinetd.service > /dev/null 2>&1 && echo yes || echo no)
    http_status=$(systemctl status httpd.service > /dev/null 2>&1 && echo yes || echo no)
    if [ $dhcp4_status = "yes" ]; then
        systemctl stop dhcpd.service
    fi
    if [ $dhcp6_status = "yes" ]; then
        systemctl stop dhcpd6.service
    fi
    if [ $ra_status = "yes" ]; then
        systemctl stop radvd.service
    fi
    # if [ $tftp_status = "yes" ]; then
    #     systemctl stop tftp.service
    # fi
    if [ $xinet_status = "yes" ]; then
        systemctl stop xinetd.service
    fi
    if [ $http_status = "yes" ]; then
        systemctl stop httpd.service
    fi
    echo "start dhcp4 ..."
    systemctl start dhcpd.service
    echo "start dhcp6 ..."
    systemctl start dhcpd6.service
    echo "start ra ..."
    systemctl start radvd.service
    echo "start xinetd ..."
    systemctl start xinetd.service
    # echo "start tftp ..."
    # systemctl start tftp.service
    echo "start httpd ..."
    systemctl start httpd.service
    dhcp4_status=$(systemctl status dhcpd.service > /dev/null 2>&1 && echo yes || echo no)
    dhcp6_status=$(systemctl status dhcpd6.service > /dev/null 2>&1 && echo yes || echo no)
    ra_status=$(systemctl status radvd.service > /dev/null 2>&1 && echo yes || echo no)
    # tftp_status=$(systemctl status tftp.service > /dev/null 2>&1 && echo yes || echo no)
    xinet_status=$(systemctl status xinetd.service > /dev/null 2>&1 && echo yes || echo no)
    http_status=$(systemctl status httpd.service > /dev/null 2>&1 && echo yes || echo no)
    all_srv_started="true"
    if [ $dhcp4_status = "no" ]; then
        echo "start DHCP4 failed!"
        all_srv_started="false"
    fi
    if [ $dhcp6_status = "no" ]; then
        echo "start DHCP6 failed!"
        all_srv_started="false"
    fi
    if [ $ra_status = "no" ]; then
        echo "start RA failed!"
        all_srv_started="false"
    fi
    # if [ $tftp_status = "no" ]; then
    #     echo "start TFTP failed!"
    #     all_srv_started="false"
    # fi
    if [ $xinet_status = "no" ]; then
        echo "start Xinet failed!"
        all_srv_started="false"
    fi
    if [ $http_status = "no" ]; then
        echo "start HTTP failed!"
        all_srv_started="false"
    fi
    echo $SPLIT_LINE
    if [ $all_srv_started = "true" ]; then
        echo "All services started success!"
    fi
    echo $SPLIT_LINE
}

function install_action {
    echo "Install software start services for PXE/iPXE server ..."
    echo $SPLIT_LINE
    stop_firewall
    echo $SPLIT_LINE
    install_dhcp
    echo $SPLIT_LINE
    install_tftp
    echo $SPLIT_LINE
    install_http
    echo $SPLIT_LINE
    process_ip
    echo $SPLIT_LINE
    process_config_file
    echo $SPLIT_LINE
    mount_image_iso_file
    echo $SPLIT_LINE
    cp_boot_file
    echo $SPLIT_LINE
    set_boot_file
    echo $SPLIT_LINE
    start_services
    echo $SPLIT_LINE
    if [ $all_srv_started = "true" ]; then
        echo "Installation of PXE/IPXE server finished!"
        echo "All services are running normally!"
    fi
    echo $SPLIT_LINE
}

function start_action {
    echo "Start services for PXE/iPXE server ..."
    echo $SPLIT_LINE
    stop_firewall
    echo $SPLIT_LINE
    process_ip
    echo $SPLIT_LINE
    process_config_file
    echo $SPLIT_LINE
    mount_image_iso_file
    echo $SPLIT_LINE
    set_boot_file
    echo $SPLIT_LINE
    start_services
    if [ $all_srv_started = "true" ]; then
        echo "Start services of PXE/IPXE server finished!"
        echo "All services are running normally!"
    fi
    echo $SPLIT_LINE
}

function main {
    get_args "$@"
    if [ $act = "install" ]; then
        install_action
    elif [ $act = "start" ]; then
        start_action
    else
        echo "Invalid action, Please input valid action argument(start/install)"
        exit 1
    fi
}

main "$@"
