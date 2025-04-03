#!/bin/bash

# Directories containing log files
LOG_DIR_PART_1="/var/www/proxy.naturalretreats.com/logs"  # SSL logs
LOG_DIR_PART_2="/u01/apache-tomcat-9.0.96/logs"           # Tomcat logs
ALL_LOGS_DIR="/var/log/vector"  # Directory for symlinks

# Ensure the target directory exists
mkdir -p "$ALL_LOGS_DIR"

# Define log categories with their respective search directories and patterns
declare -A LOG_CATEGORIES=(
    ["ssl-error.log"]="$LOG_DIR_PART_1|nres.naturalretreats.com-sslerror_log.*.log"
    ["ssl-logs.log"]="$LOG_DIR_PART_1|nres.naturalretreats.com_ssllog.*.log"
    ["Catalina_Logs"]="$LOG_DIR_PART_2|catalina.*.log"
    ["host-manager-logs"]="$LOG_DIR_PART_2|host-manager.*.log"
    ["localhost_logs"]="$LOG_DIR_PART_2|localhost.*.log"
    ["localhost_access_logs"]="$LOG_DIR_PART_2|localhost_access_log.*.txt"
    ["manager_logs"]="$LOG_DIR_PART_2|manager.*.log"
)

# Function to find the latest modified log file based on a specific pattern
find_latest_log() {
    local search_dir=$(echo "$1" | cut -d'|' -f1)
    local file_pattern=$(echo "$1" | cut -d'|' -f2)
    local latest_log

    latest_log=$(find "$search_dir" -type f -name "$file_pattern" -printf "%T@ %p\n" 2>/dev/null | sort -rn | awk '{print $2}' | head -n 1)

    echo "$latest_log"
}

# Function to update symlink to the latest log file
update_symlink() {
    local latest_log="$1"
    local symlink_name="$ALL_LOGS_DIR/$2"

    if [ -z "$latest_log" ]; then
        echo "Warning: No log file found for $symlink_name"
        return
    fi

    # Remove existing symlink if it exists
    if [ -L "$symlink_name" ]; then
        rm "$symlink_name"
    fi

    # Create a new symlink pointing to the latest log file
    ln -s "$latest_log" "$symlink_name"
    echo "Updated symlink: $symlink_name -> $latest_log"
}

# Loop through each log category and update the symlink
for symlink in "${!LOG_CATEGORIES[@]}"; do
    latest_log=$(find_latest_log "${LOG_CATEGORIES[$symlink]}")
    update_symlink "$latest_log" "$symlink"
done


echo "Giving Permission to vector user for reading Logs"
setfacl -m u:zabbix:r /u01/apache-tomcat-9.0.96/logs/* 
setfacl -m u:zabbix:x /u01/apache-tomcat-9.0.96/logs 
setfacl -m u:zabbix:r /var/www/proxy.naturalretreats.com/logs/* 
setfacl -m u:zabbix:x /var/www/proxy.naturalretreats.com/logs
 