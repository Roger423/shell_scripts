#!/bin/bash

SPLIT_LINE="-----------------------------------------------------------------------------------------------------------"
RDMA_ROOT_DIR="/home/rdma"
UPDATE_RDMA_CORE="true"
UPDATE_RIB_DRV="true"
UPDATE_RQOS="true"
UPDATE_RIB_CLI="true"
UPDATE_RFT="true"
UPDATE_PERFTEST="false"
USERNAME="build"
PASSWD="123456789"
GITLAB_ADDR="192.168.65.225"
PROJECT="c3000"
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
    $0 rdma_root=<rdma root path> rdma_core=<if update rdma-core> rib_drv=<if update rib_driver> rqos=<if update rqos> \
rib_cli=<if update rib_driver> rft=<if update rft> perftest=<if update perftest>

Arguments:
    rdma_root:  the RDMA software path where "rdma-core, rib_driver, rib_cli, rft, perftest" are located.
                Default is $RDMA_ROOT_DIR
    rdma_core:  whether to update rdma-core software (true/false), default is true
    rib_drv:    whether to update rib_driver software (true/false), default is true
    rqos:       whether to update rqos software (true/false), default is true
    rib_cli:    whether to update rib_cli software (true/false), default is true
    rft:        whether to update rft software (true/false), default is true
    perftest:   whether update perftest software (true/false), default is true

Examples:
    update all software, with the RDMA root path as $RDMA_ROOT_DIR:
        bash $0

    update all software, with the RDMA root path as /home/test/rdma/:
        bash $0 rdma_root=/home/test/rdma/

    update only rdma-core, with the RDMA root path as default $RDMA_ROOT_DIR:
        bash $0 rib_drv=false rqos=false rib_cli=false rft=false perftest=false

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
		rib_drv=*)
			UPDATE_RIB_DRV="${arg#*=}"
			;;
		rqos=*)
			UPDATE_RQOS="${arg#*=}"
			;;
		rib_cli=*)
			UPDATE_RIB_CLI="${arg#*=}"
			;;
		rft=*)
			UPDATE_RFT="${arg#*=}"
			;;
		perftest=*)
			UPDATE_PERFTEST="${arg#*=}"
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

update_rdma_core() {
	echo $SPLIT_LINE
	rdma_core_path="$RDMA_ROOT_DIR/rdma-core"
	bak_rdma_core_path="$RDMA_ROOT_DIR/rdma-core_bak_$TIME_STR"
	if [ -d "$rdma_core_path" ]; then
		echo "Backup existing rdma-core directory ..."
		mv $rdma_core_path $bak_rdma_core_path
	fi
	cd $RDMA_ROOT_DIR
	echo "Download new rdma-core ..."
	git clone http://$USERNAME:$PASSWD@$GITLAB_ADDR/$PROJECT/rdma-core.git
	echo "Compile new rdma-core ..."
	cd $RDMA_ROOT_DIR/rdma-core
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
	bak_rib_drv_path="$RDMA_ROOT_DIR/rib_drv_bak_$TIME_STR"
	if [ -d "$rib_drv_path" ]; then
		echo "Backup existing rib_driver directory ..."
		mv $rib_drv_path $bak_rib_drv_path
	fi
	cd $RDMA_ROOT_DIR
	echo "Download new rib_driver ..."
	git clone http://$USERNAME:$PASSWD@$GITLAB_ADDR/$PROJECT/rib_driver.git
	echo "Compile new rib_driver ..."
	cd $RDMA_ROOT_DIR/rib_driver
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
    echo "Compile new rqos ..."
    cd $RDMA_ROOT_DIR/rqos

    expect <<EOF
        spawn git submodule update --init --recursive
        expect "Username for 'http://$GITLAB_ADDR':"
        send "$USERNAME\r"
        expect "Password for 'http://$USERNAME@$GITLAB_ADDR':"
        send "$PASSWD\r"
		expect "Submodule path 'rdriver': checked out"
        interact
EOF
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
	echo "Compile new rib_cli ..."
	cd $RDMA_ROOT_DIR/rib_cli
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
	echo "Compile new rft ..."
	cd $RDMA_ROOT_DIR/rft
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
	perftest_path="$RDMA_ROOT_DIR/perftest"
	bak_perftest_path="$RDMA_ROOT_DIR/perftest_bak_$TIME_STR"
	if [ -d "$perftest_path" ]; then
		echo "Backup existing perftest directory ..."
		mv $perftest_path $bak_perftest_path
	fi
	cd $RDMA_ROOT_DIR
	echo "Download new perftest ..."
	git clone http://$USERNAME:$PASSWD@$GITLAB_ADDR/inspur_rdma/perftest.git
	echo "Compile new perftest ..."
	cd $RDMA_ROOT_DIR/perftest
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
