## 202501061829
# This verion of the probe_nodes.sh script uses a simple average of the BH
# of all the seed and connected nodes.  If local node is 50 blocks or less 
# behind the average, then the node is considered "on_chain"

## 202501061919
# This version will start work on adding 'version' to the log file.

#!/bin/bash

# Configuration parameters
SMTP_HOST="10.168.32.63"
SMTP_PORT=25
SENDER_DOMAIN="dennen.us"
RECIPIENT_EMAIL="pocket_node_alert@dennen.com"
LOG_FILE="$HOME/probe_nodes.log"
SEED_NODES_URL="https://raw.githubusercontent.com/pocketnetteam/pocketnet.core/76b20a013ee60d019dcfec3a4714a4e21a8b432c/contrib/seeds/nodes_main.txt"
MAX_ALERTS=3
ALERT_COUNT_FILE="$HOME/alert_count.txt"

# Function to get the seed IP addresses
get_seed_ips() {
    curl -s $SEED_NODES_URL | grep -oP '^[^:]+' > seed_ips.txt
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
        echo "$timestamp $origin $node_ip $block_height $version" >> "$LOG_FILE"
        echo "$block_height"
    fi
}

# Function to get connected nodes' IP addresses and block heights
get_connected_nodes() {
    local peer_info=$(pocketcoin-cli getpeerinfo)
    local peer_ips=$(echo "$peer_info" | jq -r '.[].addr' | cut -d':' -f1)
    for ip in $peer_ips; do
        get_node_info "$ip" "locally_connected_node"
    done
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
    echo -e "From: $hostname@$SENDER_DOMAIN\nTo: $RECIPIENT_EMAIL\nSubject: $subject\n\n$body" | msmtp \
        --host=$SMTP_HOST \
        --port=$SMTP_PORT \
        --from="$hostname@$SENDER_DOMAIN" \
        "$RECIPIENT_EMAIL"
}

# Main function to run the script
main() {
    local hostname=$(hostname)

    # Get seed IP addresses
    get_seed_ips

    # Read all seed node IP addresses from the list
    local seed_heights=()
    while IFS= read -r node_ip; do
        # Get block height and version from each seed node
        local info=$(get_node_info "$node_ip" "seed_node")
        if [ -n "$info" ]; then
            seed_heights+=("$info")
        fi
    done < seed_ips.txt

    # Get connected nodes' IP addresses, block heights, and versions
    local connected_heights=()
    while IFS= read -r node_ip; do
        # Get block height and version from each connected node
        local info=$(get_node_info "$node_ip" "locally_connected_node")
        if [ -n "$info" ]; then
            connected_heights+=("$info")
        fi
    done < <(pocketcoin-cli getpeerinfo | jq -r '.[].addr' | cut -d':' -f1)

    # Combine seed and connected heights
    all_heights=("${seed_heights[@]}" "${connected_heights[@]}")

    # Calculate the average block height (BH) from the sample
    average_bh=$(calculate_average_bh "${all_heights[@]}")

    # Get local node block height
    local local_height
    local node_online=true
    if ! local_height=$(pocketcoin-cli getblockcount 2>/dev/null); then
        node_online=false
        local_height="unknown"
    else
        local response=$(curl -s --max-time 1 -X POST -H "Content-Type: application/json" -d '{"method": "getnodeinfo", "params": [], "id": ""}' http://localhost:38081 2>/dev/null)
        local_height=$(echo $response | jq -r '.result.lastblock.height' 2>/dev/null)
    fi
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # Get peer count
    local peer_count=$(pocketcoin-cli getpeerinfo | jq -r 'length')

    # Log local node information
    echo "$timestamp local_node $(hostname) $local_height" >> "$LOG_FILE"

    # Check on-chain condition
    local on_chain=false
    if [ "$node_online" = true ] && (( local_height >= average_bh - 50 && local_height <= average_bh + 50 )); then
        on_chain=true
    elif [ "$node_online" = false ]; then
        on_chain="unknown"
    fi

    # Log on-chain condition, node online status, and peer count
    echo "$timestamp Average Block Height: $average_bh" >> "$LOG_FILE"
    echo "$timestamp On-Chain: $on_chain" >> "$LOG_FILE"
    echo "$timestamp Node Online: $node_online" >> "$LOG_FILE"
    echo "$timestamp Peer Count: $peer_count" >> "$LOG_FILE"

    # Read the current alert count
    local alert_count=0
    if [ -f "$ALERT_COUNT_FILE" ]; then
        alert_count=$(cat "$ALERT_COUNT_FILE")
    fi

    # Send email if on-chain condition is false or node is offline
    if [ "$on_chain" = false ] || [ "$node_online" = false ]; then
        if [ "$alert_count" -lt "$MAX_ALERTS" ]; then
            local subject="Pocketnet Node Status - Node Online: $node_online / On-Chain: $on_chain"
            local body="Timestamp: $timestamp\nLocal Node Block Height: $local_height\nAverage Block Height: $average_bh\nOn-Chain: $on_chain\nNode Online: $node_online\nPeer Count: $peer_count"
            if [ "$alert_count" -eq "$((MAX_ALERTS - 1))" ]; then
                body="$body\n\nThis is the last alert. Further emails will be suppressed until the node comes back online."
            fi
            send_email "$subject" "$body"
            echo "$timestamp Email Sent: $subject" >> "$LOG_FILE"
            alert_count=$((alert_count + 1))
            echo "$alert_count" > "$ALERT_COUNT_FILE"
        fi
    else
        # Reset alert count if node is back online and on-chain
        if [ "$alert_count" -gt 0 ]; then
            local subject="Pocketnet Node Status - Node Online: $node_online / On-Chain: $on_chain"
            local body="Timestamp: $timestamp\nLocal Node Block Height: $local_height\nAverage Block Height: $average_bh\nOn-Chain: $on_chain\nNode Online: $node_online\nPeer Count: $peer_count"
            send_email "$subject" "$body"
            echo "$timestamp Email Sent: $subject" >> "$LOG_FILE"
            echo "0" > "$ALERT_COUNT_FILE"
        fi
    fi
}

# Run the main function
main
