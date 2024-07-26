#!/usr/bin/env bash
# File name: wgcf.sh
# Description: Install latest version wgcf
# System Required: GNU/Linux
# Version: 1.2
#

set -o errexit
set -o errtrace
set -o pipefail

Green_font_prefix="\033[32m"
Red_font_prefix="\033[31m"
Green_background_prefix="\033[42;37m"
Red_background_prefix="\033[41;37m"
Font_color_suffix="\033[0m"
INFO="[${Green_font_prefix}INFO${Font_color_suffix}]"
ERROR="[${Red_font_prefix}ERROR${Font_color_suffix}]"

PROJECT_NAME='wgcf'
GH_API_URL='https://api.github.com/repos/ViRb3/wgcf/releases/latest'
BIN_DIR='/usr/local/bin'
BIN_NAME='wgcf'
BIN_FILE="${BIN_DIR}/${BIN_NAME}"

if [[ $(uname -s) != Linux ]]; then
    echo -e "${ERROR} This operating system is not supported."
    exit 1
fi

if [[ $(id -u) != 0 ]]; then
    echo -e "${ERROR} This script must be run as root."
    exit 1
fi

echo -e "${INFO} Get CPU architecture ..."
if [[ $(command -v apk) ]]; then
    PKGT='(apk)'
    OS_ARCH=$(apk --print-arch)
elif [[ $(command -v dpkg) ]]; then
    PKGT='(dpkg)'
    OS_ARCH=$(dpkg --print-architecture | awk -F- '{ print $NF }')
else
    OS_ARCH=$(uname -m)
fi
case ${OS_ARCH} in
*86)
    FILE_KEYWORD='linux_386'
    ;;
x86_64 | amd64)
    FILE_KEYWORD='linux_amd64'
    ;;
aarch64 | arm64)
    FILE_KEYWORD='linux_arm64'
    ;;
arm*)
    FILE_KEYWORD='linux_armv7'
    ;;
*)
    echo -e "${ERROR} Unsupported architecture: ${OS_ARCH} ${PKGT}"
    exit 1
    ;;
esac
echo -e "${INFO} Architecture: ${OS_ARCH} ${PKGT}"

echo -e "${INFO} Get ${PROJECT_NAME} download URL ..."

	# 尝试获取 IPv4 地址
    LOCAL_IP=$(curl -s -4 https://api.ipify.org || true)

    # 检查 IPv4 是否为空或不合法
    if [[ -z "$LOCAL_IP" || ! "$LOCAL_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # 获取 IPv6 地址
        LOCAL_IP=$(curl -s -6 https://api64.ipify.org || true)

        # 检查 IPv6 是否为空或不合法
        if [[ -z "$LOCAL_IP" || ! "$LOCAL_IP" =~ ^([0-9a-fA-F:]+)$ ]]; then
            echo -e "${INFO} 未能获取到有效的公网 IP 地址。"
            return 1
        else
		    cat >> /etc/hosts << EOF
# https://danwin1210.de/github-ipv6-proxy.php
2a01:4f8:c010:d56::2 github.com
2a01:4f8:c010:d56::3 api.github.com
2a01:4f8:c010:d56::4 codeload.github.com
2a01:4f8:c010:d56::5 objects.githubusercontent.com
2a01:4f8:c010:d56::6 ghcr.io
2a01:4f8:c010:d56::7 pkg.github.com npm.pkg.github.com maven.pkg.github.com nuget.pkg.github.com rubygems.pkg.github.com
EOF
            DOWNLOAD_URL=https://github.com/ViRb3/wgcf/releases/download/v2.2.22/wgcf_2.2.22_${FILE_KEYWORD}
        fi
    else
        DOWNLOAD_URL=$(curl -fsSL ${GH_API_URL} | grep 'browser_download_url' | cut -d'"' -f4 | grep "${FILE_KEYWORD}")
    fi

echo -e "${INFO} Download URL: ${DOWNLOAD_URL}"

echo -e "${INFO} Installing ${PROJECT_NAME} ..."
curl -LS "${DOWNLOAD_URL}" -o ${BIN_FILE}
chmod +x ${BIN_FILE}
if [[ ! $(echo ${PATH} | grep ${BIN_DIR}) ]]; then
    ln -sf ${BIN_FILE} /usr/bin/${BIN_NAME}
fi
if [[ -s ${BIN_FILE} && $(${BIN_NAME} -h) ]]; then
    echo -e "${INFO} Done."
else
    echo -e "${ERROR} ${PROJECT_NAME} installation failed !"
    exit 1
fi
