#!/bin/bash

SPLIT_LINE="-----------------------------------------------------------------------------------------------------------"
USERNAME="luoshanguo"
PASSWORD="luoshanguo"
LOCAL_DIR="/home/rdma"
FILE_TYPE="rpd"

# 显示帮助信息
usage() {
    echo $SPLIT_LINE
    echo "Usage: $0 -f file_url [-u username] [-p password] [-l local_dir] [-t file_type]"
    echo "  -t all: Download all files recursively from the specified directory, preserving directory structure."
    echo $SPLIT_LINE
    exit 1
}

# 检查并安装smbclient
install_smbclient() {
    if ! command -v smbclient &> /dev/null; then
        echo "smbclient not found, installing..."
        if [ -f /etc/centos-release ] || [ -f /etc/redhat-release ]; then
            # CentOS/RHEL
            sudo yum install -y samba-client
        elif [ -f /etc/lsb-release ] || [ -f /etc/os-release ]; then
            # Ubuntu/Debian
            sudo apt-get update
            sudo apt-get install -y smbclient
        else
            echo "Unsupported operating system."
            exit 1
        fi
        echo "smbclient installed successfully."
    else
        echo "smbclient is already installed."
    fi
}

# 处理URL
process_url() {
    local url="$1"
    url=$(echo ${url} | sed -E 's/^\\\\//; s/\\/ /g')
    echo "$url" | sed -E 's|^[^:]+://||; s|/| |g'
}

smb_download_file() {
    local dfile=$1
    local rdir=$2
    local ldir=$3
    echo $SPLIT_LINE
    echo "Downloading file $dfile from remote dir $rdir and save to local dir $ldir ..."
    smbclient "//$SERVER/$SHARE" -U "$USERNAME%$PASSWORD" -c "cd $rdir; lcd $ldir; get $dfile"
    echo $SPLIT_LINE
    if [ $? -eq 0 ]; then
        echo "Download $dfile success, saved to: $ldir/$dfile"
    else
        echo "Download $dfile failed"
        return
    fi

    lmd5=$(md5sum "$ldir/$dfile" | awk '{print $1}')

    echo $SPLIT_LINE
    echo "Calculate MD5 for $ldir/$dfile:"
    echo "MD5: $lmd5"
    echo $SPLIT_LINE
}

# 递归下载目录和文件
recursive_download() {
    local remote_dir="$1"
    local local_base_dir="$2"
    echo $SPLIT_LINE
    echo "Remote dir: $remote_dir"
    echo "Local base dir: $local_base_dir"
    echo $SPLIT_LINE

    # 在本地创建对应的目录结构
    local remote_rel_dir=""
    local remote_base_dir=$(basename $remote_dir)
    # remote_rel_dir="$remote_rel_dir/$remote_base_dir"
    local local_dir="$local_base_dir/$remote_base_dir"
    echo "Create local dir $local_dir"
    mkdir -p "$local_dir"

    # 获取远程目录内容
    echo $SPLIT_LINE
    echo "File list at remote dir $remote_dir"
    smbclient "//$SERVER/$SHARE" -U "$USERNAME%$PASSWORD" -c "cd $remote_dir; ls"
    echo $SPLIT_LINE
    local dir_listing
    dir_listing=$(smbclient "//$SERVER/$SHARE" -U "$USERNAME%$PASSWORD" -c "cd $remote_dir; ls")
    filtered_lines=$(echo "$dir_listing" | grep -vE '^\s*\.{1,2}\s' | grep -vE 'blocks of size')
    if [ $? -ne 0 ]; then
        echo "Failed to list directory $remote_dir"
        return 1
    fi

    # 解析目录中的文件和子目录
    while IFS= read -r line; do
        # 跳过无关行
        if [[ "$line" =~ ^\s*\.+$ || "$line" =~ NT_STATUS ]]; then
            continue
        fi

        # 提取文件名或目录名
        local item_name=$(echo "$line" | awk '{print $1}')
        echo "Process remote item $item_name under remote dir $remote_dir"
        if [[ "$item_name" = "." || "$item_name" = ".." ]]; then
            echo "Ignore $item_name"
            continue
        fi
        local is_dir=$(echo "$line" | grep -o "D.*$")

        if [ -n "$is_dir" ]; then
            # 是目录，递归调用
            local new_remote_dir="$remote_dir/$item_name"
            new_remote_dir=$(echo "$new_remote_dir" | sed 's|^/||')
            echo "New remote dir $new_remote_dir"
            recursive_download "$new_remote_dir" "$local_dir"
        else
            # 是文件，下载
            smb_download_file "$item_name" "$remote_dir" "$local_dir"
        fi
    done <<< "$filtered_lines"
}

# 解析参数
while getopts "f:u:p:l:t:" opt; do
    case "$opt" in
        f) FILE_URL="$OPTARG" ;;
        u) USERNAME="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        l) LOCAL_DIR="$OPTARG" ;;
        t) FILE_TYPE="$OPTARG" ;;
        *) usage ;;
    esac
done

# 检查参数是否为空
if [ -z "$FILE_URL" ]; then
    usage
fi

# 安装smbclient
install_smbclient

echo "file URL: $FILE_URL"
url_seg=$(process_url "$FILE_URL")
echo "Processed URL: $url_seg"

# 提取服务器地址、共享目录和文件路径
SERVER=$(echo $url_seg | awk '{print $1}')
SHARE=$(echo $url_seg | awk '{print $2}')
url_seg_list=($url_seg)
DIR_PATH=""
for ((i=2; i<${#url_seg_list[@]}; i++)); do
    DIR_PATH="${DIR_PATH}/${url_seg_list[$i]}"
done
DIR_PATH=$(echo "$DIR_PATH" | sed 's|^/||')

echo $SPLIT_LINE
echo "SERVER   :  $SERVER"
echo "SHARE    :  $SHARE"
echo "DIR_PATH :  $DIR_PATH"
echo "FILE_TYPE:  $FILE_TYPE"
echo $SPLIT_LINE

# 检查并创建本地目录
if [ ! -d "$LOCAL_DIR" ]; then
    echo $SPLIT_LINE
    echo "Local directory $LOCAL_DIR does not exist. Creating..."
    mkdir -p "$LOCAL_DIR"
    echo "Directory $LOCAL_DIR created."
    echo $SPLIT_LINE
fi

# 判断是否为 -t all 模式
if [ "$FILE_TYPE" == "all" ]; then
    echo "Starting recursive download of all files from $DIR_PATH..."
    recursive_download "$DIR_PATH" "$LOCAL_DIR"
    echo $SPLIT_LINE
    echo "Recursive download completed."
    exit 0
fi

# 原有逻辑：下载指定类型的文件
if [[ "$DIR_PATH" == *.$FILE_TYPE ]]; then
    dowload_dir_path=$(dirname "$DIR_PATH")
    dowload_filename=$(basename "$DIR_PATH")
else
    dowload_dir_path="$DIR_PATH"
fi

# 使用 smbclient 列出目录中的文件
DIR_LISTING=$(smbclient "//$SERVER/$SHARE" -U "$USERNAME%$PASSWORD" -c "cd $dowload_dir_path; ls")
echo "Directory listing:"
echo "$DIR_LISTING"
echo $SPLIT_LINE

download_files=""
if [ -z "$dowload_filename" ]; then
    download_files=$(echo "$DIR_LISTING" | grep -oP "\S+\.${FILE_TYPE}")
else
    download_files=$(echo "$DIR_LISTING" | grep -oP "$dowload_filename")
fi

echo "Download Files:"
echo "$download_files"
echo $SPLIT_LINE

# 检查是否找到指定类型的文件
if [ -z "$download_files" ]; then
    echo $SPLIT_LINE
    if [ -z "$dowload_filename" ]; then
        echo "No .$FILE_TYPE files found in the specified directory."
    else
        echo "File $dowload_filename not found in the specified directory."
    fi
    echo $SPLIT_LINE
    exit 1
fi

# 下载所有指定类型的文件并计算MD5值
for dfile in $download_files; do
    smb_download_file "$dfile" "$dowload_dir_path" "$LOCAL_DIR"
done
echo $SPLIT_LINE
