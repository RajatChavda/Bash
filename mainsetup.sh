#!/bin/bash

# Check if both arguments are provided
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <GitHub_PAT> <IP_Address>"
    exit 1
fi

# Define the authorization token and IP address from arguments
TOKEN="$1"
IP="$2"
echo $2

# Get the system's hostname
HOSTNAME=$(hostname)

# Path to the directory
DIR="/opt/vector-agent"

# Check if the directory exists
if [ -d "$DIR" ]; then
    echo "Directory already exists. Success!"
else
    sudo mkdir -p "$DIR" && echo "Directory created successfully."
fi

# Function to check if a package is installed (Debian & RedHat based systems)
is_installed() {
    dpkg -l | grep -qE "$1" || rpm -q "$1" &>/dev/null
}

cd /opt/vector-agent

# Check if Zabbix Agent is installed
if is_installed "zabbix-agent" || is_installed "zabbix-agent2"; then
    echo "Zabbix Agent is installed."
    wget --header="Authorization: token $TOKEN" -O agentsetup.sh https://raw.githubusercontent.com/RajatChavda/Bash/refs/heads/main/agentsetup.sh \
        && chmod +x agentsetup.sh \
        && ./agentsetup.sh "$IP"
else
    echo "Zabbix Agent is not installed."
    wget --header="Authorization: token $TOKEN" -O vectoragent.sh https://raw.githubusercontent.com/RajatChavda/Bash/refs/heads/main/agent%204.sh \
        && chmod +x vectoragent.sh \
        && ./vectoragent.sh "$IP"       
fi

wget --header="Authorization: token $TOKEN" -O logmonitoring.sh https://raw.githubusercontent.com/RajatChavda/Bash/refs/heads/main/logmonitoring.sh \
        && chmod +x logmonitoring.sh \
        && ./logmonitoring.sh

# Path to your script that you want to run at midnight
SCRIPT_PATH="/opt/vector-agent/logmonitoring.sh"

# Cron job entry to run the script at 00:00 every day
CRON_ENTRY="0 0 * * * $SCRIPT_PATH"

# Check if the cron job already exists
(crontab -l 2>/dev/null | grep -F "$SCRIPT_PATH") || echo "$CRON_ENTRY" | crontab -

echo "Cron job has been added to run the script at midnight every day."
