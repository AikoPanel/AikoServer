#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Error:${plain} This script must be run as root user!\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
else
    echo -e "${red}System version not detected, please contact the script author!${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}Architecture detection failed, using default architecture: ${arch}${plain}"
fi

echo "Architecture: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "This software is not supported on 32-bit systems (x86), please use 64-bit systems (x86_64). If there is an error in detection, please contact the author."
    exit 2
fi


# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}Please use CentOS 7 or higher system!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}Please use Ubuntu 16 or higher system!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}Please use Debian 8 or higher system!${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y
        yum install wget curl unzip tar crontabs socat -y
    else
        apt-get update -y
        apt install wget curl unzip tar cron socat -y
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/Aiko-Server.service ]]; then
        return 2
    fi
    temp=$(systemctl status Aiko-Server | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

install_Aiko-Server() {
    if [[ -e /usr/local/Aiko-Server/ ]]; then
        rm -rf /usr/local/Aiko-Server/
    fi

    mkdir /usr/local/Aiko-Server/ -p
    cd /usr/local/Aiko-Server/

    if  [ $# == 0 ] ;then
        last_version=$(curl -Ls "https://api.github.com/repos/AikoPanel/AikoServer/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}Failed to check Aiko-Server version. It may be due to exceeding the Github API limit. Please try again later or manually specify the Aiko-Server version for installation.${plain}"
            exit 1
        fi
        echo -e "Detected the latest version of Aiko-Server: ${last_version}, starting installation"
        wget -q -N --no-check-certificate -O /usr/local/Aiko-Server/Aiko-Server-linux.zip https://github.com/AikoPanel/AikoServer/releases/download/${last_version}/Aiko-Server-linux-${arch}.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Failed to download Aiko-Server. Please make sure your server can download files from Github.${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/AikoPanel/AikoServer/releases/download/${last_version}/Aiko-Server-linux-${arch}.zip"
        echo -e "Starting installation of Aiko-Server v$1"
        wget -q -N --no-check-certificate -O /usr/local/Aiko-Server/Aiko-Server-linux.zip ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Failed to download Aiko-Server v$1. Please make sure the version exists.${plain}"
            exit 1
        fi
    fi

    unzip Aiko-Server-linux.zip
    rm Aiko-Server-linux.zip -f
    chmod +x Aiko-Server
    mkdir /etc/Aiko-Server/ -p
    rm /etc/systemd/system/Aiko-Server.service -f
    file="https://github.com/AikoPanel/AikoServer/raw/master/Aiko-Server.service"
    wget -q -N --no-check-certificate -O /etc/systemd/system/Aiko-Server.service ${file}
    #cp -f Aiko-Server.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl stop Aiko-Server
    systemctl enable Aiko-Server
    echo -e "${green}Aiko-Server ${last_version}${plain} installation completed and set to start on boot"
    cp geoip.dat /etc/Aiko-Server/
    cp geosite.dat /etc/Aiko-Server/

    if [[ ! -f /etc/Aiko-Server/aiko.yml ]]; then
        cp aiko.yml /etc/Aiko-Server/
        echo -e ""
        echo -e "For a fresh installation, please refer to the tutorial: https://github.com/AikoPanel/AikoServer and configure the necessary content"
    else
        systemctl start Aiko-Server
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}Aiko-Server restarted successfully${plain}"
        else
            echo -e "${red}Aiko-Server may have failed to start, please use Aiko-Server log to view log information. If it cannot be started, it may have changed the configuration format, please go to the wiki for more information: https://github.com/Aiko-Server-project/Aiko-Server/wiki${plain}"
        fi
    fi

    if [[ ! -f /etc/Aiko-Server/dns.json ]]; then
        cp dns.json /etc/Aiko-Server/
    fi
    if [[ ! -f /etc/Aiko-Server/route.json ]]; then
        cp route.json /etc/Aiko-Server/
    fi
    if [[ ! -f /etc/Aiko-Server/custom_outbound.json ]]; then
        cp custom_outbound.json /etc/Aiko-Server/
    fi
    if [[ ! -f /etc/Aiko-Server/custom_inbound.json ]]; then
        cp custom_inbound.json /etc/Aiko-Server/
    fi
    if [[ ! -f /etc/Aiko-Server/AikoBlock ]]; then
        cp AikoBlock /etc/Aiko-Server/
    fi
    curl -o /usr/bin/Aiko-Server -Ls https://raw.githubusercontent.com/AikoPanel/AikoServer/master/Aiko-Server.sh
    chmod +x /usr/bin/Aiko-Server
    ln -s /usr/bin/Aiko-Server /usr/bin/aiko-server # compatible lowercase
    chmod +x /usr/bin/aiko-server
    cd $cur_dir
    rm -f install.sh
    echo -e ""
    echo "Usage of Aiko-Server management script (compatible with Aiko-Server execution, case-insensitive):"
    echo "------------------------------------------"
    echo "Aiko-Server              - Show management menu (more functions)"
    echo "Aiko-Server start        - Start Aiko-Server"
    echo "Aiko-Server stop         - Stop Aiko-Server"
    echo "Aiko-Server restart      - Restart Aiko-Server"
    echo "Aiko-Server status       - Check Aiko-Server status"
    echo "Aiko-Server enable       - Set Aiko-Server to start on boot"
    echo "Aiko-Server disable      - Disable Aiko-Server to start on boot"
    echo "Aiko-Server log          - Check Aiko-Server logs"
    echo "Aiko-Server generate     - Generate Aiko-Server configuration file"
    echo "Aiko-Server update       - Update Aiko-Server"
    echo "Aiko-Server update x.x.x - Update Aiko-Server to specified version"
    echo "Aiko-Server install      - Install Aiko-Server"
    echo "Aiko-Server uninstall    - Uninstall Aiko-Server"
    echo "Aiko-Server version      - Check Aiko-Server version"
    echo "------------------------------------------"
}

echo -e "${green}Starting installation${plain}"
install_base
install_Aiko-Server $1
