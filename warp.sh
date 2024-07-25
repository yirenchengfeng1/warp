#!/usr/bin/env bash
# Description: Cloudflare WARP Installer
# System Required: Debian, Ubuntu, Fedora, CentOS, Oracle Linux, Arch Linux
# Version: 1.0.40_Final


FontColor_Red="\033[31m"
FontColor_Red_Bold="\033[1;31m"
FontColor_Green="\033[32m"
FontColor_Green_Bold="\033[1;32m"
FontColor_Yellow="\033[33m"
FontColor_Yellow_Bold="\033[1;33m"
FontColor_Purple="\033[35m"
FontColor_Purple_Bold="\033[1;35m"
FontColor_Suffix="\033[0m"

log() {
    local LEVEL="$1"
    local MSG="$2"
    case "${LEVEL}" in
    INFO)
        local LEVEL="[${FontColor_Green}${LEVEL}${FontColor_Suffix}]"
        local MSG="${LEVEL} ${MSG}"
        ;;
    WARN)
        local LEVEL="[${FontColor_Yellow}${LEVEL}${FontColor_Suffix}]"
        local MSG="${LEVEL} ${MSG}"
        ;;
    ERROR)
        local LEVEL="[${FontColor_Red}${LEVEL}${FontColor_Suffix}]"
        local MSG="${LEVEL} ${MSG}"
        ;;
    *) ;;
    esac
    echo -e "${MSG}"
}

if [[ $(uname -s) != Linux ]]; then
    log ERROR "This operating system is not supported."
    exit 1
fi

if [[ $(id -u) != 0 ]]; then
    log ERROR "This script must be run as root."
    exit 1
fi

if [[ -z $(command -v curl) ]]; then
    log ERROR "cURL is not installed."
    exit 1
fi

WGCF_Profile='wgcf-profile.conf'
WGCF_ProfileDir="/etc/warp"
WGCF_ProfilePath="${WGCF_ProfileDir}/${WGCF_Profile}"

WireGuard_Interface='wgcf'
WireGuard_ConfPath="/etc/wireguard/${WireGuard_Interface}.conf"

WireGuard_Interface_DNS_IPv4='8.8.8.8,8.8.4.4'
WireGuard_Interface_DNS_IPv6='2001:4860:4860::8888,2001:4860:4860::8844'
WireGuard_Interface_DNS_46="${WireGuard_Interface_DNS_IPv4},${WireGuard_Interface_DNS_IPv6}"
WireGuard_Interface_DNS_64="${WireGuard_Interface_DNS_IPv6},${WireGuard_Interface_DNS_IPv4}"
WireGuard_Interface_Rule_table='51888'
WireGuard_Interface_Rule_fwmark='51888'
WireGuard_Interface_MTU='1280'

WireGuard_Peer_Endpoint_IP4='162.159.192.1'
WireGuard_Peer_Endpoint_IP6='2606:4700:d0::a29f:c001'
WireGuard_Peer_Endpoint_IPv4="${WireGuard_Peer_Endpoint_IP4}:2408"
WireGuard_Peer_Endpoint_IPv6="[${WireGuard_Peer_Endpoint_IP6}]:2408"
WireGuard_Peer_Endpoint_Domain='engage.cloudflareclient.com:2408'
WireGuard_Peer_AllowedIPs_IPv4='0.0.0.0/0'
WireGuard_Peer_AllowedIPs_IPv6='::/0'
WireGuard_Peer_AllowedIPs_DualStack='0.0.0.0/0,::/0'

TestIPv4_1='1.0.0.1'
TestIPv4_2='9.9.9.9'
TestIPv6_1='2606:4700:4700::1001'
TestIPv6_2='2620:fe::fe'
CF_Trace_URL='https://www.cloudflare.com/cdn-cgi/trace'

Get_System_Info() {
    source /etc/os-release
    SysInfo_OS_CodeName="${VERSION_CODENAME}"
    SysInfo_OS_Name_lowercase="${ID}"
    SysInfo_OS_Name_Full="${PRETTY_NAME}"
    SysInfo_RelatedOS="${ID_LIKE}"
    SysInfo_Kernel="$(uname -r)"
    SysInfo_Kernel_Ver_major="$(uname -r | awk -F . '{print $1}')"
    SysInfo_Kernel_Ver_minor="$(uname -r | awk -F . '{print $2}')"
    SysInfo_Arch="$(uname -m)"
    SysInfo_Virt="$(systemd-detect-virt)"
    case ${SysInfo_RelatedOS} in
    *fedora* | *rhel*)
        SysInfo_OS_Ver_major="$(rpm -E '%{rhel}')"
        ;;
    *)
        SysInfo_OS_Ver_major="$(echo ${VERSION_ID} | cut -d. -f1)"
        ;;
    esac
}

Print_System_Info() {
    echo -e "
System Information
---------------------------------------------------
  Operating System: ${SysInfo_OS_Name_Full}
      Linux Kernel: ${SysInfo_Kernel}
      Architecture: ${SysInfo_Arch}
    Virtualization: ${SysInfo_Virt}
---------------------------------------------------
"
}


Install_wgcf() {
    curl -fsSL https://raw.githubusercontent.com/yirenchengfeng1/warp/main/wgcf.sh | bash
}

Uninstall_wgcf() {
    rm -f /usr/local/bin/wgcf
}

Register_WARP_Account() {
    while [[ ! -f wgcf-account.toml ]]; do
        Install_wgcf
        log INFO "Cloudflare WARP Account registration in progress..."
        yes | wgcf register
        sleep 5
    done
}

Generate_WGCF_Profile() {
    while [[ ! -f ${WGCF_Profile} ]]; do
        Register_WARP_Account
        log INFO "WARP WireGuard profile (wgcf-profile.conf) generation in progress..."
        wgcf generate
    done
    Uninstall_wgcf
}

Backup_WGCF_Profile() {
    mkdir -p ${WGCF_ProfileDir}
    mv -f wgcf* ${WGCF_ProfileDir}
}

Read_WGCF_Profile() {
    WireGuard_Interface_PrivateKey=$(cat ${WGCF_ProfilePath} | grep ^PrivateKey | cut -d= -f2- | awk '$1=$1')
    WireGuard_Interface_Address=$(cat ${WGCF_ProfilePath} | grep ^Address | cut -d= -f2- | awk '$1=$1' | sed ":a;N;s/\n/,/g;ta")
    WireGuard_Peer_PublicKey=$(cat ${WGCF_ProfilePath} | grep ^PublicKey | cut -d= -f2- | awk '$1=$1')
    WireGuard_Interface_Address_IPv4=$(echo ${WireGuard_Interface_Address} | cut -d, -f1 | cut -d'/' -f1)
    WireGuard_Interface_Address_IPv6=$(echo ${WireGuard_Interface_Address} | cut -d, -f2 | cut -d'/' -f1)
}

Load_WGCF_Profile() {
    if [[ -f ${WGCF_Profile} ]]; then
        Backup_WGCF_Profile
        Read_WGCF_Profile
    elif [[ -f ${WGCF_ProfilePath} ]]; then
        Read_WGCF_Profile
    else
        Generate_WGCF_Profile
        Backup_WGCF_Profile
        Read_WGCF_Profile
    fi
}

Install_WireGuardTools_Debian() {
    case ${SysInfo_OS_Ver_major} in
    10)
        if [[ -z $(grep "^deb.*buster-backports.*main" /etc/apt/sources.list{,.d/*}) ]]; then
            echo "deb http://deb.debian.org/debian buster-backports main" | tee /etc/apt/sources.list.d/backports.list
        fi
        ;;
    *)
        if [[ ${SysInfo_OS_Ver_major} -lt 10 ]]; then
            log ERROR "This operating system is not supported."
            exit 1
        fi
        ;;
    esac
    apt update
    apt install iproute2 openresolv -y
    apt install wireguard-tools --no-install-recommends -y
}

Install_WireGuardTools_Ubuntu() {
    apt update
    apt install iproute2 openresolv -y
    apt install wireguard-tools --no-install-recommends -y
}

Install_WireGuardTools_CentOS() {
    yum install epel-release -y || yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-${SysInfo_OS_Ver_major}.noarch.rpm -y
    yum install iproute iptables wireguard-tools -y
}

Install_WireGuardTools_Fedora() {
    dnf install iproute iptables wireguard-tools -y
}

Install_WireGuardTools_Arch() {
    pacman -Sy iproute2 openresolv wireguard-tools --noconfirm
}

Install_WireGuardTools() {
    log INFO "Installing wireguard-tools..."
    case ${SysInfo_OS_Name_lowercase} in
    *debian*)
        Install_WireGuardTools_Debian
        ;;
    *ubuntu*)
        Install_WireGuardTools_Ubuntu
        ;;
    *centos* | *rhel*)
        Install_WireGuardTools_CentOS
        ;;
    *fedora*)
        Install_WireGuardTools_Fedora
        ;;
    *arch*)
        Install_WireGuardTools_Arch
        ;;
    *)
        if [[ ${SysInfo_RelatedOS} = *rhel* || ${SysInfo_RelatedOS} = *fedora* ]]; then
            Install_WireGuardTools_CentOS
        else
            log ERROR "This operating system is not supported."
            exit 1
        fi
        ;;
    esac
}

Install_WireGuardGo() {
    case ${SysInfo_Virt} in
    openvz | lxc*)
        curl -fsSL https://raw.githubusercontent.com/yirenchengfeng1/warp/main/wireguard-go.sh | bash
        ;;
    *)
        if [[ ${SysInfo_Kernel_Ver_major} -lt 5 || ${SysInfo_Kernel_Ver_minor} -lt 6 ]]; then
            curl -fsSL https://raw.githubusercontent.com/yirenchengfeng1/warp/main/wireguard-go.sh | bash
        fi
        ;;
    esac
}

Check_WARP_Client() {
    WARP_Client_Status=$(systemctl is-active warp-svc)
    WARP_Client_SelfStart=$(systemctl is-enabled warp-svc 2>/dev/null)
}

Check_WireGuard() {
    WireGuard_Status=$(systemctl is-active wg-quick@${WireGuard_Interface})
    WireGuard_SelfStart=$(systemctl is-enabled wg-quick@${WireGuard_Interface} 2>/dev/null)
}

Install_WireGuard() {
    Print_System_Info
    Check_WireGuard
    if [[ ${WireGuard_SelfStart} != enabled || ${WireGuard_Status} != active ]]; then
        Install_WireGuardTools
        Install_WireGuardGo
    else
        log INFO "WireGuard is installed and running."
    fi
}

Start_WireGuard() {
    Check_WARP_Client
    log INFO "Starting WireGuard..."
    if [[ ${WARP_Client_Status} = active ]]; then
        systemctl stop warp-svc
        systemctl enable wg-quick@${WireGuard_Interface} --now
        systemctl start warp-svc
    else
        systemctl enable wg-quick@${WireGuard_Interface} --now
    fi
    Check_WireGuard
    if [[ ${WireGuard_Status} = active ]]; then
        log INFO "WireGuard is running."
    else
        log ERROR "WireGuard failure to run!"
        journalctl -u wg-quick@${WireGuard_Interface} --no-pager
        exit 1
    fi
}

Restart_WireGuard() {
    Check_WARP_Client
    log INFO "Restarting WireGuard..."
    if [[ ${WARP_Client_Status} = active ]]; then
        systemctl stop warp-svc
        systemctl restart wg-quick@${WireGuard_Interface}
        systemctl start warp-svc
    else
        systemctl restart wg-quick@${WireGuard_Interface}
    fi
    Check_WireGuard
    if [[ ${WireGuard_Status} = active ]]; then
        log INFO "WireGuard has been restarted."
    else
        log ERROR "WireGuard failure to run!"
        journalctl -u wg-quick@${WireGuard_Interface} --no-pager
        exit 1
    fi
}

Enable_IPv6_Support() {
    if [[ $(sysctl -a | grep 'disable_ipv6.*=.*1') || $(cat /etc/sysctl.{conf,d/*} | grep 'disable_ipv6.*=.*1') ]]; then
        sed -i '/disable_ipv6/d' /etc/sysctl.{conf,d/*}
        echo 'net.ipv6.conf.all.disable_ipv6 = 0' >/etc/sysctl.d/ipv6.conf
        sysctl -w net.ipv6.conf.all.disable_ipv6=0
    fi
}

Enable_WireGuard() {
    Enable_IPv6_Support
    Check_WireGuard
    if [[ ${WireGuard_SelfStart} = enabled ]]; then
        Restart_WireGuard
    else
        Start_WireGuard
    fi
}

Stop_WireGuard() {
    Check_WARP_Client
    if [[ ${WireGuard_Status} = active ]]; then
        log INFO "Stoping WireGuard..."
        if [[ ${WARP_Client_Status} = active ]]; then
            systemctl stop warp-svc
            systemctl stop wg-quick@${WireGuard_Interface}
            systemctl start warp-svc
        else
            systemctl stop wg-quick@${WireGuard_Interface}
        fi
        Check_WireGuard
        if [[ ${WireGuard_Status} != active ]]; then
            log INFO "WireGuard has been stopped."
        else
            log ERROR "WireGuard stop failure!"
        fi
    else
        log INFO "WireGuard is stopped."
    fi
}

Disable_WireGuard() {
    Check_WARP_Client
    Check_WireGuard
    if [[ ${WireGuard_SelfStart} = enabled || ${WireGuard_Status} = active ]]; then
        log INFO "Disabling WireGuard..."
        if [[ ${WARP_Client_Status} = active ]]; then
            systemctl stop warp-svc
            systemctl disable wg-quick@${WireGuard_Interface} --now
            systemctl start warp-svc
        else
            systemctl disable wg-quick@${WireGuard_Interface} --now
        fi
        Check_WireGuard
        if [[ ${WireGuard_SelfStart} != enabled && ${WireGuard_Status} != active ]]; then
            log INFO "WireGuard has been disabled."
        else
            log ERROR "WireGuard disable failure!"
        fi
    else
        log INFO "WireGuard is disabled."
    fi
}

Print_WireGuard_Log() {
    journalctl -u wg-quick@${WireGuard_Interface} -f
}

Check_Network_Status_IPv4() {
    if ping -c1 -W1 ${TestIPv4_1} >/dev/null 2>&1 || ping -c1 -W1 ${TestIPv4_2} >/dev/null 2>&1; then
        IPv4Status='on'
    else
        IPv4Status='off'
    fi
}

Check_Network_Status_IPv6() {
    if ping6 -c1 -W1 ${TestIPv6_1} >/dev/null 2>&1 || ping6 -c1 -W1 ${TestIPv6_2} >/dev/null 2>&1; then
        IPv6Status='on'
    else
        IPv6Status='off'
    fi
}

Check_Network_Status() {
    Disable_WireGuard
    Check_Network_Status_IPv4
    Check_Network_Status_IPv6
}

Check_IPv4_addr() {
    IPv4_addr=$(
        ip route get ${TestIPv4_1} 2>/dev/null | grep -oP 'src \K\S+' ||
            ip route get ${TestIPv4_2} 2>/dev/null | grep -oP 'src \K\S+'
    )
}

Check_IPv6_addr() {
    IPv6_addr=$(
        ip route get ${TestIPv6_1} 2>/dev/null | grep -oP 'src \K\S+' ||
            ip route get ${TestIPv6_2} 2>/dev/null | grep -oP 'src \K\S+'
    )
}

Get_IP_addr() {
    Check_Network_Status
    if [[ ${IPv4Status} = on ]]; then
        log INFO "Getting the network interface IPv4 address..."
        Check_IPv4_addr
        if [[ ${IPv4_addr} ]]; then
            log INFO "IPv4 Address: ${IPv4_addr}"
        else
            log WARN "Network interface IPv4 address not obtained."
        fi
    fi
    if [[ ${IPv6Status} = on ]]; then
        log INFO "Getting the network interface IPv6 address..."
        Check_IPv6_addr
        if [[ ${IPv6_addr} ]]; then
            log INFO "IPv6 Address: ${IPv6_addr}"
        else
            log WARN "Network interface IPv6 address not obtained."
        fi
    fi
}

Get_WireGuard_Interface_MTU() {
    log INFO "Getting the best MTU value for WireGuard..."
    MTU_Preset=1500
    MTU_Increment=10
    if [[ ${IPv4Status} = off && ${IPv6Status} = on ]]; then
        CMD_ping='ping6'
        MTU_TestIP_1="${TestIPv6_1}"
        MTU_TestIP_2="${TestIPv6_2}"
    else
        CMD_ping='ping'
        MTU_TestIP_1="${TestIPv4_1}"
        MTU_TestIP_2="${TestIPv4_2}"
    fi
    while true; do
        if ${CMD_ping} -c1 -W1 -s$((${MTU_Preset} - 28)) -Mdo ${MTU_TestIP_1} >/dev/null 2>&1 || ${CMD_ping} -c1 -W1 -s$((${MTU_Preset} - 28)) -Mdo ${MTU_TestIP_2} >/dev/null 2>&1; then
            MTU_Increment=1
            MTU_Preset=$((${MTU_Preset} + ${MTU_Increment}))
        else
            MTU_Preset=$((${MTU_Preset} - ${MTU_Increment}))
            if [[ ${MTU_Increment} = 1 ]]; then
                break
            fi
        fi
        if [[ ${MTU_Preset} -le 1360 ]]; then
            log WARN "MTU is set to the lowest value."
            MTU_Preset='1360'
            break
        fi
    done
    WireGuard_Interface_MTU=$((${MTU_Preset} - 80))
    log INFO "WireGuard MTU: ${WireGuard_Interface_MTU}"
}

Generate_WireGuardProfile_Interface() {
    Get_WireGuard_Interface_MTU
    log INFO "WireGuard profile (${WireGuard_ConfPath}) generation in progress..."
    cat <<EOF >${WireGuard_ConfPath}
# Generated by P3TERX/warp.sh
# Visit https://github.com/P3TERX/warp.sh for more information

[Interface]
PrivateKey = ${WireGuard_Interface_PrivateKey}
Address = ${WireGuard_Interface_Address}
DNS = ${WireGuard_Interface_DNS}
MTU = ${WireGuard_Interface_MTU}
EOF
}

Generate_WireGuardProfile_Interface_Rule_TableOff() {
    cat <<EOF >>${WireGuard_ConfPath}
Table = off
EOF
}

Generate_WireGuardProfile_Interface_Rule_IPv4_nonGlobal() {
    cat <<EOF >>${WireGuard_ConfPath}
PostUP = ip -4 route add default dev ${WireGuard_Interface} table ${WireGuard_Interface_Rule_table}
PostUP = ip -4 rule add from ${WireGuard_Interface_Address_IPv4} lookup ${WireGuard_Interface_Rule_table}
PostDown = ip -4 rule delete from ${WireGuard_Interface_Address_IPv4} lookup ${WireGuard_Interface_Rule_table}
PostUP = ip -4 rule add fwmark ${WireGuard_Interface_Rule_fwmark} lookup ${WireGuard_Interface_Rule_table}
PostDown = ip -4 rule delete fwmark ${WireGuard_Interface_Rule_fwmark} lookup ${WireGuard_Interface_Rule_table}
PostUP = ip -4 rule add table main suppress_prefixlength 0
PostDown = ip -4 rule delete table main suppress_prefixlength 0
EOF
}

Generate_WireGuardProfile_Interface_Rule_IPv6_nonGlobal() {
    cat <<EOF >>${WireGuard_ConfPath}
PostUP = ip -6 route add default dev ${WireGuard_Interface} table ${WireGuard_Interface_Rule_table}
PostUP = ip -6 rule add from ${WireGuard_Interface_Address_IPv6} lookup ${WireGuard_Interface_Rule_table}
PostDown = ip -6 rule delete from ${WireGuard_Interface_Address_IPv6} lookup ${WireGuard_Interface_Rule_table}
PostUP = ip -6 rule add fwmark ${WireGuard_Interface_Rule_fwmark} lookup ${WireGuard_Interface_Rule_table}
PostDown = ip -6 rule delete fwmark ${WireGuard_Interface_Rule_fwmark} lookup ${WireGuard_Interface_Rule_table}
PostUP = ip -6 rule add table main suppress_prefixlength 0
PostDown = ip -6 rule delete table main suppress_prefixlength 0
EOF
}

Generate_WireGuardProfile_Interface_Rule_DualStack_nonGlobal() {
    Generate_WireGuardProfile_Interface_Rule_TableOff
    Generate_WireGuardProfile_Interface_Rule_IPv4_nonGlobal
    Generate_WireGuardProfile_Interface_Rule_IPv6_nonGlobal
}

Generate_WireGuardProfile_Interface_Rule_nonGlobal_only_IPv4() {
    Generate_WireGuardProfile_Interface_Rule_TableOff
    Generate_WireGuardProfile_Interface_Rule_IPv4_nonGlobal
}

Generate_WireGuardProfile_Interface_Rule_nonGlobal_only_IPv6() {
    Generate_WireGuardProfile_Interface_Rule_TableOff
    Generate_WireGuardProfile_Interface_Rule_IPv6_nonGlobal
}


Generate_WireGuardProfile_Interface_Rule_IPv4_Global_srcIP() {
    cat <<EOF >>${WireGuard_ConfPath}
PostUp = ip -4 rule add from ${IPv4_addr} lookup main prio 18
PostDown = ip -4 rule delete from ${IPv4_addr} lookup main prio 18
EOF
}

Generate_WireGuardProfile_Interface_Rule_IPv6_Global_srcIP() {
    cat <<EOF >>${WireGuard_ConfPath}
PostUp = ip -6 rule add from ${IPv6_addr} lookup main prio 18
PostDown = ip -6 rule delete from ${IPv6_addr} lookup main prio 18
EOF
}

Generate_WireGuardProfile_Peer() {
    cat <<EOF >>${WireGuard_ConfPath}

[Peer]
PublicKey = ${WireGuard_Peer_PublicKey}
AllowedIPs = ${WireGuard_Peer_AllowedIPs}
Endpoint = ${WireGuard_Peer_Endpoint}
EOF
}


Check_WireGuard_Status() {
    Check_WireGuard
    case ${WireGuard_Status} in
    active)
        WireGuard_Status_en="${FontColor_Green}Running${FontColor_Suffix}"
        WireGuard_Status_zh="${FontColor_Green}运行中${FontColor_Suffix}"
        ;;
    *)
        WireGuard_Status_en="${FontColor_Red}Stopped${FontColor_Suffix}"
        WireGuard_Status_zh="${FontColor_Red}未运行${FontColor_Suffix}"
        ;;
    esac
}

Check_WARP_WireGuard_Status() {
    Check_Network_Status_IPv4
    if [[ ${IPv4Status} = on ]]; then
        WARP_IPv4_Status=$(curl -s4 ${CF_Trace_URL} --connect-timeout 2 | grep warp | cut -d= -f2)
    else
        unset WARP_IPv4_Status
    fi
    case ${WARP_IPv4_Status} in
    on)
        WARP_IPv4_Status_en="${FontColor_Green}WARP${FontColor_Suffix}"
        WARP_IPv4_Status_zh="${WARP_IPv4_Status_en}"
        ;;
    plus)
        WARP_IPv4_Status_en="${FontColor_Green}WARP+${FontColor_Suffix}"
        WARP_IPv4_Status_zh="${WARP_IPv4_Status_en}"
        ;;
    off)
        WARP_IPv4_Status_en="Normal"
        WARP_IPv4_Status_zh="正常"
        ;;
    *)
        Check_Network_Status_IPv4
        if [[ ${IPv4Status} = on ]]; then
            WARP_IPv4_Status_en="Normal"
            WARP_IPv4_Status_zh="正常"
        else
            WARP_IPv4_Status_en="${FontColor_Red}Unconnected${FontColor_Suffix}"
            WARP_IPv4_Status_zh="${FontColor_Red}未连接${FontColor_Suffix}"
        fi
        ;;
    esac
    Check_Network_Status_IPv6
    if [[ ${IPv6Status} = on ]]; then
        WARP_IPv6_Status=$(curl -s6 ${CF_Trace_URL} --connect-timeout 2 | grep warp | cut -d= -f2)
    else
        unset WARP_IPv6_Status
    fi
    case ${WARP_IPv6_Status} in
    on)
        WARP_IPv6_Status_en="${FontColor_Green}WARP${FontColor_Suffix}"
        WARP_IPv6_Status_zh="${WARP_IPv6_Status_en}"
        ;;
    plus)
        WARP_IPv6_Status_en="${FontColor_Green}WARP+${FontColor_Suffix}"
        WARP_IPv6_Status_zh="${WARP_IPv6_Status_en}"
        ;;
    off)
        WARP_IPv6_Status_en="Normal"
        WARP_IPv6_Status_zh="正常"
        ;;
    *)
        Check_Network_Status_IPv6
        if [[ ${IPv6Status} = on ]]; then
            WARP_IPv6_Status_en="Normal"
            WARP_IPv6_Status_zh="正常"
        else
            WARP_IPv6_Status_en="${FontColor_Red}Unconnected${FontColor_Suffix}"
            WARP_IPv6_Status_zh="${FontColor_Red}未连接${FontColor_Suffix}"
        fi
        ;;
    esac
    if [[ ${IPv4Status} = off && ${IPv6Status} = off ]]; then
        log ERROR "Cloudflare WARP network anomaly, WireGuard tunnel established failed."
        Disable_WireGuard
        exit 1
    fi
}


Print_WARP_WireGuard_Status() {
    log INFO "Status check in progress..."
    Check_WireGuard_Status
    Check_WARP_WireGuard_Status
    echo -e "
 ----------------------------
 WireGuard\t: ${WireGuard_Status_en}
 IPv4 Network\t: ${WARP_IPv4_Status_en}
 IPv6 Network\t: ${WARP_IPv6_Status_en}
 ----------------------------
"
    log INFO "Done."
}


View_WireGuard_Profile() {
    Print_Delimiter
    cat ${WireGuard_ConfPath}
    Print_Delimiter
}

Check_WireGuard_Peer_Endpoint() {
    if ping -c1 -W1 ${WireGuard_Peer_Endpoint_IP4} >/dev/null 2>&1; then
        WireGuard_Peer_Endpoint="${WireGuard_Peer_Endpoint_IPv4}"
    elif ping6 -c1 -W1 ${WireGuard_Peer_Endpoint_IP6} >/dev/null 2>&1; then
        WireGuard_Peer_Endpoint="${WireGuard_Peer_Endpoint_IPv6}"
    else
        WireGuard_Peer_Endpoint="${WireGuard_Peer_Endpoint_Domain}"
    fi
}

Set_WARP_IPv4() {
    Install_WireGuard
    Get_IP_addr
    Load_WGCF_Profile
    if [[ ${IPv4Status} = off && ${IPv6Status} = on ]]; then
        WireGuard_Interface_DNS="${WireGuard_Interface_DNS_64}"
    else
        WireGuard_Interface_DNS="${WireGuard_Interface_DNS_46}"
    fi
    WireGuard_Peer_AllowedIPs="${WireGuard_Peer_AllowedIPs_IPv4}"
    Check_WireGuard_Peer_Endpoint
    Generate_WireGuardProfile_Interface
    if [[ -n ${IPv4_addr} ]]; then
        Generate_WireGuardProfile_Interface_Rule_IPv4_Global_srcIP
    fi
    Generate_WireGuardProfile_Peer
    View_WireGuard_Profile
    Enable_WireGuard
    Print_WARP_WireGuard_Status
}

Set_WARP_IPv6() {
    Install_WireGuard
    Get_IP_addr
    Load_WGCF_Profile
    if [[ ${IPv4Status} = off && ${IPv6Status} = on ]]; then
        WireGuard_Interface_DNS="${WireGuard_Interface_DNS_64}"
    else
        WireGuard_Interface_DNS="${WireGuard_Interface_DNS_46}"
    fi
    WireGuard_Peer_AllowedIPs="${WireGuard_Peer_AllowedIPs_IPv6}"
    Check_WireGuard_Peer_Endpoint
    Generate_WireGuardProfile_Interface
    if [[ -n ${IPv6_addr} ]]; then
        Generate_WireGuardProfile_Interface_Rule_IPv6_Global_srcIP
    fi
    Generate_WireGuardProfile_Peer
    View_WireGuard_Profile
    Enable_WireGuard
    Print_WARP_WireGuard_Status
}

Set_WARP_DualStack() {
    Install_WireGuard
    Get_IP_addr
    Load_WGCF_Profile
    WireGuard_Interface_DNS="${WireGuard_Interface_DNS_46}"
    WireGuard_Peer_AllowedIPs="${WireGuard_Peer_AllowedIPs_DualStack}"
    Check_WireGuard_Peer_Endpoint
    Generate_WireGuardProfile_Interface
    if [[ -n ${IPv4_addr} ]]; then
        Generate_WireGuardProfile_Interface_Rule_IPv4_Global_srcIP
    fi
    if [[ -n ${IPv6_addr} ]]; then
        Generate_WireGuardProfile_Interface_Rule_IPv6_Global_srcIP
    fi
    Generate_WireGuardProfile_Peer
    View_WireGuard_Profile
    Enable_WireGuard
    Print_WARP_WireGuard_Status
}

Set_WARP_DualStack_nonGlobal() {
    Install_WireGuard
    Get_IP_addr
    Load_WGCF_Profile
    WireGuard_Interface_DNS="${WireGuard_Interface_DNS_46}"
    WireGuard_Peer_AllowedIPs="${WireGuard_Peer_AllowedIPs_DualStack}"
    Check_WireGuard_Peer_Endpoint
    Generate_WireGuardProfile_Interface
    Generate_WireGuardProfile_Interface_Rule_DualStack_nonGlobal
    Generate_WireGuardProfile_Peer
    View_WireGuard_Profile
    Enable_WireGuard
    Print_WARP_WireGuard_Status
}

Set_WARP_DualStack_nonGlobal_IPv4() {
    Install_WireGuard
    Get_IP_addr
    Load_WGCF_Profile
    WireGuard_Interface_DNS="${WireGuard_Interface_DNS_46}"
    WireGuard_Peer_AllowedIPs="${WireGuard_Peer_AllowedIPs_DualStack}"
    Check_WireGuard_Peer_Endpoint
    Generate_WireGuardProfile_Interface
	Generate_WireGuardProfile_Interface_Rule_nonGlobal_only_IPv4
    Generate_WireGuardProfile_Peer
    View_WireGuard_Profile
    Enable_WireGuard
    Print_WARP_WireGuard_Status
}

Set_WARP_DualStack_nonGlobal_IPv6() {
    Install_WireGuard
    Get_IP_addr
    Load_WGCF_Profile
    WireGuard_Interface_DNS="${WireGuard_Interface_DNS_46}"
    WireGuard_Peer_AllowedIPs="${WireGuard_Peer_AllowedIPs_DualStack}"
    Check_WireGuard_Peer_Endpoint
    Generate_WireGuardProfile_Interface
    Generate_WireGuardProfile_Interface_Rule_nonGlobal_only_IPv6
    Generate_WireGuardProfile_Peer
    View_WireGuard_Profile
    Enable_WireGuard
    Print_WARP_WireGuard_Status
}


Print_Usage() {
    echo -e "

USAGE:
    bash <(curl -fsSL https://raw.githubusercontent.com/yirenchengfeng1/warp/main/warp.sh) [SUBCOMMAND]

SUBCOMMANDS:
    wg4             Configuration WARP IPv4 Global Network (with WireGuard), all IPv4 outbound data over the WARP network
    wg6             Configuration WARP IPv6 Global Network (with WireGuard), all IPv6 outbound data over the WARP network
    wgd             Configuration WARP Dual Stack Global Network (with WireGuard), all outbound data over the WARP network
    wgx             Configuration WARP Non-Global Network (with WireGuard), set fwmark or interface IP Address to use the WARP network
    wgy             Configuration WARP IPv4 Non-Global Network (with WireGuard), set fwmark or interface IP Address to use the WARP network
    wgz             Configuration WARP IPv6 Non-Global Network (with WireGuard), set fwmark or interface IP Address to use the WARP network	
    rwg             Restart WARP WireGuard service
    dwg             Disable WARP WireGuard service
    status          Prints status information
    help            Prints this message or the help of the given subcommand(s)
"
}


if [ $# -ge 1 ]; then
    Get_System_Info
    case ${1} in
    wg4 | 4)
        Set_WARP_IPv4
        ;;
    wg6 | 6)
        Set_WARP_IPv6
        ;;
    wgd | d)
        Set_WARP_DualStack
        ;;
    wgx | x)
        Set_WARP_DualStack_nonGlobal
        ;;
	wgy | y)
        Set_WARP_DualStack_nonGlobal_IPv4
        ;;
    wgz | z)
        Set_WARP_DualStack_nonGlobal_IPv6
        ;;
    rwg)
        Restart_WireGuard
        ;;
    dwg)
        Disable_WireGuard
        ;;
    status)
        Print_WARP_WireGuard_Status
        ;;
    help)
        Print_Usage
        ;;
    *)
        log ERROR "Invalid Parameters: $*"
        Print_Usage
        exit 1
        ;;
    esac
else
    Print_Usage
fi
