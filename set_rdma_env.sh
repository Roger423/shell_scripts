#!/bin/bash

SPLIT_LINE="-----------------------------------------------------------------------------------------------------------"
ACTION="set"
RDMA_ROOT_DIR="/home/rdma"
SET_RDMA_CORE="true"
SET_RIB_DRV="true"
SET_RQOS="true"
SET_RIB_CLI="true"
SET_RFT="true"
SET_PERFTEST="true"
SET_ENV_FILE="$(realpath "$HOME/.bashrc")"

print_help() {
    cat << EOF
$SPLIT_LINE
Put RDMA software (rdma-core, rib_driver, rib_cli, rft, perftest) in the same directory, such as $RDMA_ROOT_DIR.
Then use this script to set the environment variable for RDMA test.
After running this script, the RDMA environment variables are set permanently and do not need to be reset even after 
the host is restarted. If the RDMA software directory changes, re-running this script to set the RDMA environment 
variables will replace the existing RDMA environment variable settings.

Usage:
    $0 -h or $0 help or $0 --help
    or
    $0 rdma_root=<rdma root path> rdma_core=<if set rdma-core env> rib_drv=<if set rib_driver env> rqos=<if set rqos env> \
rib_cli=<if set rib_driver env> rft=<if set rft env> perftest=<if set perftest env>

Arguments:
	action:     the action of running this script(set/clear), to set RDMA env variable or clear RDMA env variable.
    rdma_root:  the RDMA software path where "rdma-core, rib_driver, rib_cli, rft, perftest" are located. 
	            Default is $RDMA_ROOT_DIR
    rdma_core:  whether to set the environment variables of rdma-core software (true/false), default is true
    rib_drv:    whether to set the environment variables of rib_driver software (true/false), default is true
    rqos:       whether to set the environment variables of rqos software (true/false), default is true
    rib_cli:    whether to set the environment variables of rib_cli software (true/false), default is true
    rft:        whether to set the environment variables of rft software (true/false), default is true
    perftest:   whether to set the environment variables of perftest software (true/false), default is true

Examples:
    Set environment variables for all software, with the RDMA root path as $RDMA_ROOT_DIR:
        bash $0

    Set environment variables for all software, with the RDMA root path as /home/test/rdma/:
        bash $0 rdma_root=/home/test/rdma/

    Set environment variables for only rdma-core, with the RDMA root path as default $RDMA_ROOT_DIR:
        bash $0 rib_drv=false rqos=false rib_cli=false rft=false perftest=false
	
	Clear environment variables of RDMA:
		bash $0 action=clear
$SPLIT_LINE
EOF
}

for arg in "$@"
do
	case $arg in
		action=*)
			ACTION="${arg#*=}"
			;;
		rdma_root=*)
			RDMA_ROOT_DIR="${arg#*=}"
			;;
		rdma_core=*)
			SET_RDMA_CORE="${arg#*=}"
			;;
		rib_drv=*)
			SET_RIB_DRV="${arg#*=}"
			;;
		rqos=*)
			SET_RQOS="${arg#*=}"
			;;
		rib_cli=*)
			SET_RIB_CLI="${arg#*=}"
			;;
		rft=*)
			SET_RFT="${arg#*=}"
			;;
		perftest=*)
			SET_PERFTEST="${arg#*=}"
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

set_rdma_root() {
	if ! grep -q "# RDMA ENV SETTING" $SET_ENV_FILE; then
		echo "# RDMA ENV SETTING" >> $SET_ENV_FILE
	fi

	if ! grep -q "export RDMA_ROOT=$RDMA_ROOT_DIR" $SET_ENV_FILE; then
		if grep -q "export RDMA_ROOT=" $SET_ENV_FILE; then
			sed -i '/export RDMA_ROOT=/d' $SET_ENV_FILE
		fi
		sed -i "/# RDMA ENV SETTING/a export RDMA_ROOT=$RDMA_ROOT_DIR" $SET_ENV_FILE
	fi
}

set_lib_path() {
    if ! grep -q "export LIBRARY_PATH=\$LIBRARY_PATH:\$RDMA_CORE/lib" "$SET_ENV_FILE"; then
        sed -i "/export RDMA_CORE=/a export LIBRARY_PATH=\$LIBRARY_PATH:\$RDMA_CORE/lib" "$SET_ENV_FILE"
    fi
}

set_ld_lib_path() {
    if ! grep -q "export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:\$RDMA_CORE/lib" "$SET_ENV_FILE"; then
        sed -i "/export LIBRARY_PATH=/a export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:\$RDMA_CORE/lib" "$SET_ENV_FILE"
    fi
}

set_pkg_config_path() {
    if ! grep -q "export PKG_CONFIG_PATH=\$RDMA_CORE/lib/pkgconfig:\$PKG_CONFIG_PATH" "$SET_ENV_FILE"; then
        sed -i "/export LD_LIBRARY_PATH=/a export PKG_CONFIG_PATH=\$RDMA_CORE/lib/pkgconfig:\$PKG_CONFIG_PATH" \
		"$SET_ENV_FILE"
    fi
}

# set_c_include_path() {
#     if ! grep -q "export C_INCLUDE_PATH=\$C_INCLUDE_PATH:\$RDMA_CORE/include" "$SET_ENV_FILE"; then
#         sed -i "/export PKG_CONFIG_PATH=/a export C_INCLUDE_PATH=\$C_INCLUDE_PATH:\$RDMA_CORE/include" "$SET_ENV_FILE"
#     fi
# }

# set_cplus_include_path() {
#     if ! grep -q "export CPLUS_INCLUDE_PATH=\$CPLUS_INCLUDE_PATH:\$RDMA_CORE/include" "$SET_ENV_FILE"; then
#         sed -i "/export C_INCLUDE_PATH=/a export CPLUS_INCLUDE_PATH=\$CPLUS_INCLUDE_PATH:\$RDMA_CORE/include" \
# 		"$SET_ENV_FILE"
#     fi
# }

set_rdma_core_env() {
    if ! grep -q "export RDMA_CORE=\$RDMA_ROOT/rdma-core/build" "$SET_ENV_FILE"; then
        sed -i "/export RDMA_ROOT=/a export RDMA_CORE=\$RDMA_ROOT/rdma-core/build" "$SET_ENV_FILE"
    fi
	set_lib_path
	set_ld_lib_path
	set_pkg_config_path
	# set_c_include_path
	# set_cplus_include_path
    if ! grep -q "export PATH=\$RDMA_CORE/bin:\$PATH" "$SET_ENV_FILE"; then
		sed -i "/export LD_LIBRARY_PATH=/a export PATH=\$RDMA_CORE/bin:\$PATH" "$SET_ENV_FILE"
    fi
}

set_rib_drv_env() {
	RIB_DIR=$RDMA_ROOT_DIR/rib_driver
	RIB_DRV_PATH=$RIB_DIR/rib.ko
    if ! grep -q "export RIB_DRV_PATH=$RIB_DRV_PATH" "$SET_ENV_FILE"; then
        echo "export RIB_DRV_PATH=$RIB_DRV_PATH" >> "$SET_ENV_FILE"
    fi
}

set_rqos_env() {
	RQOS_DIR=$RDMA_ROOT_DIR/rqos
	RQOS_PATH=$RQOS_DIR/rqos.ko
    if ! grep -q "export RQOS_PATH=$RQOS_PATH" "$SET_ENV_FILE"; then
        echo "export RQOS_PATH=$RQOS_PATH" >> "$SET_ENV_FILE"
    fi
}

set_rib_cli_env() {
    if ! grep -q "export RIB_CLI_PATH=$RDMA_ROOT_DIR/rib_cli" "$SET_ENV_FILE"; then
        echo "export RIB_CLI_PATH=$RDMA_ROOT_DIR/rib_cli" >> "$SET_ENV_FILE"
    fi
    if ! grep -q "export PATH=\$RIB_CLI_PATH:\$PATH" "$SET_ENV_FILE"; then
		sed -i "/export RIB_CLI_PATH=/a export PATH=\$RIB_CLI_PATH:\$PATH" "$SET_ENV_FILE"
    fi
}

set_rft_env() {
    if ! grep -q "export RFT_PATH=$RDMA_ROOT_DIR/rft" "$SET_ENV_FILE"; then
        echo "export RFT_PATH=$RDMA_ROOT_DIR/rft" >> "$SET_ENV_FILE"
    fi
    if ! grep -q "export PATH=\$RFT_PATH:\$PATH" "$SET_ENV_FILE"; then
		sed -i "/export RFT_PATH=/a export PATH=\$RFT_PATH:\$PATH" "$SET_ENV_FILE"
    fi
}

set_perftest_env() {
    if ! grep -q "export PERFTEST_PATH=$RDMA_ROOT_DIR/perftest" "$SET_ENV_FILE"; then
        echo "export PERFTEST_PATH=$RDMA_ROOT_DIR/perftest" >> "$SET_ENV_FILE"
    fi
    if ! grep -q "export PATH=\$PERFTEST_PATH:\$PATH" "$SET_ENV_FILE"; then
		sed -i "/export PERFTEST_PATH=/a export PATH=\$PERFTEST_PATH:\$PATH" "$SET_ENV_FILE"
    fi
}

clear_env_var() {
	echo $SPLIT_LINE
	echo "Clear RDMA env variable ..."
	sed -i '/# RDMA ENV SETTING/,$d' $HOME/.bashrc
	source $HOME/.bashrc
	CURRENT_PATH=$PATH
	NEW_PATH=$(echo $CURRENT_PATH | tr ':' '\n' | grep -v "/home/rdma/" | tr '\n' ':')
	NEW_PATH=$(echo $NEW_PATH | sed 's/:$//')
	export PATH=$NEW_PATH
	echo "PATH env variable after clear RDMA path: "
	echo $PATH
	echo $SPLIT_LINE
}

main() {
	if [ ! -f "$SET_ENV_FILE.bak" ]; then
		echo $SPLIT_LINE
		echo "Backup $SET_ENV_FILE"
		cp "$SET_ENV_FILE" "$SET_ENV_FILE.bak"
		echo "Backup of $SET_ENV_FILE created as $SET_ENV_FILE.bak"
	fi
	if [ $ACTION = "clear" ]; then
		clear_env_var
		exit 0
	fi
	echo $SPLIT_LINE
	echo "Set RDMA root dir path ..."
	echo "RDMA ROOT PATH --> $RDMA_ROOT_DIR"
	set_rdma_root
	if [ $SET_RDMA_CORE = "true" ]; then
		echo $SPLIT_LINE
		echo "Set rdma-core env ..."
		set_rdma_core_env
	fi
	if [ $SET_RIB_DRV = "true" ]; then
		echo $SPLIT_LINE
		echo "Set rib dirver env ..."
		set_rib_drv_env
	fi
	if [ $SET_RQOS = "true" ]; then
		echo $SPLIT_LINE
		echo "Set rqos env ..."
		set_rqos_env
	fi
	if [ $SET_RIB_CLI = "true" ]; then
		echo $SPLIT_LINE
		echo "Set rib_cli env ..."
		set_rib_cli_env
	fi
	if [ $SET_RFT = "true" ]; then
		echo $SPLIT_LINE
		echo "Set rft env ..."
		set_rft_env
	fi
	if [ $SET_PERFTEST = "true" ]; then
		echo $SPLIT_LINE
		echo "Set perftest env ..."
		set_perftest_env
	fi
	echo $SPLIT_LINE
	echo "Content of file $SET_ENV_FILE:"
	cat $SET_ENV_FILE
	echo $SPLIT_LINE
	echo "Loading new RDMA env setting..."
	source $SET_ENV_FILE
	echo $SPLIT_LINE
	echo "PATH env variable:"
	echo $PATH
	echo $SPLIT_LINE
	if [ $? -eq 0 ]; then
		echo "RDMA env setting done!"
	else
		echo "RDMA env setting failed!"
	fi
	echo $SPLIT_LINE
}

main
