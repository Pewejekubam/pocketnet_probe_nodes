#!/bin/bash

# MIT License
# See LICENSE file in the root of the repository for details.

## 202502052105CST
# This is the version I'm trying to get the external config file working correctly
#  I also need to get the 'Marjority Block Height' integrated and replace the 
#  'Average Block Height' with the 'Majority Block Height'

## 202502071306CST
# Normalized version that includes debug code

## 202502071344CST
# Removed file-based seed node IP address list

## 202502071349CST
# compared MBH logic to working test script.

## 202502071355CST
# This version is working!  MGH logic and logging output are solid.
# I'll start trying to tighten up the code and the log output.

## 202502071401CST
# Consolidated runtime data into a single file

## 202502071405CST
# Enabled email testing feature


# Read configuration parameters from JSON file
cd "$(dirname "$0")"
CONFIG_FILE="probe_nodes_conf.json"

# Ensure the configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "$(date +"%Y-%m-%d %H:%M:%S") - Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Validate the configuration file format
if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    echo "$(date +"%Y-%m-%d %H:%M:%S") - Invalid JSON format in configuration file: $CONFIG_FILE"
    exit 1
fi

# Read configuration parameters from JSON file
CONFIG_DIR=$(jq -r '.CONFIG_DIR' "$CONFIG_FILE")
LOG_FILE="$CONFIG_DIR/probe_nodes.log"
RUNTIME_FILE="$CONFIG_DIR/probe_nodes_runtime.json"
SEED_NODES_URL=$(jq -r '.SEED_NODES_URL' "$CONFIG_FILE")
MAX_ALERTS=$(jq -r '.MAX_ALERTS' "$CONFIG_FILE")
ALERT_COUNT_FILE="$CONFIG_DIR/alert_count.txt"
THRESHOLD=$(jq -r '.THRESHOLD' "$CONFIG_FILE")
POCKETCOIN_CLI_ARGS=$(jq -r '.POCKETCOIN_CLI_ARGS' "$CONFIG_FILE")
SMTP_HOST=$(jq -r '.SMTP_HOST' "$CONFIG_FILE")
SMTP_PORT=$(jq -r '.SMTP_PORT' "$CONFIG_FILE")
RECIPIENT_EMAIL=$(jq -r '.RECIPIENT_EMAIL' "$CONFIG_FILE")
MSMTP_FROM=$(jq -r '.MSMTP_FROM' "$CONFIG_FILE")
MSMTP_USER=$(jq -r '.MSMTP_USER' "$CONFIG_FILE")
MSMTP_PASSWORD=$(jq -r '.MSMTP_PASSWORD' "$CONFIG_FILE")
MSMTP_TLS=$(jq -r '.MSMTP_TLS' "$CONFIG_FILE")
MSMTP_AUTH=$(jq -r '.MSMTP_AUTH' "$CONFIG_FILE")
EMAIL_TESTING=$(jq -r '.EMAIL_TESTING' "$CONFIG_FILE")

# Ensure the runtime file exists
if [ ! -f "$RUNTIME_FILE" ]; then
    echo '{"comment": "This file is used exclusively by the script and should not be edited manually.", "threshold_count": 0, "previous_node_online": true}' > "$RUNTIME_FILE"
fi

# Function to check if a required parameter is missing
check_required_param() {
    local param_name=$1
    if ! jq -e ". | has(\"$param_name\")" "$CONFIG_FILE" > /dev/null; then
        echo "$(date +"%Y-%m-%d %H:%M:%S") - Missing required parameter in configuration file: $param_name" | tee -a "$LOG_FILE"
        exit 1
    fi
}

# Check required parameters
check_required_param "CONFIG_DIR"
check_required_param "SEED_NODES_URL"
check_required_param "MAX_ALERTS"
check_required_param "THRESHOLD"
check_required_param "POCKETCOIN_CLI_ARGS"
check_required_param "SMTP_HOST"
check_required_param "SMTP_PORT"
check_required_param "RECIPIENT_EMAIL"
check_required_param "MSMTP_FROM"

# Create the necessary directories if they don't exist
mkdir -p "$CONFIG_DIR"

# Function to get the seed IP addresses
get_seed_ips() {
    curl -s $SEED_NODES_URL | grep -oP '^[^:]+' 
}

# Function to get block height and version from a node with a timeout of 1 second
get_node_info() {
    local node_ip=$1
    local url="http://$node_ip:38081"
    local response=$(curl -s --max-time 1 -X POST -H "Content-Type: application/json" -d '{"method": "getnodeinfo", "params": [], "id": ""}' $url 2>/dev/null)
    local block_height=$(echo $response | jq -r '.result.lastblock.height' 2>/dev/null)
    local version=$(echo $response | jq -r '.result.version' 2>/dev/null)
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    if [ -n "$block_height" ]; then
        echo "$timestamp ip: $node_ip block_height: $block_height version: $version" >> "$LOG_FILE"
        echo "$block_height"
    else
        echo "$timestamp ip: $node_ip - Unreachable or no response within 1 second" >> "$LOG_FILE"
    fi
}

# Function to update frequency map with block heights from nodes
update_frequency_map() {
    local origin=$1
    shift
    local -n freq_map=$1
    shift
    local node_ips=("$@")
    for node_ip in "${node_ips[@]}"; do
        local block_height=$(get_node_info "$node_ip" "$origin")
        if [ -n "$block_height" ]; then
            ((freq_map[$block_height]++))
        fi
    done
}

# Function to determine the Majority Block Height (MBH)
determine_mbh() {
    local -n freq_map=$1
    local max_count=0
    local mbh=0
    for height in "${!freq_map[@]}"; do
        if (( freq_map[$height] > max_count )); then
            max_count=${freq_map[$height]}
            mbh=$height
        elif (( freq_map[$height] == max_count )); then
            if (( height < mbh )); then
                mbh=$height
            fi
        fi
    done
    echo "$mbh"
}

# Function to send email
send_email() {
    local subject=$1
    local body=$2
    local hostname=$(hostname)
    local msmtp_command="msmtp --host=$SMTP_HOST --port=$SMTP_PORT --from=$MSMTP_FROM --logfile=/dev/stdout"
    
    if [ -n "$MSMTP_USER" ]; then
        msmtp_command="$msmtp_command --user=$MSMTP_USER"
    fi
    
    if [ -n "$MSMTP_PASSWORD" ]; then
        msmtp_command="$msmtp_command --passwordeval='echo $MSMTP_PASSWORD'"
    fi
    
    if [ "$MSMTP_TLS" = true ]; then
        msmtp_command="$msmtp_command --tls"
    fi
    
    if [ "$MSMTP_AUTH" = true ]; then
        msmtp_command="$msmtp_command --auth=on"
    fi
    
    echo -e "From: $MSMTP_FROM\nTo: $RECIPIENT_EMAIL\nSubject: $subject\n\n$body" | $msmtp_command "$RECIPIENT_EMAIL"
}

# Main function to run the script
main() {
    local hostname=$(hostname)

    # Check if email testing is enabled
    if [ "$EMAIL_TESTING" = true ]; then
        local subject="Test Email from Pocketnet Node"
        local body="This is a test email from the Pocketnet node script.\n\nSMTP Host: $SMTP_HOST\nSMTP Port: $SMTP_PORT\nRecipient Email: $RECIPIENT_EMAIL\nFrom: $MSMTP_FROM\nUser: $MSMTP_USER\nTLS: $MSMTP_TLS\nAuth: $MSMTP_AUTH"
        echo -e "EMAIL_TESTING is enabled. A test email will be sent with the following parameters:\n"
        echo -e "Subject: $subject\n"
        echo -e "Body:\n$body\n"
        send_email "$subject" "$body"
        exit 0
    fi

    # Get seed IP addresses
    seed_node_ips=($(get_seed_ips))

    # Check if the seed IPs array is empty
    if [ ${#seed_node_ips[@]} -eq 0 ]; then
        # Log the message
        echo "$(date +"%Y-%m-%d %H:%M:%S") - No seed nodes retrieved. The seed IPs array is empty." >> "$LOG_FILE"

        # Notify the user via email
        send_email "Seed Node Retrieval Alert" "No seed nodes retrieved. The seed IPs array is empty."

        # Decide whether to exit or continue
        # exit 1
    fi

    # Initialize frequency map
    declare -A frequency_map

    # Update frequency map with block heights from seed nodes
    update_frequency_map "seed_node" frequency_map "${seed_node_ips[@]}"

    # Get connected nodes' IP addresses
    local peer_info=$(pocketcoin-cli $POCKETCOIN_CLI_ARGS getpeerinfo)
    local peer_ips=($(echo "$peer_info" | jq -r '.[].addr' | cut -d':' -f1))

    # Update frequency map with block heights from connected nodes
    update_frequency_map "locally_connected_node" frequency_map "${peer_ips[@]}"

    # Determine the Majority Block Height (MBH)
    mbh=$(determine_mbh frequency_map)

    # Get local node block height
    local local_height
    local node_online=true
    if ! local_height=$(pocketcoin-cli $POCKETCOIN_CLI_ARGS getblockcount 2>/dev/null); then
        node_online=false
        local_height="unknown"
    else
        local response=$(curl -s --max-time 1 -X POST -H "Content-Type: application/json" -d '{"method": "getnodeinfo", "params": [], "id": ""}' http://localhost:38081 2>/dev/null)
        local_height=$(echo $response | jq -r '.result.lastblock.height' 2>/dev/null)
    fi
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # Get peer count
    local peer_count=$(pocketcoin-cli $POCKETCOIN_CLI_ARGS getpeerinfo | jq -r 'length')

    # Log local node information
    echo "$timestamp ip: localhost block_height: $local_height" >> "$LOG_FILE"

    # Check on-chain condition
    local on_chain=false
    if [ "$node_online" = true ] && (( local_height >= mbh - 50 && local_height <= mbh + 50 )); then
        on_chain=true
    elif [ "$node_online" = false ]; then
        on_chain="unknown"
    fi

    # Log on-chain condition, node online status, and peer count
    echo "$timestamp Majority Block Height: $mbh" >> "$LOG_FILE"
    echo "$timestamp On-Chain: $on_chain" >> "$LOG_FILE"
    echo "$timestamp Node Online: $node_online" >> "$LOG_FILE"
    echo "$timestamp Peer Count: $peer_count" >> "$LOG_FILE"

    # Read the current alert count
    local alert_count=0
    if [ -f "$ALERT_COUNT_FILE" ]; then
        alert_count=$(cat "$ALERT_COUNT_FILE")
    fi

    # Read the current runtime data
    local threshold_count=$(jq -r '.threshold_count' "$RUNTIME_FILE")
    local previous_node_online=$(jq -r '.previous_node_online' "$RUNTIME_FILE")

    # Increment threshold count if node is offline
    if [ "$node_online" = false ]; then
        threshold_count=$((threshold_count + 1))
        jq --argjson count "$threshold_count" '.threshold_count = $count' "$RUNTIME_FILE" > "$RUNTIME_FILE.tmp" && mv "$RUNTIME_FILE.tmp" "$RUNTIME_FILE"
    else
        # Reset threshold count if node is back online
        threshold_count=0
        jq --argjson count "$threshold_count" '.threshold_count = $count' "$RUNTIME_FILE" > "$RUNTIME_FILE.tmp" && mv "$RUNTIME_FILE.tmp" "$RUNTIME_FILE"
        
        # Send email if node has come back online
        if [ "$previous_node_online" = false ]; then
            local subject="Pocketnet Node Status - Node is back ONLINE"
            local body="Timestamp: $timestamp\nLocal Node Block Height: $local_height\nMajority Block Height: $mbh\nOn-Chain: $on_chain\nNode Online: $node_online\nPeer Count: $peer_count\nThreshold Count: $threshold_count"
            send_email "$subject" "$body"
            echo "$timestamp Email Sent: $subject" >> "$LOG_FILE"
        fi
    fi

    # Save the current node online status for the next run
    jq --argjson online "$node_online" '.previous_node_online = $online' "$RUNTIME_FILE" > "$RUNTIME_FILE.tmp" && mv "$RUNTIME_FILE.tmp" "$RUNTIME_FILE"

    # Send email if threshold is exceeded
    if [ "$threshold_count" -ge "$THRESHOLD" ]; then
        if [ "$alert_count" -lt "$MAX_ALERTS" ]; then
            local subject="Pocketnet Node Status - Node Online: $node_online / On-Chain: $on_chain"
            local body="Timestamp: $timestamp\nLocal Node Block Height: $local_height\nMajority Block Height: $mbh\nOn-Chain: $on_chain\nNode Online: $node_online\nPeer Count: $peer_count\nThreshold Count: $threshold_count"
            if [ "$alert_count" -eq "$((MAX_ALERTS - 1))" ]; then
                body="$body\n\nThis is the last alert. Further emails will be suppressed until the node comes back online."
            fi
            send_email "$subject" "$body"
            echo "$timestamp Email Sent: $subject" >> "$LOG_FILE"
            alert_count=$((alert_count + 1))
            echo "$alert_count" > "$ALERT_COUNT_FILE"
        fi
    fi
}

# Run the main function
main