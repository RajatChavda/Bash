#!/bin/bash

# Variables
SERVER_IP=$1  # Replace with your Zabbix server IP
ZABBIX_AGENT_CONF="/etc/zabbix/zabbix_agent2.conf"
ZABBIX_AGENT_ALT_CONF="/etc/zabbix/zabbix_agent.conf"

# Get Public IP and Set Custom Hostname
PUBLIC_IP=$(wget -qO- ifconfig.me/ip)
HOSTNAME="asg-ip-$PUBLIC_IP"


echo "Public IP: $PUBLIC_IP"
echo "Hostname: $HOSTNAME"

# Add Zabbix user to necessary groups
sudo usermod -aG adm zabbix
sudo usermod -aG root zabbix

# Check if the agent2 config exists, otherwise use agent1 config
if [ -f "$ZABBIX_AGENT_CONF" ]; then
    CONF_FILE="$ZABBIX_AGENT_CONF"
elif [ -f "$ZABBIX_AGENT_ALT_CONF" ]; then
    CONF_FILE="$ZABBIX_AGENT_ALT_CONF"
else
    echo "No Zabbix agent configuration file found!"
    exit 1
fi

echo "Using configuration file: $CONF_FILE"

# Set Hostname, Server, and ServerActive in Zabbix Configuration
sudo sed -i "s/^Hostname=.*/Hostname=$HOSTNAME/" "$CONF_FILE"
sudo sed -i "s/^Server=.*/Server=$SERVER_IP/" "$CONF_FILE"
sudo sed -i "s/^ServerActive=.*/ServerActive=$SERVER_IP/" "$CONF_FILE"

# Restart Zabbix Agent
if systemctl list-units --full -all | grep -q "zabbix-agent2.service"; then
    sudo systemctl restart zabbix-agent2
else
    sudo systemctl restart zabbix-agent
fi

# Verify if the service is running
if systemctl is-active --quiet zabbix-agent2; then
    echo "Zabbix Agent 2 is running."
elif systemctl is-active --quiet zabbix-agent; then
    echo "Zabbix Agent is running."
else
    echo "Zabbix Agent failed to start!"
    exit 1
fi

# Test connection with Zabbix Agent
if command -v zabbix_agent2 &> /dev/null; then
    zabbix_agent2 -t system.hostname
elif command -v zabbix_agentd &> /dev/null; then
    zabbix_agentd -t system.hostname
else
    echo "Zabbix Agent command not found!"
fi

echo "Installing CRON"
sudo yum install cronie -y
sudo systemctl start crond
sudo systemctl enable crond

echo "Zabbix Agent setup completed successfully!"
 