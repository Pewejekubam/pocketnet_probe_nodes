## 202501061829
# This version of the probe_nodes.sh script uses a simple average of the BH
# of all the seed and connected nodes. If local node is 50 blocks or less 
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
        get_node_info "$ip" "connected"
    done
}

# Main script execution
get_seed_ips
while read -r seed_ip; do
    get_node_info "$seed_ip" "seed"
done < seed_ips.txt

get_connected_nodes
