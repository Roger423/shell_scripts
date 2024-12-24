#!/bin/bash

SPLIT_LINE="-----------------------------------------------------------------------------------------------------------"
# Set qemu version
QEMU_VERSION="8.1.1"

# Set vm name
VM_NAME="vm0"

# Set vm cpu cores count
VM_CPU_CORES=4

# Set vm memory size (GiB)
VM_MEM=4

# Set vm img path
VM_IMG="/home/vm0.qcow2"

# Set MAC address for vm manage interface
VM_MNG_MAC="00:00:00:00:01:01"

# Set vm RDMA device function ID
RDMA_DEV="88:00.1"

# Set vm Virtio device function ID
VIRTIO_DEV="87:00.1"

# Set vm NVMe device function ID
NVME_DEV=""

# Set vm VNC port
VNC_PORT="5940"

# Physical interface of the host
PHY_INTERFACE="enp5s0"

# Set vm xml file name, default to be the same with vm name
XML_FILE="$VM_NAME.xml"

# Set bridge name for vm to attach to
BRIDGE_NAME="br0"

check_libvirt_install() {
    echo "Check libvirt-client installation"
    sudo yum install libvirt libvirt-daemon -y
    if rpm -q libvirt-client &> /dev/null; then 
        echo "libvirt-client is already installed" 
    else 
        echo "libvirt-client is not installed, installing now..." 
        sudo dnf install -y libvirt-client 
        if [ $? -eq 0 ]; then 
            echo "libvirt-client installation successful" 
        else 
            echo "libvirt-client installation failed" 
        fi 
    fi
    sudo systemctl enable libvirtd
    sudo systemctl start libvirtd
}

stop_firewall_and_selinux() {
    echo "Stop firewall and Selinux"
    systemctl stop firewalld.service
    systemctl disable firewalld.service
    setenforce 0
}

check_iommu() {
    echo "Check enable iommu in /etc/default/grub"
    if grep -q "iommu=on" /etc/default/grub; then
        echo "IOMMU is enabled in /etc/default/grub"
    else
        echo "IOMMU is not enabled in /etc/default/grub, please enable iommu in /etc/default/grub first"
        exit 1
    fi
}

check_python3() {
    echo "Check python3 version"
    python3_ver=$(python3 --version 2>&1 | awk '{print $2}')
    req_ver="3.8.0"
    if [[ $(echo -e "$python3_ver\n$req_ver" | sort -V | head -n1) == "$req_ver" ]]; then
        echo "Python version is $python3_ver, which is sufficient."
    else
        echo "Python version is $python3_ver, which is not sufficient. Installing Python 3.8..."
        sudo dnf install -y python38
        if [ $? -eq 0 ]; then
            echo "Python 3.8 installation successful."

            # 使用 alternatives 设置默认的 python3 为 python3.8
            sudo alternatives --install /usr/bin/python3 python3 /usr/bin/python3.8 1
            sudo alternatives --set python3 /usr/bin/python3.8
            sudo ln -s /usr/bin/pip3.8 /usr/bin/pip3
            new_python3_ver=$(python3 --version 2>&1 | awk '{print $2}')
            echo "Default Python version is now $new_python3_ver."
        else
            echo "Python 3.8 installation failed."
        fi
    fi
}

check_qemu() {
    echo "Check qemu version"
    qemu_ver=$(qemu-system-x86_64 --version | grep -oP '(?<=version )[^,]*')
    req_ver=$QEMU_VERSION
    if [[ $(echo -e "$qemu_ver\n$req_ver" | sort -V | head -n1) == "$req_ver" ]]; then
        echo "QEMU version is $qemu_ver, which is sufficient."
    else
        echo "QEMU version is $qemu_ver, which is not sufficient. Downloading and installing QEMU $QEMU_VERSION..."
        dnf groupinstall "Development Tools" -y
        dnf install pkgconfig glib2-devel -y
        dnf install pixman-devel -y
        pip3 install meson ninja -i https://pypi.tuna.tsinghua.edu.cn/simple
        pip3 install --upgrade meson -i https://pypi.tuna.tsinghua.edu.cn/simple
        pip3 install pyelftools -i https://pypi.tuna.tsinghua.edu.cn/simple
        cd /opt/
        wget https://download.qemu.org/qemu-$QEMU_VERSION.tar.xz
        tar -xf qemu-$QEMU_VERSION.tar.xz
        cd qemu-$QEMU_VERSION
        ./configure --target-list=x86_64-softmmu --enable-debug --enable-debug-info --enable-kvm
        make -j
        sudo make install
        cd
        if [ $? -eq 0 ]; then
            echo "QEMU $QEMU_VERSION installation successful."
        else
            echo "QEMU $QEMU_VERSION installation failed."
        fi
    fi
}

create_vm_xml_file() {
    echo "Create vm xml file"
    if [ -f "$XML_FILE" ]; then 
        echo "$XML_FILE already exists. please specify another vm name to create corresponding xml file"
        exit 1	
    else 
        touch "$XML_FILE" 
    fi
}

set_xml_file() {
    echo "Set vm xml file content"
cat <<EOF > $XML_FILE
<domain type='kvm'>
  <name>$VM_NAME</name>
  <uuid>$(uuidgen)</uuid>
  <memory unit='GiB'>$VM_MEM</memory>
  <currentMemory unit='GiB'>$VM_MEM</currentMemory>
  <vcpu>$VM_CPU_CORES</vcpu>
  <cpu mode='host-passthrough'>
  </cpu>

  <os>
   <type arch='x86_64' machine='pc'>hvm</type>
   <boot dev='hd'/>
   <boot dev='cdrom'/>
   <bootmenu enable='yes'/>
  </os>
  <features>
   <acpi/>
   <apic/>
   <pae/>
  </features>
  <clock offset='localtime'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
  <devices>
   <emulator>/usr/local/bin/qemu-system-x86_64</emulator>
   <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='$VM_IMG'/>
      <target dev='vda' bus='virtio'/>
   </disk>

   <interface type='bridge'>
     <mac address='$VM_MNG_MAC'/>
     <source bridge='$BRIDGE_NAME'/>
     <model type='virtio'/>
   </interface>

   <graphics type='vnc' port='$VNC_PORT' autoport='no' listen='0.0.0.0' keymap='en-us'>
     <listen type='address' address='0.0.0.0'/>
   </graphics>

EOF

if [ -n "$RDMA_DEV" ]; then
    cat <<EOF >> $XML_FILE
   <hostdev mode='subsystem' type='pci' managed='yes'>
     <source>
       <address domain='0x0000' bus='0x${RDMA_DEV:0:2}' slot='0x${RDMA_DEV:3:2}' function='0x${RDMA_DEV:6:1}'/>
     </source>
   </hostdev>
EOF
fi

if [ -n "$VIRTIO_DEV" ]; then
    cat <<EOF >> $XML_FILE
   <hostdev mode='subsystem' type='pci' managed='yes'>
     <source>
       <address domain='0x0000' bus='0x${VIRTIO_DEV:0:2}' slot='0x${VIRTIO_DEV:3:2}' function='0x${VIRTIO_DEV:6:1}'/>
     </source>
   </hostdev>
EOF
fi

if [ -n "$NVME_DEV" ]; then
    cat <<EOF >> $XML_FILE
   <hostdev mode='subsystem' type='pci' managed='yes'>
     <source>
       <address domain='0x0000' bus='0x${NVME_DEV:0:2}' slot='0x${NVME_DEV:3:2}' function='0x${NVME_DEV:6:1}'/>
     </source>
   </hostdev>
EOF
fi

cat <<EOF >> $XML_FILE
  </devices>
</domain>
EOF
}

clear_phy_iface_connection() {
    echo "Clear physical interface connection of $PHY_INTERFACE..."
    echo "This will cause SSH connection down if SSH connection via $PHY_INTERFACE"
    cons=$(nmcli -t -f NAME,DEVICE connection show | grep $PHY_INTERFACE | awk -F: '{print $1}')
    if [ -n "$cons" ]; then
        echo "Found connections using $PHY_INTERFACE:"
        echo "$cons"
        while IFS= read -r con; do
            br_master=$(nmcli -g connection.master connection show "$con")
            if [ "$br_master" == "$BRIDGE_NAME" ]; then
                echo "Connection \"$con\" is a slave interface of $BRIDGE_NAME, not deleting."
            else
                echo "Deleting connection \"$con\"..."
                nmcli connection delete "$con"
                if [ $? -eq 0 ]; then
                    echo "Connection \"$con\" deleted successfully."
                else
                    echo "Failed to delete connection \"$con\"."
                fi
            fi
        done <<< "$cons"
    else
        echo "No connections found using $PHY_INTERFACE."
    fi
}

create_br() {
    echo "Create bridge $BRIDGE_NAME ..."
    if nmcli connection show $BRIDGE_NAME &> /dev/null; then
        echo "Network bridge $BRIDGE_NAME already exists."
    else
        echo "Network bridge $BRIDGE_NAME does not exist. Creating it now..."
        nmcli connection add type bridge con-name $BRIDGE_NAME ifname $BRIDGE_NAME
        if [ $? -eq 0 ]; then
            echo "Network bridge $BRIDGE_NAME has been created successfully."
        else
            echo "Failed to create network bridge $BRIDGE_NAME."
        fi
    fi
}

clear_no_interface_connection() {
    echo "Clean up connections with no managing interfaces"
    all_conns=$(nmcli -t -f NAME,DEVICE connection show)
    while IFS=: read -r name device; do
        if [ -z "$device" ]; then
            echo "Deleting connection \"$name\" which has no managing interface..."
            nmcli connection delete "$name"
            if [ $? -eq 0 ]; then
                echo "Connection \"$name\" deleted successfully."
            else
                echo "Failed to delete connection \"$name\"."
            fi
        fi
    done <<< "$connections"
}

add_phy_interface_to_br() {
    echo "Add physical interface $PHY_INTERFACE to be a slave port of $BRIDGE_NAME"
    nmcli connection add type bridge-slave ifname $PHY_INTERFACE master $BRIDGE_NAME
    if [ $? -eq 0 ]; then
        echo "Add interface $PHY_INTERFACE to be a slave port of $BRIDGE_NAME successfully."
    else
        echo "Failed to add interface $PHY_INTERFACE to be a slave port of $BRIDGE_NAME."
    fi
    sleep 2
}

check_phy_interface_to_br() {
    echo "Check if $PHY_INTERFACE is a slave port of any bridge"
    clear_no_interface_connection
    conns=$(nmcli -t -f NAME,DEVICE connection show | grep $PHY_INTERFACE | awk -F: '{print $1}')
    if [ -n "$conns" ]; then
        echo "Found connections using $PHY_INTERFACE: "
        echo "$conns"
        vld_conn=""
        while IFS= read -r conn; do
            br_mst=$(nmcli -g connection.master connection show "$conn")
            if [ "$br_mst" == "$BRIDGE_NAME" ]; then
                echo "Connection \"$conn\" is a slave interface of $BRIDGE_NAME"
                if [ -z "$vld_conn" ]; then
                    vld_conn="$conn"
                else
                    echo "Connection \"$conn\" is an extra slave interface of $BRIDGE_NAME, should be deleted"
                    nmcli connection delete "$conn"
                    if [ $? -eq 0 ]; then
                        echo "Connection \"$conn\" deleted successfully."
                    else
                        echo "Failed to delete connection \"$conn\"."
                    fi
                    sleep 2
                fi
            else
                echo "Deleting connection \"$conn\"..."
                nmcli connection delete "$conn"
                if [ $? -eq 0 ]; then
                    echo "Connection \"$conn\" deleted successfully."
                else
                    echo "Failed to delete connection \"$conn\"."
                fi
                sleep 2
            fi
        done <<< "$conns"
        if [ -z "$vld_conn" ]; then
            add_phy_interface_to_br
        fi
    else
        echo "No connections found using $PHY_INTERFACE."
        add_phy_interface_to_br
    fi
}

set_br_ip_method() {
    echo "Set ipv4 method for $BRIDGE_NAME"
    br_ip_method=$(nmcli -t -f ipv4.method connection show $BRIDGE_NAME | awk -F: '{print $2}')
    if [ "$br_ip_method" == "auto" ]; then
        echo "The address method for $BRIDGE_NAME is already set to auto."
    else
        echo "Setting the address method for $BRIDGE_NAME to auto..."
        nmcli connection modify $BRIDGE_NAME ipv4.method auto
        nmcli connection up $BRIDGE_NAME
        sleep 5
        if [ $? -eq 0 ]; then
            echo "The address method for $BRIDGE_NAME has been set to auto successfully."
        else
            echo "Failed to set the address method for $BRIDGE_NAME to auto."
        fi
    fi
}

start_vm() {
    echo "Define vm using XML file $XML_FILE"
    virsh define $XML_FILE
    if [ $? -eq 0 ]; then
        echo "Define vm by $XML_FILE successfully."
    else
        echo "Failed to define vm by $XML_FILE."
    exit 1
    fi
    echo "Check vm list before start vm"
    virsh list --all
    echo "Start vm ..."
    virsh start $VM_NAME
    if [ $? -eq 0 ]; then
        echo "Start vm by $VM_NAME successfully."
    else
        echo "Failed to start vm $VM_NAME."
        exit 1
    fi
    echo "Check vm list after start vm"
    virsh list
}

show_info() {
    echo $SPLIT_LINE
    br_ip=$(ifconfig $BRIDGE_NAME | grep 'inet ' | awk '{print $2}')
    echo "VM deployed successfully"
    echo "Information of VM environment:"
    echo "IP address of host(SSH) ----> $br_ip"
    echo "Virtio device of VM --------> $VIRTIO_DEV"
    echo "RDMA device of VM ----------> $RDMA_DEV"
    echo "NVMe device of VM ----------> $NVME_DEV"
    echo "VNC port of VM -------------> $VNC_PORT"
    echo $SPLIT_LINE
}

main() {
    echo $SPLIT_LINE
    check_iommu
    echo $SPLIT_LINE
    stop_firewall_and_selinux
    echo $SPLIT_LINE
    check_libvirt_install
    echo $SPLIT_LINE
    check_python3
    echo $SPLIT_LINE
    check_qemu
    echo $SPLIT_LINE
    create_vm_xml_file
    echo $SPLIT_LINE
    set_xml_file
    echo $SPLIT_LINE
    clear_phy_iface_connection
    echo $SPLIT_LINE
    create_br
    echo $SPLIT_LINE
    check_phy_interface_to_br
    echo $SPLIT_LINE
    set_br_ip_method
    echo $SPLIT_LINE
    start_vm
    echo $SPLIT_LINE
    show_info
}

main
