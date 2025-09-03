#!/bin/bash

SPLIT_LINE="-----------------------------------------------------------------------------------------------------------"
iface=""
iso_image_path="/home/ubuntu-22.04.1-desktop-amd64.iso"
srv_ip="10.0.0.1"
srv_ip6="2023::1"
act=""
tftp_root="/srv/tftp"
mt_dir="/var/www/html/Ubuntu"
iso_filename=$(basename "$iso_image_path")

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
    ufw status
    ufw disable
}

function install_dhcp {
    echo "Install DHCP and RA ..."
    apt install -y isc-dhcp-server
    apt install -y radvd

    systemctl stop isc-dhcp-server
    systemctl disable isc-dhcp-server
    systemctl stop isc-dhcp-server6
    systemctl disable isc-dhcp-server6
    systemctl stop radvd
    systemctl disable radvd
}

function install_tftp {
    echo "Install TFTP ..."
    apt install -y tftpd-hpa

    systemctl stop tftpd-hpa.service
    systemctl disable tftpd-hpa.service
}

function install_http {
    echo "Install HTTP ..."
    apt install -y apache2

    systemctl stop apache2.service
    systemctl disable apache2.service
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
    echo $SPLIT_LINE
    check_network_manager
    echo $SPLIT_LINE
    config_interface_ip
    echo $SPLIT_LINE
    get_dhcp_ip_range
}

function set_dhcp_iface_file {
    echo "Set DHCP interface file ..."
    if [[ ! -e "/etc/default/isc-dhcp-server.bak" ]]; then
        cp /etc/default/isc-dhcp-server /etc/default/isc-dhcp-server.bak
    fi
    cat <<EOF > /etc/default/isc-dhcp-server
INTERFACESv4="$iface"
INTERFACESv6="$iface"
EOF
}

function set_dhcp4_config_file {
    echo "Set DHCP4 config file ..."
    ip4_subnet="$ipseg1.$ipseg2.$ipseg3.0"
    if [[ ! -e "/etc/dhcp/dhcpd.conf.bak" ]]; then
        cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.bak
    fi
    cat <<EOF > /etc/dhcp/dhcpd.conf
subnet $ip4_subnet netmask 255.255.255.0 {
    range $ip4_rg_st $ip4_rg_ed;
    option routers $srv_ip;
    next-server $srv_ip;
    if option user-class = "iPXE" {
        filename "/UEFI/ipv4.ipxe";
    } else {
            filename "/UEFI/bootx64.efi";
    }
}
EOF
}

function set_dhcp6_config_file {
    echo "Set DHCP6 config file ..."
    ip6_subnet="$ip6seg1::"
    if [[ ! -e "/etc/dhcp/dhcpd6.conf.bak" ]]; then
        cp /etc/dhcp/dhcpd6.conf /etc/dhcp/dhcpd6.conf.bak
    fi
    cat <<EOF > /etc/dhcp/dhcpd6.conf
subnet6 $ip6_subnet/64 {
    range6 $ip6_rg_st $ip6_rg_ed;
    range6 $ip6_subnet temporary;
    if option user-class = "iPXE" {
        filename "/UEFI/ipv6.ipxe";
    } else {
            filename "/UEFI/bootx64.efi";
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

function process_config_file {
    set_dhcp_iface_file
    set_dhcp4_config_file
    set_dhcp6_config_file
    set_ra_config_file
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

function cp_legacy_boot_file {
    echo "Copy legacy boot files to tftp root dir ..."
    legacy_dir="$tftp_root/Legacy"
    if [[ ! -e "$legacy_dir" ]]; then
        mkdir -p $legacy_dir
    fi
    apt install syslinux pxelinux

    cp $mt_dir/casper/{vmlinuz,initrd} $legacy_dir
    cp /usr/lib/syslinux/modules/bios/{ldlinux.c32,libutil.c32,menu.c32,vesamenu.c32} $legacy_dir
    cp /usr/lib/PXELINUX/{lpxelinux.0,pxelinux.0} $legacy_dir
    sleep 1
}

function set_legacy_menu_file {
    if [[ ! -e "$legacy_dir/pxelinux.cfg" ]]; then
        mkdir -p $legacy_dir/pxelinux.cfg
    fi
    if [[ ! -e "$legacy_dir/pxelinux.cfg/default" ]]; then
        touch $legacy_dir/pxelinux.cfg/default
    fi
    cat <<EOF > "$legacy_dir/pxelinux.cfg/default"
DEFAULT menu.c32
MENU TITLE ULTIMATE PXE SERVER - By Griffon - Ver 1.0
PROMPT 0
TIMEOUT 0

MENU COLOR TABMSG  37;40  #ffffffff #00000000
MENU COLOR TITLE   37;40  #ffffffff #00000000
MENU COLOR SEL      7     #ffffffff #00000000
MENU COLOR UNSEL    37;40 #ffffffff #00000000
MENU COLOR BORDER   37;40 #ffffffff #00000000

LABEL Ubuntu IPv4
    kernel /vmlinuz
    initrd /initrd
    append root=/dev/ram0 ramdisk_size=1500000 ip=dhcp url=http://$srv_ip/$iso_filename

LABEL Ubuntu IPv6
    kernel /vmlinuz
    initrd /initrd
    append root=/dev/ram0 ramdisk_size=1500000 ip=dhcp url=http://[$srv_ip6]/$iso_filename

EOF
}

function set_ipv4_ipxe_boot_file {
    echo "Create and set IPv4 iPXE boot file ..."
    if [[ ! -e "$tftp_root/UEFI/ipv4.ipxe" ]]; then
        touch $tftp_root/UEFI/ipv4.ipxe
    fi
    cat <<EOF > "$tftp_root/UEFI/ipv4.ipxe"
#!ipxe
set base http://$srv_ip
kernel \${base}/Ubuntu/casper/vmlinuz initrd=initrd ip=dhcp url=\${base}/$iso_filename autoinstall
initrd \${base}/Ubuntu/casper/initrd
boot
EOF
}

function set_ipv6_ipxe_boot_file {
    echo "Create and set IPv6 iPXE boot file ..."
    if [[ ! -e "$tftp_root/UEFI/ipv6.ipxe" ]]; then
        touch $tftp_root/UEFI/ipv6.ipxe
    fi
    cat <<EOF > "$tftp_root/UEFI/ipv6.ipxe"
#!ipxe
set base http://$srv_ip6
kernel \${base}/Ubuntu/casper/vmlinuz initrd=initrd ip=dhcp url=\${base}/$iso_filename autoinstall
initrd \${base}/Ubuntu/casper/initrd
boot
EOF
}

function cp_uefi_boot_file {
    echo "Copy UEFI boot files to tftp root dir ..."
    uefi_dir="$tftp_root/UEFI"
    if [[ ! -e "$uefi_dir" ]]; then
        mkdir -p $uefi_dir
    fi

    cp $mt_dir/casper/{vmlinuz,initrd}  $uefi_dir
    apt download shim-signed
    dpkg -x shim-signed*deb shim
    cp shim/usr/lib/shim/shimx64.efi.signed.latest  $uefi_dir/bootx64.efi
    apt download grub-efi-amd64-signed
    dpkg -x grub-efi-amd64-signed*deb grub
    cp grub/usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed $uefi_dir/grubx64.efi
    apt download grub-common
    dpkg -x grub-common*deb grub-common
    cp grub-common/usr/share/grub/unicode.pf2 $uefi_dir
    sleep 1
}

function set_uefi_menu_file {
    if [[ ! -e "$tftp_root/grub" ]]; then
        mkdir $tftp_root/grub
    fi
    if [[ ! -e "$tftp_root/grub/grub.cfg" ]]; then
        touch $tftp_root/grub/grub.cfg
    fi
    cat <<EOF > "$tftp_root/grub/grub.cfg"
set default="0"
set timeout=-1
        
if loadfont unicode; then
	set gfxmode=auto
	set locale_dir=\$prefix/locale
	set lang=en_US
fi
terminal_output gfxterm

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray
if background_color 44,0,30; then
	clear
fi

function gfxmode {
	set gfxpayload="\${1}"
	if [ "\${1}" = "keep" ]; then
		set vt_handoff=vt.handoff=7
	else
		set vt_handoff=
	fi
}

set linux_gfx_mode=keep
export linux_gfx_mode

menuentry 'Ubuntu IPv4' {
	gfxmode \$linux_gfx_mode
	linux /UEFI/vmlinuz root=/dev/ram0 ramdisk_size=1500000 ip=dhcp url=http://$srv_ip/$iso_filename
	initrd /UEFI/initrd
}

menuentry 'Ubuntu IPv6' {
	gfxmode \$linux_gfx_mode
	linux /UEFI/vmlinuz root=/dev/ram0 ramdisk_size=1500000 ip=dhcp url=http://[$srv_ip6]/$iso_filename
	initrd /UEFI/initrd
}
EOF
}

function set_install_boot_file {
    echo "Set boot file for installation ..."
    cp_legacy_boot_file
    set_legacy_menu_file
    set_ipv4_ipxe_boot_file
    set_ipv6_ipxe_boot_file
    cp_uefi_boot_file
    set_uefi_menu_file
}

function set_start_boot_file {
    echo "Set boot file for start service ..."
    set_legacy_menu_file
    set_ipv4_ipxe_boot_file
    set_ipv6_ipxe_boot_file
    set_uefi_menu_file
}

function start_services {
    echo "Start all related services ..."
    dhcp4_status=$(systemctl status isc-dhcp-server > /dev/null 2>&1 && echo yes || echo no)
    dhcp6_status=$(systemctl status isc-dhcp-server6 > /dev/null 2>&1 && echo yes || echo no)
    ra_status=$(systemctl status radvd > /dev/null 2>&1 && echo yes || echo no)
    tftp_status=$(systemctl status tftpd-hpa.service > /dev/null 2>&1 && echo yes || echo no)
    http_status=$(systemctl status apache2.service > /dev/null 2>&1 && echo yes || echo no)
    if [ $dhcp4_status = "yes" ]; then
        systemctl stop isc-dhcp-server
    fi
    if [ $dhcp6_status = "yes" ]; then
        systemctl stop isc-dhcp-server6
    fi
    if [ $ra_status = "yes" ]; then
        systemctl stop radvd
    fi
    if [ $tftp_status = "yes" ]; then
        systemctl stop tftpd-hpa.service
    fi
    if [ $http_status = "yes" ]; then
        systemctl stop apache2.service
    fi
    echo "start dhcp4 ..."
    systemctl start isc-dhcp-server
    echo "start dhcp6 ..."
    systemctl start isc-dhcp-server6
    echo "start ra ..."
    systemctl start radvd
    echo "start tftp ..."
    systemctl start tftpd-hpa.service
    echo "start httpd ..."
    systemctl start apache2.service
    dhcp4_status=$(systemctl status isc-dhcp-server > /dev/null 2>&1 && echo yes || echo no)
    dhcp6_status=$(systemctl status isc-dhcp-server6 > /dev/null 2>&1 && echo yes || echo no)
    ra_status=$(systemctl status radvd > /dev/null 2>&1 && echo yes || echo no)
    tftp_status=$(systemctl status tftpd-hpa.service > /dev/null 2>&1 && echo yes || echo no)
    http_status=$(systemctl status apache2.service > /dev/null 2>&1 && echo yes || echo no)
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
    if [ $tftp_status = "no" ]; then
        echo "start TFTP failed!"
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
    set_install_boot_file
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
    # echo $SPLIT_LINE
    process_ip
    echo $SPLIT_LINE
    process_config_file
    echo $SPLIT_LINE
    mount_image_iso_file
    echo $SPLIT_LINE
    set_start_boot_file
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
