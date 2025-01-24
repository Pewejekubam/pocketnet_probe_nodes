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

# Function to get block height from a node with a timeout of 1 second
get_node_info() {
    local node_ip=$1
    local origin=$2
    local url="http://$node_ip:38081"
    local response=$(curl -s --max-time 1 -X POST -H "Content-Type: application/json" -d '{"method": "getnodeinfo", "params": [], "id": ""}' $url 2>/dev/null)
    local block_height=$(echo $response | jq -r '.result.lastblock.height' 2>/dev/null)
    if [ -n "$block_height" ]; then
        local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        echo "$timestamp $origin $node_ip $block_height"
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

# Function to calculate mean and standard deviation
calculate_stats() {
    local heights=("$@")
    local sum=0
    local count=${#heights[@]}
    echo "Heights: ${heights[@]}"  # Debugging information
    for height in "${heights[@]}"; do
        sum=$((sum + height))
    done
    local mean=$(echo "scale=2; $sum / $count" | bc)
    local variance=0
    for height in "${heights[@]}"; do
        variance=$(echo "scale=2; $variance + ($height - $mean) * ($height - $mean)" | bc)
    done
    if [ $count -gt 1 ]; then
        local stddev=$(echo "scale=2; sqrt($variance / $count)" | bc)
    else
        local stddev=0
    fi
    echo "Mean: $mean, Stddev: $stddev"  # Debugging information
    echo "$mean $stddev"
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
        # Get block height from each seed node
        local info=$(get_node_info "$node_ip" "seed_node")
        if [ -n "$info" ]; then
            seed_heights+=("${info##* }")
            echo "$info" >> "$LOG_FILE"
        fi
    done < seed_ips.txt

    # Get connected nodes' IP addresses and block heights
    local connected_heights=()
    while IFS= read -r node_ip; do
        # Get block height from each connected node
        local info=$(get_node_info "$node_ip" "locally_connected_node")
        if [ -n "$info" ]; then
            connected_heights+=("${info##* }")
            echo "$info" >> "$LOG_FILE"
        fi
    done < <(pocketcoin-cli getpeerinfo | jq -r '.[].addr' | cut -d':' -f1)

    # Calculate mean and standard deviation
    local all_heights=("${seed_heights[@]}" "${connected_heights[@]}")
    local stats=$(calculate_stats "${all_heights[@]}")
    local mean=$(echo "$stats" | cut -d' ' -f1)
    local stddev=$(echo "$stats" | cut -d' ' -f2)

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

    # Log local node information
    echo "$timestamp local_node $(hostname) $local_height" >> "$LOG_FILE"

    # Check on-chain condition
    local on_chain=false
    if [ "$node_online" = true ] && (( local_height <= mean + 50 && local_height >= mean - 50 )); then
        on_chain=true
    elif [ "$node_online" = false ]; then
        on_chain="unknown"
    fi

    # Log on-chain condition and node online status
    echo "$timestamp Local Node Block Height: $local_height" >> "$LOG_FILE"
    echo "$timestamp Mean Block Height: $mean" >> "$LOG_FILE"
    echo "$timestamp Standard Deviation: $stddev" >> "$LOG_FILE"
    echo "$timestamp On-Chain: $on_chain" >> "$LOG_FILE"
    echo "$timestamp Node Online: $node_online" >> "$LOG_FILE"

    # Read the current alert count
    local alert_count=0
    if [ -f "$ALERT_COUNT_FILE" ]; then
        alert_count=$(cat "$ALERT_COUNT_FILE")
    fi

    # Send email if on-chain condition is false or node is offline
    if [ "$on_chain" = false ] || [ "$node_online" = false ]; then
        if [ "$alert_count" -lt "$MAX_ALERTS" ]; then
            local subject="Pocketnet Node Status - Node Online: $node_online / On-Chain: $on_chain"
            local body="Timestamp: $timestamp\nLocal Node Block Height: $local_height\nMean Block Height: $mean\nStandard Deviation: $stddev\nOn-Chain: $on_chain\nNode Online: $node_online"
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
            local body="Timestamp: $timestamp\nLocal Node Block Height: $local_height\nMean Block Height: $mean\nStandard Deviation: $stddev\nOn-Chain: $on_chain\nNode Online: $node_online"
            send_email "$subject" "$body"
            echo "$timestamp Email Sent: $subject" >> "$LOG_FILE"
            echo "0" > "$ALERT_COUNT_FILE"
        fi
    fi
}

# Run the main function
main
