#!/bin/bash

# MIT License
# See LICENSE file in the root of the repository for details.

# Configuration parameters
# Note: Not all parameters are necessary to configure for your particular email setup.
# Leave blank ("") any MSMTP parameters that are not to be passed to the MTA.
CONFIG_DIR="$HOME/probe_nodes"
LOG_FILE="$CONFIG_DIR/probe_nodes.log"
TEMP_LOG_FILE="$CONFIG_DIR/probe_nodes_temp.log"
SEED_NODES_URL="https://raw.githubusercontent.com/pocketnetteam/pocketnet.core/76b20a013ee60d019dcfec3a4714a4e21a8b432c/contrib/seeds/nodes_main.txt"
MAX_ALERTS=3
ALERT_COUNT_FILE="$CONFIG_DIR/alert_count.txt"
THRESHOLD=3
THRESHOLD_COUNT_FILE="$CONFIG_DIR/threshold_count.txt"
BAN_LIST_FILE="$CONFIG_DIR/ban_list.txt"
BAN_THRESHOLD=10000  # Number of blocks behind to consider banning
# Custom arguments for pocketcoin-cli
# Note: This can be an empty string if no custom arguments are needed.
POCKETCOIN_CLI_ARGS="-rpcport=67530 -conf=/path/to/pocketnet/pocketcoin.conf"
SMTP_HOST="smtp.example.com"
SMTP_PORT=587
RECIPIENT_EMAIL="alert@example.com"
MSMTP_FROM="node@example.com"
MSMTP_USER="your_email@example.com"
MSMTP_PASSWORD="your_password"
MSMTP_TLS=true
MSMTP_AUTH=true


# Create the necessary directories if they don't exist
mkdir -p "$CONFIG_DIR"

# Function to get the seed IP addresses
get_seed_ips() {
    curl -s $SEED_NODES_URL | grep -oP '^[^:]+' > "$CONFIG_DIR/seed_ips.txt"
}

# Function to get block height and version from a node with a timeout of 1 second
get_node_info() {
    local node_ip=$1
    local origin=$2
    local url="http://$node_ip:38081"
    local response=$(curl -s --max-time 1 -X POST -H "Content-Type: application/json" -d '{"method": "getnodeinfo", "params": [], "id": ""}' $url 2>/dev/null)
    local block_height=$(echo $response | jq -r '.result.lastblock.height' 2>/dev/null)
    local version=$(echo $response | jq -r '.result.version' 2>/dev/null)
    if [ -n "$block_height" ]; then
        local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        echo "$timestamp origin: $origin ip: $node_ip block_height: $block_height version: $version" | tee -a "$LOG_FILE" >> "$TEMP_LOG_FILE"
        echo "$block_height"
    fi
}

# Function to get connected nodes' IP addresses and block heights
get_connected_nodes() {
    local peer_info=$(pocketcoin-cli $POCKETCOIN_CLI_ARGS getpeerinfo)
    local peer_ips=$(echo "$peer_info" | jq -r '.[].addr' | cut -d':' -f1)
    local connected_heights=()
    for ip in $peer_ips; do
        local block_height=$(get_node_info "$ip" "locally_connected_node")
        if [ -n "$block_height" ]; then
            connected_heights+=("$block_height")
        fi
    done
    echo "${connected_heights[@]}"
}

# Function to calculate the average block height (BH) from the sample
calculate_average_bh() {
    local heights=("$@")
    local sum=0
    local count=${#heights[@]}
    for height in "${heights[@]}"; do
        sum=$((sum + height))
    done
    if [ $count -gt 0 ]; then
        local average_bh=$((sum / count))
    else
        local average_bh=0
    fi
    echo "$average_bh"
}

# Function to send email
send_email() {
    local subject=$1
    local body=$2
    local hostname=$(hostname)
    local msmtp_command="msmtp --host=$SMTP_HOST --port=$SMTP_PORT --from=$MSMTP_FROM"
    
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

# Function to update the ban list
update_ban_list() {
    local node_ip=$1
    local current_ban_list=()
    
    # Read the current ban list into an array
    if [ -f "$BAN_LIST_FILE" ]; then
        while IFS= read -r ip; do
            current_ban_list+=("$ip")
        done < "$BAN_LIST_FILE"
    fi
    
    # Check if the IP is already in the ban list
    if [[ ! " ${current_ban_list[@]} " =~ " ${node_ip} " ]]; then
        echo "$node_ip" >> "$BAN_LIST_FILE"
    fi
}

# Main function to run the script
main() {
    local hostname=$(hostname)

    # Get seed IP addresses
    get_seed_ips

    # Read all seed node IP addresses from the list
    local seed_heights=()
    while IFS= read -r node_ip; do
        # Get block height from each seed node
        local block_height=$(get_node_info "$node_ip" "seed_node")
        if [ -n "$block_height" ]; then
            seed_heights+=("$block_height")
        fi
    done < "$CONFIG_DIR/seed_ips.txt"

    # Get connected nodes' block heights
    local connected_heights=($(get_connected_nodes))

    # Combine seed and connected heights
    all_heights=("${seed_heights[@]}" "${connected_heights[@]}")

    # Calculate the average block height (BH) from the sample
    average_bh=$(calculate_average_bh "${all_heights[@]}")

    # Identify and ban nodes significantly behind the average
    local valid_heights=()
    for height in "${all_heights[@]}"; do
        if (( height < average_bh - BAN_THRESHOLD )); then
            local node_ip=$(grep "block_height: $height" "$TEMP_LOG_FILE" | awk -F 'ip: ' '{print $2}' | awk '{print $1}')
            update_ban_list "$node_ip"
        else
            valid_heights+=("$height")
        fi
    done

    # Recalculate the average block height (BH) after excluding banned nodes
    average_bh=$(calculate_average_bh "${valid_heights[@]}")

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
    echo "$timestamp origin: local_node hostname: $(hostname) block_height: $local_height" | tee -a "$LOG_FILE" >> "$TEMP_LOG_FILE"

    # Check on-chain condition
    local on_chain=false
    if [ "$node_online" = true ] && (( local_height >= average_bh - 50 && local_height <= average_bh + 50 )); then
        on_chain=true
    elif [ "$node_online" = false ]; then
        on_chain="unknown"
    fi

    # Log on-chain condition, node online status, and peer count
    echo "$timestamp Average Block Height: $average_bh" | tee -a "$LOG_FILE" >> "$TEMP_LOG_FILE"
    echo "$timestamp On-Chain: $on_chain" | tee -a "$LOG_FILE" >> "$TEMP_LOG_FILE"
    echo "$timestamp Node Online: $node_online" | tee -a "$LOG_FILE" >> "$TEMP_LOG_FILE"
    echo "$timestamp Peer Count: $peer_count" | tee -a "$LOG_FILE" >> "$TEMP_LOG_FILE"

    # Read the current alert count
    local alert_count=0
    if [ -f "$ALERT_COUNT_FILE" ]; then
        alert_count=$(cat "$ALERT_COUNT_FILE")
    fi

    # Read the current threshold count
    local threshold_count=0
    if [ -f "$THRESHOLD_COUNT_FILE" ]; then
        threshold_count=$(cat "$THRESHOLD_COUNT_FILE")
    fi

    # Read the previous node online status
    previous_node_online=true
    if [ -f "$CONFIG_DIR/previous_node_online.txt" ]; then
        previous_node_online=$(cat "$CONFIG_DIR/previous_node_online.txt")
    fi

    # Increment threshold count if node is offline
    if [ "$node_online" = false ]; then
        threshold_count=$((threshold_count + 1))
        echo "$threshold_count" > "$THRESHOLD_COUNT_FILE"
    else
        # Reset threshold count if node is back online
        threshold_count=0
        echo "$threshold_count" > "$THRESHOLD_COUNT_FILE"
        
        # Send email if node has come back online
        if [ "$previous_node_online" = false ]; then
            local subject="Pocketnet Node Status - Node is back ONLINE"
            local body="Timestamp: $timestamp\nLocal Node Block Height: $local_height\nAverage Block Height: $average_bh\nOn-Chain: $on_chain\nNode Online: $node_online\nPeer Count: $peer_count\nThreshold Count: $threshold_count"
            send_email "$subject" "$body"
            echo "$timestamp Email Sent: $subject" | tee -a "$LOG_FILE" >> "$TEMP_LOG_FILE"
        fi
    fi

    # Save the current node online status for the next run
    echo "$node_online" > "$CONFIG_DIR/previous_node_online.txt"

    # Send email if threshold is exceeded
    if [ "$threshold_count" -ge "$THRESHOLD" ]; then
        if [ "$alert_count" -lt "$MAX_ALERTS" ]; then
            local subject="Pocketnet Node Status - Node Online: $node_online / On-Chain: $on_chain"
            local body="Timestamp: $timestamp\nLocal Node Block Height: $local_height\nAverage Block Height: $average_bh\nOn-Chain: $on_chain\nNode Online: $node_online\nPeer Count: $peer_count\nThreshold Count: $threshold_count"
            if [ "$alert_count" -eq "$((MAX_ALERTS - 1))" ]; then
                body="$body\n\nThis is the last alert. Further emails will be suppressed until the node comes back online."
            fi
            send_email "$subject" "$body"
            echo "$timestamp Email Sent: $subject" | tee -a "$LOG_FILE" >> "$TEMP_LOG_FILE"
            alert_count=$((alert_count + 1))
            echo "$alert_count" > "$ALERT_COUNT_FILE"
        fi
    fi

    # Clean up the temporary log file
    rm "$TEMP_LOG_FILE"
}

# Run the main function
main
