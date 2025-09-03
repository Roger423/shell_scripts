#!/bin/bash

SPLIT_LINE="-----------------------------------------------------------------------------------------------------------"
RDMA_ROOT_DIR="/home/rdma"
UPDATE_RDMA_CORE="false"
RDMA_CORE_BRANCH="master"
UPDATE_RIB_DRV="false"
RIB_DRV_BRANCH="sriov"
UPDATE_RQOS="false"
RQOS_BRANCH="main"
UPDATE_RIB_CLI="false"
RIB_CLI_BRANCH="master"
UPDATE_RFT="false"
RFT_BRANCH="master"
UPDATE_PERFTEST="false"
PERFTEST_BRANCH="hrdma-3.0"
USERNAME="build"
PASSWD="123456789"
PERFTEST_USERNAME="luoshanguo"
PERFTEST_PASSWD="lsg123456"
GITLAB_ADDR="192.168.65.225"
PROJECT="c3000"
KERNEL_DEVEL_PKG="kernel-devel-4.18.0-305.3.1.el8.x86_64"
KERNEL_HEADERS_PKG="kernel-headers-4.18.0-305.3.1.el8.x86_64"
KERNEL_DEVEL_PKG_PATH="/home/rdma/$KERNEL_DEVEL_PKG.rpm"
KERNEL_HEADERS_PKG_PATH="/home/rdma/$KERNEL_HEADERS_PKG.rpm"
KERNEL="$(uname -r)"

RDMA_CORE_DEP_PKGS=("cmake" "libnl3" "libnl3-devel")
RQOS_DEP_PKGS=("yaml-cpp" "yaml-cpp-devel" "yaml-cpp-static")
PERFTEST_DEP_PKGS=("pciutils-devel" "libibverbs" "libibverbs-devel")


TIME_STR=$(date +"%Y%m%d_%H%M%S")

print_help() {
    cat << EOF
$SPLIT_LINE
To download RDMA software (rdma-core, rib_driver, rqos, rib_cli, rft, perftest) in the same directory, 
such as $RDMA_ROOT_DIR. Then compile RDMA software. It will be backuped if old software exist, 
with a directory name appended by a time string.

Usage:
    $0 -h or $0 help or $0 --help
    or
    $0 rdma_root=<rdma root path> rdma_core=<if update rdma-core> rdma_core_branch=<git branch of rdma-core> \
rib_drv=<if update rib_driver> rib_drv_branch=<git branch of rib driver> rqos=<if update rqos> rqos_branch=<git branch \
of rqos> rib_cli=<if update rib_driver> rib_cli_branch=<git branch of rib_cli> rft=<if update rft> rft_branch=<git \
branch of rft> perftest=<if update perftest> perftest_branch=<git branch of perftest>

Arguments:
    rdma_root:         the RDMA software path where "rdma-core, rib_driver, rib_cli, rft, perftest" are located.
                       Default is $RDMA_ROOT_DIR
    rdma_core:         whether to update rdma-core software (true/false), default is $UPDATE_RDMA_CORE
	rdma_core_branch:  specify the branch of rdma-core to update, default is $RDMA_CORE_BRANCH
    rib_drv:           whether to update rib_driver software (true/false), default is $UPDATE_RIB_DRV
	rib_drv_branch:    specify the branch of rib driver to update, default is $RIB_DRV_BRANCH
    rqos:              whether to update rqos software (true/false), default is $UPDATE_RQOS
	rqos_branch:       specify the branch of rqos to update, default is $RQOS_BRANCH
    rib_cli:           whether to update rib_cli software (true/false), default is $UPDATE_RIB_CLI
	rib_cli_branch:    specify the branch of rib_cli to update, default is $RIB_CLI_BRANCH
    rft:               whether to update rft software (true/false), default is $UPDATE_RFT
	rft_branch:        specify the branch of rft to update, default is $RFT_BRANCH
    perftest:          whether update perftest software (true/false), default is $UPDATE_PERFTEST
	perftest_branch:   specify the branch of perftest to update, default is $PERFTEST_BRANCH

Examples:
    update all software, with the RDMA root path as $RDMA_ROOT_DIR, and the branch of all software to be the default:
        bash $0

    update all software, with the RDMA root path as /home/test/rdma/:
        bash $0 rdma_root=/home/test/rdma/

    update only rdma-core, with the RDMA root path as default $RDMA_ROOT_DIR:
        bash $0 rib_drv=false rqos=false rib_cli=false rft=false perftest=false

    update all software, specify branch, with the RDMA root path as default $RDMA_ROOT_DIR:
        bash $0 rdma_core_branch=xxx rib_drv_branch=xxx rqos_branch=xxx rib_cli_branch=xxx rft_branch=xxx \
perftest_branch=xxx

$SPLIT_LINE
EOF
}

for arg in "$@"
do
	case $arg in
		rdma_root=*)
			RDMA_ROOT_DIR="${arg#*=}"
			;;
		rdma_core=*)
			UPDATE_RDMA_CORE="${arg#*=}"
			;;
		rdma_core_branch=*)
			RDMA_CORE_BRANCH="${arg#*=}"
			;;
		rib_drv=*)
			UPDATE_RIB_DRV="${arg#*=}"
			;;
		rib_drv_branch=*)
			RIB_DRV_BRANCH="${arg#*=}"
			;;
		rqos=*)
			UPDATE_RQOS="${arg#*=}"
			;;
		rqos_branch=*)
			RQOS_BRANCH="${arg#*=}"
			;;
		rib_cli=*)
			UPDATE_RIB_CLI="${arg#*=}"
			;;
		rib_cli_branch=*)
			RIB_CLI_BRANCH="${arg#*=}"
			;;
		rft=*)
			UPDATE_RFT="${arg#*=}"
			;;
		rft_branch=*)
			RFT_BRANCH="${arg#*=}"
			;;
		perftest=*)
			UPDATE_PERFTEST="${arg#*=}"
			;;
		perftest_branch=*)
			PERFTEST_BRANCH="${arg#*=}"
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

install_kernel_packages() {
    # Check if the kernel-devel package is already installed
    if rpm -q $KERNEL_DEVEL_PKG &> /dev/null; then
        echo "$KERNEL_DEVEL_PKG is already installed."
    else
        echo "Installing $KERNEL_DEVEL_PKG ..."
		if [ ! -f $KERNEL_DEVEL_PKG_PATH ]; then
			echo "Error: File not found: $KERNEL_DEVEL_PKG_PATH"
			exit 1
		fi
        rpm -ivh $KERNEL_DEVEL_PKG_PATH
    fi

    # Check if the kernel-headers package is already installed
    if rpm -q $KERNEL_HEADERS_PKG &> /dev/null; then
        echo "$KERNEL_HEADERS_PKG is already installed."
    else
        echo "Installing $KERNEL_HEADERS_PKG ..."
		if [ ! -f $KERNEL_HEADERS_PKG_PATH ]; then
			echo "Error: File not found: $KERNEL_HEADERS_PKG_PATH"
			exit 1
		fi
        rpm -ivh $KERNEL_HEADERS_PKG_PATH
    fi
}

# Modify the RDMA driver file
modify_rdma_driver() {
    local file_path="/lib/modules/$KERNEL/build/include/uapi/rdma/ib_user_ioctl_verbs.h"
    echo "Modifying file $file_path ..."
    
    # Check if the file exists
    if [ ! -f $file_path ]; then
        echo "Error: File not found: $file_path"
        exit 1
    fi

    # Check if the modification already exists
    if grep -q "RDMA_DRIVER_RIB" $file_path; then
        echo "Modification already exists in the file."
    else
        # Use sed to insert RDMA_DRIVER_RIB after RDMA_DRIVER_SIW
        sed -i '/RDMA_DRIVER_SIW/a\        RDMA_DRIVER_RIB,' $file_path
        echo "Modification completed."
    fi
}

install_deps() {
    local dep_pkgs=("$@")
    for pkg in "${dep_pkgs[@]}"; do
        if rpm -q $pkg &> /dev/null; then
            echo "$pkg already installed"
            continue
        else
            echo "Install $pkg..."
            sudo yum install -y $pkg
            if [ $? -eq 0 ]; then
                echo "$pkg installed successful"
            else
                echo "$pkg installed failed"
            fi
        fi
    done
}

update_rdma_core() {
	echo $SPLIT_LINE
	# local dep_pkgs=("cmake" "libnl3" "libnl3-devel")
	install_deps "${RDMA_CORE_DEP_PKGS[@]}"

	rdma_core_path="$RDMA_ROOT_DIR/rdma-core"
	bak_rdma_core_path="$RDMA_ROOT_DIR/rdma-core_bak_$TIME_STR"
	if [ -d "$rdma_core_path" ]; then
		echo "Backup existing rdma-core directory ..."
		mv $rdma_core_path $bak_rdma_core_path
	fi
	cd $RDMA_ROOT_DIR
	echo "Download new rdma-core ..."
	git clone http://$USERNAME:$PASSWD@$GITLAB_ADDR/$PROJECT/rdma-core.git
	cd $RDMA_ROOT_DIR/rdma-core
	echo "Change rdma-core branch to $RDMA_CORE_BRANCH"
	git checkout $RDMA_CORE_BRANCH
	git branch
	echo "Compile new rdma-core ..."
	bash build.sh
	if [ $? -eq 0 ]; then
		echo "Compile rdma-core success!"
	else
		echo "Compile rdma-core failed!"
	fi
	echo $SPLIT_LINE
}

update_rib_drv() {
	echo $SPLIT_LINE
	rib_drv_path="$RDMA_ROOT_DIR/rib_driver"
	bak_rib_drv_path="$RDMA_ROOT_DIR/rib_driver_bak_$TIME_STR"
	if [ -d "$rib_drv_path" ]; then
		echo "Backup existing rib_driver directory ..."
		mv $rib_drv_path $bak_rib_drv_path
	fi
	cd $RDMA_ROOT_DIR
	echo "Download new rib_driver ..."
	git clone http://$USERNAME:$PASSWD@$GITLAB_ADDR/$PROJECT/rib_driver.git
	cd $RDMA_ROOT_DIR/rib_driver
	echo "Change rib_driver branch to $RIB_DRV_BRANCH"
	git checkout $RIB_DRV_BRANCH
	git branch
	echo "Compile new rib_driver ..."
	make
	if [ $? -eq 0 ]; then
		echo "Compile rib_driver success!"
	else
		echo "Compile rib_driver failed!"
	fi
	echo $SPLIT_LINE
}

update_rqos() {
    echo $SPLIT_LINE
	# local dep_pkgs=("yaml-cpp" "yaml-cpp-devel" "yaml-cpp-static")
	install_deps "${RQOS_DEP_PKGS[@]}"

    rqos_path="$RDMA_ROOT_DIR/rqos"
    bak_rqos_path="$RDMA_ROOT_DIR/rqos_bak_$TIME_STR"

    if ! command -v expect &> /dev/null; then
        echo "Expect is not installed. Installing expect..."
        sudo yum install -y expect
    fi

    if [ -d "$rqos_path" ]; then
        echo "Backup existing rqos directory ..."
        mv $rqos_path $bak_rqos_path
    fi
    
    cd $RDMA_ROOT_DIR
    echo "Download new rqos ..."
    git clone http://$USERNAME:$PASSWD@$GITLAB_ADDR/$PROJECT/rqos.git
	cd $RDMA_ROOT_DIR/rqos
	echo "Change rqos branch to $RQOS_BRANCH"
	git checkout $RQOS_BRANCH
	git branch
    echo "Update submodules for rqos ..."
	
    expect <<EOF
        log_user 1
        spawn git submodule update --init --recursive
        set timeout 120
        expect {
            "Username for 'http://$GITLAB_ADDR':" { send "$USERNAME\r"; exp_continue }
            "Password for 'http://$USERNAME@$GITLAB_ADDR':" { send "$PASSWD\r"; exp_continue }
            -re "Submodule path 'rdriver': checked out.*" { exp_continue }
            timeout { puts "Timed out waiting for submodule update"; exit 1 }
        }
        interact
EOF
	echo "Compile new rqos ..."
    make && make install
    if [ $? -eq 0 ]; then
        echo "Compile rqos success!"
    else
        echo "Compile rqos failed!"
    fi

    echo $SPLIT_LINE
}

update_rib_cli() {
	echo $SPLIT_LINE
	rib_cli_path="$RDMA_ROOT_DIR/rib_cli"
	bak_rib_cli_path="$RDMA_ROOT_DIR/rib_cli_bak_$TIME_STR"
	if [ -d "$rib_cli_path" ]; then
		echo "Backup existing rib_cli directory ..."
		mv $rib_cli_path $bak_rib_cli_path
	fi
	cd $RDMA_ROOT_DIR
	echo "Download new rib_cli ..."
	git clone http://$USERNAME:$PASSWD@$GITLAB_ADDR/$PROJECT/rib_cli.git
	cd $RDMA_ROOT_DIR/rib_cli
	echo "Change rib_cli branch to $RIB_CLI_BRANCH"
	git checkout $RIB_CLI_BRANCH
	git branch
	echo "Compile new rib_cli ..."
	make
	if [ $? -eq 0 ]; then
		echo "Compile rib_cli success!"
	else
		echo "Compile rib_cli failed!"
	fi
	echo $SPLIT_LINE
}

update_rft() {
	echo $SPLIT_LINE
	rft_path="$RDMA_ROOT_DIR/rft"
	bak_rft_path="$RDMA_ROOT_DIR/rft_bak_$TIME_STR"
	if [ -d "$rft_path" ]; then
		echo "Backup existing rft directory ..."
		mv $rft_path $bak_rft_path
	fi
	cd $RDMA_ROOT_DIR
	echo "Download new rft ..."
	git clone http://$USERNAME:$PASSWD@$GITLAB_ADDR/$PROJECT/rft.git
	cd $RDMA_ROOT_DIR/rft
	echo "Change rft branch to $RFT_BRANCH"
	git checkout $RFT_BRANCH
	git branch
	echo "Compile new rft ..."
	make
	if [ $? -eq 0 ]; then
		echo "Compile rft success!"
	else
		echo "Compile rft failed!"
	fi
	echo $SPLIT_LINE
}

update_perftest() {
	echo $SPLIT_LINE
	# local dep_pkgs=("pciutils-devel" "libibverbs" "libibverbs-devel")
	install_deps "${PERFTEST_DEP_PKGS[@]}"

	# if rpm -q pciutils-devel &> /dev/null; then
	# 	continue
	# else
	# 	echo "Install pciutils-devel..."
	# 	sudo dnf install -y pciutils-devel
	# 	if [ $? -eq 0 ]; then
	# 		echo "pciutils-devel installed successful"
	# 	else
	# 		echo "pciutils-devel installed failed"
	# 	fi
	# fi
	echo $SPLIT_LINE
	perftest_path="$RDMA_ROOT_DIR/perftest"
	bak_perftest_path="$RDMA_ROOT_DIR/perftest_bak_$TIME_STR"
	if [ -d "$perftest_path" ]; then
		echo "Backup existing perftest directory ..."
		mv $perftest_path $bak_perftest_path
	fi
	cd $RDMA_ROOT_DIR
	echo "Download new perftest ..."
	git clone http://$PERFTEST_USERNAME:$PERFTEST_PASSWD@$GITLAB_ADDR/inspur_rdma/perftest.git
	cd $RDMA_ROOT_DIR/perftest
	echo "Change perftest branch to $PERFTEST_BRANCH"
	git checkout $PERFTEST_BRANCH
	git branch
	echo "Compile new perftest ..."
	./autogen.sh && ./configure && make
	if [ $? -eq 0 ]; then
		echo "Compile perftest success!"
	else
		echo "Compile perftest failed!"
	fi
	echo $SPLIT_LINE
}

main() {
	echo $SPLIT_LINE
	# install_kernel_packages
	# echo $SPLIT_LINE
	modify_rdma_driver
	echo $SPLIT_LINE
	echo "Set RDMA root dir path ..."
	echo "RDMA ROOT PATH --> $RDMA_ROOT_DIR"
	if [ $UPDATE_RDMA_CORE = "true" ]; then
		update_rdma_core
	fi
	if [ $UPDATE_RIB_DRV = "true" ]; then
		update_rib_drv
	fi
	if [ $UPDATE_RQOS = "true" ]; then
		update_rqos
	fi
	if [ $UPDATE_RIB_CLI = "true" ]; then
		update_rib_cli
	fi
	if [ $UPDATE_RFT = "true" ]; then
		update_rft
	fi
	if [ $UPDATE_PERFTEST = "true" ]; then
		update_perftest
	fi
	echo $SPLIT_LINE
}

main
