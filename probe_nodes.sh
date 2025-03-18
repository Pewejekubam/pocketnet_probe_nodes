#!/bin/bash
## 202503050856CST


# MIT License

# Read configuration parameters from JSON file
cd "$(dirname "$0")" || { echo "Failed to change directory"; exit 1; }
CONFIG_FILE="probe_nodes_conf.json"

# Ensure the configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Validate the configuration file format
if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    echo "Invalid JSON format in configuration file: $CONFIG_FILE"
    exit 1
fi

# Read configuration parameters from JSON file
CONFIG_DIR=$(jq -r '.CONFIG_DIR' "$CONFIG_FILE")
LOG_FILE="$CONFIG_DIR/probe_nodes.log"

# Function to log messages
log_message() {
    local message=$1
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $message" >> "$LOG_FILE"
}

# Continue with the rest of the configuration
RUNTIME_FILE="$CONFIG_DIR/probe_nodes_runtime.json"
SEED_NODES_URL=$(jq -r '.SEED_NODES_URL' "$CONFIG_FILE")
MAX_ALERTS=$(jq -r '.MAX_ALERTS' "$CONFIG_FILE")
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
MAJORITY_LAG_THRESH=$(jq -r '.MAJORITY_LAG_THRESH' "$CONFIG_FILE")

# Ensure the runtime file exists
if [ ! -f "$RUNTIME_FILE" ]; then
    echo '{"comment": "This file is used exclusively by the script and should not be edited manually.", "offline_check_count": 0, "previous_node_online": true, "sent_alert_count": 0, "online_start_time": "", "offline_start_time": "", "consecutive_lag_checks": 0}' > "$RUNTIME_FILE"
fi

# Function to log messages
log_message() {
    local message=$1
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $message" | tee -a "$LOG_FILE"
}

# Function to check if a required parameter is missing
check_required_param() {
    local param_name=$1
    if ! jq -e ". | has(\"$param_name\")" "$CONFIG_FILE" > /dev/null; then
        log_message "Missing required parameter in configuration file: $param_name"
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
check_required_param "MAJORITY_LAG_THRESH"

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
        echo "$block_height $version"
    else
        echo "unreachable"
    fi
}

# Function to update frequency map with block heights from nodes
update_frequency_map() {
    local origin=$1
    shift
    local -n freq_map=$1
    shift
    local node_ips=("$@")
    local log_messages=()
    for node_ip in "${node_ips[@]}"; do
        local node_info=$(get_node_info "$node_ip" "$origin")
        if [[ "$node_info" != "unreachable" ]]; then
            local block_height=$(echo "$node_info" | awk '{print $1}')
            local version=$(echo "$node_info" | awk '{print $2}')
            ((freq_map[$block_height]++))
            log_messages+=("ip: $node_ip block_height: $block_height version: $version")
        else
            log_messages+=("ip: $node_ip - Unreachable or no response within 1 second")
        fi
    done
    for message in "${log_messages[@]}"; do
        log_message "$message"
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
    
    if [ "$MSMTP_TLS" = "true" ]; then
        msmtp_command="$msmtp_command --tls"
    fi
    
    if [ "$MSMTP_AUTH" = "true" ]; then
        msmtp_command="$msmtp_command --auth=on"
    fi
    
    echo -e "From: $MSMTP_FROM\nTo: $RECIPIENT_EMAIL\nSubject: $subject\n\n$body" | $msmtp_command "$RECIPIENT_EMAIL"
}

# Function to reset LAG-related counters
reset_lag_counters() {
    jq '.consecutive_lag_checks = 0' "$RUNTIME_FILE" > "$RUNTIME_FILE.tmp" && mv "$RUNTIME_FILE.tmp" "$RUNTIME_FILE"
}

# Main function to run the script
main() {
    local hostname=$(hostname)

    # Check if email testing is enabled
    if [ "$EMAIL_TESTING" = "true" ]; then
        local subject="Test Email from Pocketnet Node"
        local body="This is a test email from the Pocketnet node script.\n\nSMTP Host: $SMTP_HOST\nSMTP Port: $SMTP_PORT\nRecipient Email: $RECIPIENT_EMAIL\nFrom: $MSMTP_FROM\nUser: $MSMTP_USER\nTLS: $MSMTP_TLS\nAuth: $MSMTP_AUTH"
        log_message "EMAIL_TESTING is enabled. A test email will be sent with the following parameters:\nSubject: $subject\nBody:\n$body\n"
        log_message "EMAIL_TESTING is enabled. A test email will be sent with the following parameters:\nSubject: $subject\nBody:\n$body\n"
        send_email "$subject" "$body"
        exit 0
    fi

    # Get seed IP addresses
    seed_node_ips=($(get_seed_ips))

    # Check if the seed IPs array is empty
    if [ ${#seed_node_ips[@]} -eq 0 ]; then
        # Log the message
        log_message "No seed nodes retrieved. The seed IPs array is empty."
        log_message "No seed nodes retrieved. The seed IPs array is empty."

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
    local peer_info
    if ! peer_info=$(pocketcoin-cli $POCKETCOIN_CLI_ARGS getpeerinfo 2>/dev/null); then
        log_message "Failed to get peer info"
        peer_info="[]"
    fi
    local peer_ips=($(echo "$peer_info" | jq -r '.[].addr' | cut -d':' -f1))

    # Update frequency map with block heights from connected nodes
    update_frequency_map "locally_connected_node" frequency_map "${peer_ips[@]}"

    # Determine the Majority Block Height (MBH)
    mbh=$(determine_mbh frequency_map)

    # Get local node block height
    local local_height
    local node_online="true"
    if ! local_height=$(pocketcoin-cli $POCKETCOIN_CLI_ARGS getblockcount 2>/dev/null); then
        node_online="false"
        local_height="unknown"
    else
        local response=$(curl -s --max-time 1 -X POST -H "Content-Type: application/json" -d '{"method": "getnodeinfo", "params": [], "id": ""}' http://localhost:38081 2>/dev/null)
        local_height=$(echo $response | jq -r '.result.lastblock.height' 2>/dev/null)
    fi
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # Get peer count
    local peer_count=$(echo "$peer_info" | jq -r 'length')

    # Log local node information
    log_message "ip: localhost block_height: $local_height"
    log_message "ip: localhost block_height: $local_height"

    # Check on-chain condition
    local on_chain="false"
    if [ "$node_online" = "true" ] && [[ "$local_height" =~ ^[0-9]+$ ]] && [[ "$mbh" =~ ^[0-9]+$ ]]; then
        if (( local_height >= mbh - MAJORITY_LAG_THRESH && local_height <= mbh + MAJORITY_LAG_THRESH )); then
            on_chain="true"
        fi
    elif [ "$node_online" = "false" ]; then
        on_chain="unknown"
    fi

    # Log on-chain condition, node online status, and peer count
    log_message "Majority Block Height: $mbh"
    log_message "On-Chain: $on_chain"
    log_message "Node Online: $node_online"
    log_message "Peer Count: $peer_count"

    # Check if node's block height exceeds the majority lag threshold
    if [ "$node_online" = "true" ] && [ "$local_height" != "unknown" ]; then
        if [[ "$local_height" =~ ^[0-9]+$ ]] && [[ "$mbh" =~ ^[0-9]+$ ]]; then
            local block_lag=$((mbh - local_height))
            if (( block_lag > MAJORITY_LAG_THRESH )); then
                local subject="Node Alert: Block Lag Detected"
                local body="Timestamp: $timestamp\nLocal Node Block Height: $local_height\nMajority Block Height: $mbh\nOn-Chain: $on_chain\nNode Online: $node_online\nPeer Count: $peer_count\nNode Lag Behind Majority Block Height: $block_lag blocks"
                send_email "$subject" "$body"
                log_message "Node Lag Behind Majority Block Height: $block_lag blocks"
            fi
        else
            log_message "Invalid block height values for comparison: mbh=$mbh, local_height=$local_height"
        fi
    fi

    # Read the current runtime data
    local offline_check_count=$(jq -r '.offline_check_count' "$RUNTIME_FILE")
    local previous_node_online=$(jq -r '.previous_node_online' "$RUNTIME_FILE")
    local sent_alert_count=$(jq -r '.sent_alert_count' "$RUNTIME_FILE")
    local online_start_time=$(jq -r '.online_start_time' "$RUNTIME_FILE")
    local offline_start_time=$(jq -r '.offline_start_time' "$RUNTIME_FILE")
    local consecutive_lag_checks=$(jq -r '.consecutive_lag_checks' "$RUNTIME_FILE")

    # Increment offline check count if node is offline
    if [ "$node_online" = "false" ]; then
        offline_check_count=$((offline_check_count + 1))
        log_message "Node Offline - Consecutive Offline Checks: $offline_check_count"
        jq --argjson count "$offline_check_count" '.offline_check_count = $count' "$RUNTIME_FILE" > "$RUNTIME_FILE.tmp" && mv "$RUNTIME_FILE.tmp" "$RUNTIME_FILE"
        
        # Update offline start time if transitioning to offline
        if [ "$previous_node_online" = "true" ]; then
            jq --arg time "$timestamp" '.offline_start_time = $time' "$RUNTIME_FILE" > "$RUNTIME_FILE.tmp" && mv "$RUNTIME_FILE.tmp" "$RUNTIME_FILE"
        fi

        # Reset LAG-related counters
        reset_lag_counters
    else
        # Reset offline check count if node is back online
        if [ "$previous_node_online" = "false" ]; then
            offline_check_count=0
            log_message "Node Online - Resetting Offline Checks Count"
        else
            offline_check_count=0
        fi
        jq --argjson count "$offline_check_count" '.offline_check_count = $count' "$RUNTIME_FILE" > "$RUNTIME_FILE.tmp" && mv "$RUNTIME_FILE.tmp" "$RUNTIME_FILE"
        
        # Send email if node has come back online
        if [ "$previous_node_online" = "false" ]; then
            # Reset sent alert count
            sent_alert_count=0
            jq --argjson count "$sent_alert_count" '.sent_alert_count = $count' "$RUNTIME_FILE" > "$RUNTIME_FILE.tmp" && mv "$RUNTIME_FILE.tmp" "$RUNTIME_FILE"
            
            # Calculate offline duration
            local offline_duration_seconds=$(( $(date +%s) - $(date -d "$offline_start_time" +%s) ))
            local offline_duration=$(printf '%d Days, %d Hours, %d Minutes' $((offline_duration_seconds/86400)) $(( (offline_duration_seconds%86400)/3600 )) $(( (offline_duration_seconds%3600)/60 )))
            
            local subject="Pocketnet Node Status - Node is back ONLINE"
            local body="Timestamp: $timestamp\nLocal Node Block Height: $local_height\nMajority Block Height: $mbh\nOn-Chain: $on_chain\nNode Online: $node_online\nPeer Count: $peer_count\nOffline Check Count: $offline_check_count\nOffline Duration: $offline_duration"
            send_email "$subject" "$body"
            log_message "Email Sent: $subject"
            
            # Log the human-readable offline duration
            log_message "Node was offline for $offline_duration"
            
            # Update online start time
            jq --arg time "$timestamp" '.online_start_time = $time' "$RUNTIME_FILE" > "$RUNTIME_FILE.tmp" && mv "$RUNTIME_FILE.tmp" "$RUNTIME_FILE"
        fi

        # Check if node's block height exceeds the majority lag threshold
        if [ "$local_height" != "unknown" ]; then
            if [[ "$local_height" =~ ^[0-9]+$ ]] && [[ "$mbh" =~ ^[0-9]+$ ]]; then
                local block_lag=$((mbh - local_height))
                if (( block_lag > MAJORITY_LAG_THRESH )); then
                    consecutive_lag_checks=$((consecutive_lag_checks + 1))
                    log_message "Node Lag Detected - Consecutive Lag Checks: $consecutive_lag_checks"
                    jq --argjson count "$consecutive_lag_checks" '.consecutive_lag_checks = $count' "$RUNTIME_FILE" > "$RUNTIME_FILE.tmp" && mv "$RUNTIME_FILE.tmp" "$RUNTIME_FILE"
                else
                    consecutive_lag_checks=0
                    jq --argjson count "$consecutive_lag_checks" '.consecutive_lag_checks = $count' "$RUNTIME_FILE" > "$RUNTIME_FILE.tmp" && mv "$RUNTIME_FILE.tmp" "$RUNTIME_FILE"
                fi
            else
                log_message "Invalid block height values for comparison: mbh=$mbh, local_height=$local_height"
            fi
        fi
    fi

    # Save the current node online status for the next run
    jq --argjson online "$node_online" '.previous_node_online = $online' "$RUNTIME_FILE" > "$RUNTIME_FILE.tmp" && mv "$RUNTIME_FILE.tmp" "$RUNTIME_FILE"

    # Send email if threshold is exceeded
    if [ "$offline_check_count" -ge "$THRESHOLD" ]; then
        if [ "$sent_alert_count" -lt "$MAX_ALERTS" ]; then
            local subject="Pocketnet Node Status - Node Online: $node_online / On-Chain: $on_chain"
            local body="Timestamp: $timestamp\nLocal Node Block Height: $local_height\nMajority Block Height: $mbh\nOn-Chain: $on_chain\nNode Online: $node_online\nPeer Count: $peer_count\nOffline Check Count: $offline_check_count"
            if [ "$sent_alert_count" -eq "$((MAX_ALERTS - 1))" ]; then
                body="$body\n\nAlert Limit Reached - No More Alerts Will Be Sent"
            fi
            send_email "$subject" "$body"
            log_message "Alert Sent - Current Alert Count: $sent_alert_count"
            sent_alert_count=$((sent_alert_count + 1))
            jq --argjson count "$sent_alert_count" '.sent_alert_count = $count' "$RUNTIME_FILE" > "$RUNTIME_FILE.tmp" && mv "$RUNTIME_FILE.tmp" "$RUNTIME_FILE"
        fi
    fi
}

# Run the main function
main