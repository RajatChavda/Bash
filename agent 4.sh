#!/bin/bash

#--------------------------------------------------------#
#                    Global Variables                    #
#--------------------------------------------------------#

#-> log
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
BLUE="\e[34m"
RESET="\e[0m"  # Reset color to default

# Define Global variables
SERVER_IP=$1

# Get the distribution name and version
DISTRO_NAME=$(grep '^NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
DISTRO_VERSION=$(grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
ARCHITECTURE=$(uname -m)


#--------------------------------------------------------#
#                    Argument parsing                    #
#--------------------------------------------------------#


#--------------------------------------------------------#
#                       Functions                        #
#--------------------------------------------------------#

welcome_box() {
    local full_text="$1"  # Capture function parameter
    local length=${#full_text}
    local term_width=$(tput cols)
    local padding=$(( (term_width - length) / 2 ))
    echo "" && echo "" && echo ""
    printf "%*s" "$padding" ""  # Align the text
    for ((i = 0; i < length; i++)); do
        printf "%s" "${full_text:i:1}"
        sleep 0.1  # Adjust typing speed
    done
    echo "" && echo "" && echo ""
    sleep 1
}

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local color
    case "$level" in
        INFO) color=$GREEN;;
        WARNING) color=$YELLOW;;
        ERROR) color=$RED;;
        DEBUG) color=$BLUE;;
        *) color=$RESET;;
    esac
    # Log message format
    log_message="${timestamp} [$level] ${message}"
    # Print to console
    echo -ne "${color}${timestamp} [$level] ${RESET}"
    # Typing animation for the message
    for ((i = 0; i < ${#message}; i++)); do
        echo -ne "${message:i:1}"
        sleep 0.01  # Adjust typing speed if needed
    done
    echo ""  # Move to a new line
}

# Function to check if the public IP is accessible on a specific port
create_host_name() {
    local port=10050
    local public_ip=${2:-$(curl -s http://ipinfo.io/ip)}
    local private_ip=$(hostname -I | awk '{print $1}')


    if [[ -z "$public_ip" ]]; then
        log WARNING "Failed to retrieve public IP."
        return 1
    fi
    log INFO "Public IP retrieved: $public_ip"

    # Start a simple HTTP server in the background using nc
    echo -e "HTTP/1.1 200 OK\r\nContent-Length: 24\r\nContent-Type: text/plain\r\n\r\nHello from port $port!" | nc -lk -w 5 $port &
    local nc_pid=$!
    log INFO "Temporary service hosted on port $port"

    # Give nc a moment to start properly
    sleep 2

    # Send a curl request to the public IP on port
    local response=$(curl -s --connect-timeout 10 --max-time 10 "http://$public_ip:$port")

    # Check the response
    if [[ "$response" == "Hello from port $port!" ]]; then
        log INFO "Public IP is accessible externally on port $port."
        host_name="asg-$public_ip"
    else
        log INFO "Public IP is not accessible on port $port."
        host_name="asg-$private_ip"
    fi

    # Cleanup: Kill the nc process to stop the HTTP server
    kill $nc_pid
}

#-> Installng required packages.
# Function to install required packages
debian_install_requirements() {
    # Define the packages that need to be checked and installed
    local packages=("wget" "curl")

    # Check if nc is a command that needs installation and adjust the package name
    if ! type nc >/dev/null 2>&1; then
        packages+=("netcat-traditional")  # You could also choose netcat-openbsd based on preference
    fi

    for package in "${packages[@]}"; do
        if ! dpkg -s $package >/dev/null 2>&1; then
            log WARNING "$package is not installed. Installing..."
            sudo apt-get update && sudo apt-get install -y $package
        else
            log INFO "$package is already installed."
        fi
    done

    create_host_name
}

redhat_install_requirements() {
    # Define the packages that need to be checked and installed
    local packages=("wget" "curl")

    # Check if nc is a command that needs installation and adjust the package name
    if ! type nc >/dev/null 2>&1; then
        packages+=("nmap-ncat")  # nmap-ncat is often used instead of traditional netcat on Red Hat-based systems
    fi

    for package in "${packages[@]}"; do
        if ! rpm -q $package >/dev/null 2>&1; then
            log WARNING "$package is not installed. Installing..."
            sudo dnf install -y $package
        else
            log INFO "$package is already installed."
        fi
    done

    create_host_name
}



#--------------------------------------------------------#
#                         BODY                           #
#--------------------------------------------------------#
clear
welcome_box "VECTOR AGENT INSTALLATION"


# Check if an argument is provided
if [ -z "$SERVER_IP" ]; then
  log ERROR "Server ip is missing."
  log WARNING "Please provide server ip along with script as argument."
  log WARNING "Abroting Installation."
  exit 1
fi

log INFO "SERVER IP: $SERVER_IP"

if [[ "$DISTRO_NAME" == "Amazon Linux" ]] && [[ "$DISTRO_VERSION" == "2023" ]]; then
    log INFO "Detected Amazon Linux 2023."
    redhat_install_requirements
   
    # Install Zabbix 7.0 for Amazon Linux 2023
    log INFO "Installing Vector agent for Amazon Linux 2023..."
    sudo rpm -Uvh https://repo.zabbix.com/zabbix/7.0/amazonlinux/2023/x86_64/zabbix-release-7.0-6.amzn2023.noarch.rpm
    sudo dnf clean all
    sudo dnf install -y zabbix-agent2 zabbix-agent2-plugin-*

    # Update configuration
    log INFO "Updating Configuration file"
    sudo sed -i "s/^Server=.*/Server=$SERVER_IP/" /etc/zabbix/zabbix_agent2.conf
    sudo sed -i "s/^ServerActive=.*/ServerActive=$SERVER_IP/" /etc/zabbix/zabbix_agent2.conf
    sudo sed -i "s/^Hostname=.*/Hostname=$host_name/" /etc/zabbix/zabbix_agent2.conf

    # Start and enable the service
    sudo systemctl restart zabbix-agent2
    sudo systemctl enable zabbix-agent2

    log INFO "Vector agent installation and configuration complete."


elif [[ "$DISTRO_NAME" == "Amazon Linux" ]] && [[ "$DISTRO_VERSION" == "2" ]]; then
    log INFO "Detected Amazon Linux 2."
    redhat_install_requirements
   
    # Define variables for Amazon Linux 2
    ZABBIX_RPM="https://repo.zabbix.com/zabbix/6.0/rhel/8/x86_64/zabbix-agent-6.0.1-1.el8.x86_64.rpm"
    RPM_FILE="zabbix-agent-6.0.1-1.el8.x86_64.rpm"
   
    # Download and install the Zabbix agent
    log INFO "Downloading Vector agent..."
    wget $ZABBIX_RPM

    log INFO "Installing Vector agent..."
    sudo yum install -y ./$RPM_FILE
    sudo rm ./$RPM_FILE

    # Update configuration
    log INFO "Updating Configurations"
    sudo sed -i "s/^Server=.*/Server=$SERVER_IP/" /etc/zabbix/zabbix_agentd.conf
    sudo sed -i "s/^ServerActive=.*/ServerActive=$SERVER_IP/" /etc/zabbix/zabbix_agentd.conf
    sudo sed -i "s/^Hostname=.*/Hostname=$host_name/" /etc/zabbix/zabbix_agentd.conf

    # Enable and start the service
    log INFO "Enabling and starting the Vector agent service..."
    sudo systemctl enable zabbix-agent.service --now

    log INFO "Vector agent installation and configuration complete."

    log INFO "Installing Cron"
    sudo yum install cronie -y
    sudo systemctl start crond
    sudo systemctl enable crond

elif [[ "$DISTRO_NAME" == "AlmaLinux" ]] && [[ "$ARCHITECTURE" == "x86_64" ]]; then
    log INFO "Detected Alma Linux."
    redhat_install_requirements

    if [[ "$DISTRO_VERSION" == 9.* ]]; then
        log INFO "Detected OS Version $DISTRO_VERSION"
        sudo rpm -Uvh https://repo.zabbix.com/zabbix/7.0/alma/9/x86_64/zabbix-release-latest-7.0.el9.noarch.rpm
    elif [[ "$DISTRO_VERSION" == 8.* ]]; then
        log INFO "Detected OS Version $DISTRO_VERSION"
        sudo rpm -Uvh https://repo.zabbix.com/zabbix/7.0/alma/8/x86_64/zabbix-release-latest-7.0.el8.noarch.rpm
    fi

    # Install Zabbix Agent Repository 7.0 for Alma Linux
    sudo dnf clean all

    # Download and install the Zabbix agent
    log INFO "Downloading Vector agent..."
    sudo dnf install zabbix-agent2 -y
    sudo dnf install zabbix-agent2-plugin-mongodb zabbix-agent2-plugin-mssql zabbix-agent2-plugin-postgresql zabbix-sender -y

    # Update configuration
    log INFO "Updating Configurations"
    sudo sed -i "s/^Server=.*/Server=$SERVER_IP/" /etc/zabbix/zabbix_agent2.conf
    sudo sed -i "s/^ServerActive=.*/ServerActive=$SERVER_IP/" /etc/zabbix/zabbix_agent2.conf
    sudo sed -i "s/^Hostname=.*/Hostname=$host_name/" /etc/zabbix/zabbix_agent2.conf

    # Enable and start the service
    log INFO "Enabling and starting the Vector agent service..."
    sudo systemctl restart zabbix-agent2.service --now
    sudo systemctl enable zabbix-agent2.service --now

    log INFO "Vector agent installation and configuration complete."
    log INFO "VECTOR SENDER: INSTALLATION COMPLETED"

elif [[ "$DISTRO_NAME" == "CentOS Stream" ]] && [[ "$ARCHITECTURE" == "x86_64" ]]; then
    log INFO "Detected CentOS Stream"
    redhat_install_requirements

    if [[ "$DISTRO_VERSION" == 9.* ]]; then
        log INFO "Detected OS Version $DISTRO_VERSION"
        sudo rpm -Uvh https://repo.zabbix.com/zabbix/7.0/centos/9/x86_64/zabbix-release-latest-7.0.el9.noarch.rpm
    elif [[ "$DISTRO_VERSION" == 8.* ]]; then
        log INFO "Detected OS Version $DISTRO_VERSION"
        sudo rpm -Uvh https://repo.zabbix.com/zabbix/7.0/centos/8/x86_64/zabbix-release-latest-7.0.el8.noarch.rpm
    fi

    # Install Zabbix Agent Repository 7.0 for CentOS Stream
    sudo dnf clean all

    # Download and install the Zabbix agent
    log INFO "Downloading Vector agent..."
    sudo dnf install zabbix-agent2 -y
    sudo dnf install zabbix-agent2-plugin-mongodb zabbix-agent2-plugin-mssql zabbix-agent2-plugin-postgresql zabbix-sender -y

    # Update configuration
    log INFO "Updating Configurations"
    sudo sed -i "s/^Server=.*/Server=$SERVER_IP/" /etc/zabbix/zabbix_agent2.conf
    sudo sed -i "s/^ServerActive=.*/ServerActive=$SERVER_IP/" /etc/zabbix/zabbix_agent2.conf
    sudo sed -i "s/^Hostname=.*/Hostname=$host_name/" /etc/zabbix/zabbix_agent2.conf

    # Enable and start the service
    log INFO "Enabling and starting the Vector agent service..."
    sudo systemctl restart zabbix-agent2.service --now
    sudo systemctl enable zabbix-agent2.service --now

    log INFO "Vector agent installation and configuration complete."
    log INFO "VECTOR SENDER: INSTALLATION COMPLETED"

elif [[ "$DISTRO_NAME" == "Oracle Linux Server" ]]; then
    log INFO "Detected Oracle Linux"
    redhat_install_requirements

    log INFO "DOWNLOADING REPOSITORY"

    if [[ "$DISTRO_VERSION" == 7.* ]]; then
        log INFO "Detected OS Version 7"
        sudo rpm -Uvh https://repo.zabbix.com/zabbix/7.0/rhel/7/x86_64/zabbix-release-latest.el7.noarch.rpm
        sudo yum clean all

        log INFO "Installing Vector Agent"
        sudo yum install zabbix-agent2 zabbix-agent2-plugin-* zabbix-sender -y

        log INFO "UPDATING CONFIGURATION FILES"
        sudo sed -i "s/^Server=.*/Server=$SERVER_IP/" /etc/zabbix/zabbix_agent2.conf
        sudo sed -i "s/^ServerActive=.*/ServerActive=$SERVER_IP/" /etc/zabbix/zabbix_agent2.conf
        sudo sed -i "s/^Hostname=.*/Hostname=$host_name/" /etc/zabbix/zabbix_agent2.conf

        log INFO "Restarting Version"
        sudo systemctl restart zabbix-agent2
        sudo systemctl enable zabbix-agent2
    fi

elif [[ "$DISTRO_NAME" == "Ubuntu" ]] && [[ "$ARCHITECTURE" == "x86_64" ]]; then
    log INFO "Detected Ubuntu Linux on x86_64 Processor"
    debian_install_requirements
    log INFO "DOWNLOADING REPOSITORY"

    if [[ "$DISTRO_VERSION" == "22.04" ]]; then
        log INFO "Detected OS Version 22.04"
        wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-2+ubuntu22.04_all.deb
        deb_name="zabbix-release_7.0-2+ubuntu22.04_all.deb"

    elif [[ "$DISTRO_VERSION" == "24.04" ]]; then
        log INFO "Detected OS Version 24.04"
        wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-2+ubuntu24.04_all.deb
        deb_name="zabbix-release_7.0-2+ubuntu24.04_all.deb"

    elif [[ "$DISTRO_VERSION" == "20.04" ]]; then
        log INFO "Detected OS Version 20.04"
        wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-2+ubuntu20.04_all.deb
        deb_name="zabbix-release_7.0-2+ubuntu20.04_all.deb"
    fi

    log INFO "INSTALLING VECTOR REPOSITORY"
    sudo dpkg -i $deb_name
    sudo apt update
    sudo rm $deb_name

    log INFO "INSTALLING VECTOR AGENT"
    sudo apt install zabbix-agent2 zabbix-agent2-plugin-* zabbix-sender -y

    # Update configuration
    log INFO "UPDATING CONFIGURATION FILES"
    sudo sed -i "s/^Server=.*/Server=$SERVER_IP/" /etc/zabbix/zabbix_agent2.conf
    sudo sed -i "s/^ServerActive=.*/ServerActive=$SERVER_IP/" /etc/zabbix/zabbix_agent2.conf
    sudo sed -i "s/^Hostname=.*/Hostname=$host_name/" /etc/zabbix/zabbix_agent2.conf

    # Enable and start the service
    log INFO "Enabling and starting the VECTOR agent service..."
    sudo systemctl enable zabbix-agent2.service
    sudo systemctl restart zabbix-agent2.service

    log INFO "VECTOR agent installation and configuration complete."

elif [[ "$DISTRO_NAME" == "Debian GNU/Linux" ]]; then
    log INFO "Detected Debian Linux"
    debian_install_requirements
    log INFO "DOWNLOADING REPOSITORY"
    
    if [[ "$DISTRO_VERSION" == "12" ]]; then
        log INFO "Detected OS Version 12"
        wget https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_7.0-2+debian12_all.deb
        deb_name="zabbix-release_7.0-2+debian12_all.deb"
    fi

    log INFO "INSTALLING VECTOR REPOSITORY"
    sudo dpkg -i $deb_name
    sudo apt update
    sudo rm $deb_name

    log INFO "INSTALLING VECTOR AGENT"
    sudo apt install zabbix-agent2 zabbix-agent2-plugin-* zabbix-sender -y

    # Update configuration
    log INFO "UPDATING VECTOR AGENT CONFIGURATION FILES."
    sudo sed -i "s/^Server=.*/Server=$SERVER_IP/" /etc/zabbix/zabbix_agent2.conf
    sudo sed -i "s/^ServerActive=.*/ServerActive=$SERVER_IP/" /etc/zabbix/zabbix_agent2.conf
    sudo sed -i "s/^Hostname=.*/Hostname=$host_name/" /etc/zabbix/zabbix_agent2.conf

    # Enable and start the service
    log INFO "Enabling and starting the VECTOR agent service..."
    sudo systemctl enable zabbix-agent2.service
    sudo systemctl restart zabbix-agent2.service

    log INFO "VECTOR agent installation and configuration complete."

else
    log INFO "Unsupported Linux distribution or version."
    exit 1
fi

log INFO "Agent Name: $host_name"
log INFO "THANKS FOR USING VECTOR ;)"