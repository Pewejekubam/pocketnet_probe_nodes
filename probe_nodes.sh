#!/bin/bash
## 20250415160409CDT
## v0.6.7
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

# Function to get a configuration value from the JSON file
# Arguments:
#   $1 - The key to retrieve from the configuration file.
# Returns:
#   The value associated with the key.
get_config_value() {
    local key=$1
    local value
    value=$(jq -r ".${key}" "$CONFIG_FILE")
    if [ "$value" == "null" ]; then
        log_message "Error: Missing required parameter in configuration file: $key"
        exit 1
    fi
    echo "$value"
}

# Read configuration parameters from JSON file
CONFIG_DIR=$(get_config_value "CONFIG_DIR")
LOG_FILE="$CONFIG_DIR/probe_nodes.log"
RUNTIME_FILE="$CONFIG_DIR/probe_nodes_runtime.json"
SEED_NODES_URL=$(get_config_value "SEED_NODES_URL")
MAX_ALERTS=$(get_config_value "MAX_ALERTS")
THRESHOLD=$(get_config_value "THRESHOLD")
POCKETCOIN_CLI_ARGS=$(get_config_value "POCKETCOIN_CLI_ARGS")
RECIPIENT_EMAIL=$(get_config_value "RECIPIENT_EMAIL")
EMAIL_TESTING=$(get_config_value "EMAIL_TESTING")
MAJORITY_LAG_THRESH=$(get_config_value "MAJORITY_LAG_THRESH")

# Function to log messages
# Logs a message with a timestamp to both the console and the log file.
# Arguments:
#   $1 - The message to log.
log_message() {
    local message=$1
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $message" | tee -a "$LOG_FILE"
}

# Ensure the runtime file exists
if [ ! -f "$RUNTIME_FILE" ]; then
    echo '{"comment": "This file is used exclusively by the script and should not be edited manually.", "offline_check_count": 0, "previous_node_online": true, "sent_alert_count": 0, "online_start_time": "", "offline_start_time": ""}' > "$RUNTIME_FILE"
fi

# Function to validate required configuration keys
# Arguments:
#   $1 - An array of required keys.
validate_config_keys() {
    local -n keys=$1
    for key in "${keys[@]}"; do
        local value
        value=$(jq -e ".${key}" "$CONFIG_FILE" 2>/dev/null)
        if [ "$value" == "null" ] || [ -z "$value" ]; then
            log_message "Missing required parameter in configuration file: $key"
            exit 1
        fi
    done
}

# Validate required configuration keys
required_keys=("CONFIG_DIR" "SEED_NODES_URL" "MAX_ALERTS" "THRESHOLD" "POCKETCOIN_CLI_ARGS" "RECIPIENT_EMAIL" "EMAIL_TESTING" "MAJORITY_LAG_THRESH")
validate_config_keys required_keys

# Create the necessary directories if they don't exist
mkdir -p "$CONFIG_DIR"

# Function to get the seed IP addresses
# Fetches a list of seed node IPs from the SEED_NODES_URL.
# Returns:
#   A list of IP addresses.
get_seed_ips() {
    curl -s $SEED_NODES_URL | grep -oP '^[^:]+' 
}

# Function to fetch block height and version from a node
# Handles both local and remote nodes.
# Arguments:
#   $1 - The IP address of the node.
# Returns:
#   The block height and version, or "unreachable" if the node is not reachable.
fetch_node_info() {
    local node_ip=$1
    local block_height=""
    local version=""
    local url="http://$node_ip:38081"

    if [[ "$node_ip" == "127.0.0.1" || "$node_ip" == "localhost" ]]; then
        # Attempt to fetch block height using pocketcoin-cli for local nodes
        if ! block_height=$(pocketcoin-cli $POCKETCOIN_CLI_ARGS getblockcount 2>/dev/null); then
            block_height="unknown"
        fi
    fi

    # Fallback to HTTP POST for local nodes or directly for remote nodes
    local response=$(curl -s --max-time 1 -X POST -H "Content-Type: application/json" -d '{"method": "getnodeinfo", "params": [], "id": ""}' $url 2>/dev/null)
    if [[ "$block_height" == "unknown" || -z "$block_height" ]]; then
        block_height=$(echo $response | jq -r '.result.lastblock.height' 2>/dev/null)
    fi
    version=$(echo $response | jq -r '.result.version' 2>/dev/null)

    if [[ -n "$block_height" && "$block_height" != "null" ]]; then
        echo "$block_height $version"
    else
        echo "unreachable"
    fi
}

# Function to update frequency map with block heights from nodes
# Updates a frequency map with block heights reported by a list of nodes.
# Arguments:
#   $1 - The origin of the nodes (e.g., "seed_node" or "locally_connected_node").
#   $2 - A reference to the frequency map (associative array).
#   $3+ - A list of node IP addresses.
update_frequency_map() {
    local origin=$1
    shift
    local -n freq_map=$1
    shift
    local node_ips=("$@")
    local log_messages=()
    for node_ip in "${node_ips[@]}"; do
        local node_info=$(fetch_node_info "$node_ip" "$origin")
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
# Determines the block height with the highest frequency in the frequency map.
# Arguments:
#   $1 - A reference to the frequency map (associative array).
# Returns:
#   The majority block height (MBH).
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

# Path to the msmtprc file
MSMTPRC_FILE="$HOME/.msmtprc"

# Function to validate the .msmtprc file
# Checks if the file exists and contains valid configurations.
validate_msmtprc() {
    if [ ! -f "$MSMTPRC_FILE" ]; then
        log_message "Warning: .msmtprc file not found. Running in log-only mode."
        return 1
    fi
    if ! grep -q "^account" "$MSMTPRC_FILE"; then
        log_message "Error: Invalid .msmtprc file. Missing 'account' configuration. Running in log-only mode."
        return 1
    fi
    return 0
}

# Validate the .msmtprc file
validate_msmtprc
EMAIL_ENABLED=$?

# Helper function to construct email subject and body
# Arguments:
#   $1 - The notification type (e.g., "offline", "online", etc.).
#   $2 - Context data (e.g., local_height, mbh, peer_count, etc.).
# Returns:
#   The subject and body as a string (separated by a newline).
construct_email_content() {
    local type=$1
    local context=$2
    local subject=""
    local body=""

    case "$type" in
        "offline")
            subject="OFFLINE | Offline checks: ${context[offline_check_count]}"
            body="Timestamp: ${context[timestamp]}\nLocal Node Block Height: ${context[local_height]}\nMajority Block Height: ${context[mbh]}\nOn-Chain: ${context[on_chain]}\nNode Online: ${context[node_online]}\nPeer Count: ${context[peer_count]}\nOffline Check Count: ${context[offline_check_count]}"
            ;;
        "online")
            subject="ONLINE | Synced, Peers: ${context[peer_count]}"
            body="Timestamp: ${context[timestamp]}\nLocal Node Block Height: ${context[local_height]}\nMajority Block Height: ${context[mbh]}\nOn-Chain: ${context[on_chain]}\nNode Online: ${context[node_online]}\nPeer Count: ${context[peer_count]}"
            ;;
        "test")
            subject="Test Email from Pocketnet Node"
            body="This is a test email from the Pocketnet node script.\n\nSMTP Host: $SMTP_HOST\nSMTP Port: $SMTP_PORT\nRecipient Email: $RECIPIENT_EMAIL\nFrom: $MSMTP_FROM\nUser: $MSMTP_USER\nTLS: $MSMTP_TLS\nAuth: $MSMTP_AUTH"
            ;;
        "seed_failure")
            subject="OFFLINE | No seed nodes found"
            body="No seed nodes retrieved. The seed IPs array is empty."
            ;;
        *)
            log_message "Error: Unknown notification type '$type'."
            return 1
            ;;
    esac

    echo -e "$subject\n$body"
}

# Function to send email notifications
# Dynamically construct subject lines based on the current state and context.
send_notification() {
    local type=$1
    declare -A context=("${!2}") # Pass context as an associative array
    local email_content
    email_content=$(construct_email_content "$type" context)
    local subject=$(echo "$email_content" | head -n 1)
    local body=$(echo "$email_content" | tail -n +2)

    if [ -z "$subject" ] || [ -z "$body" ]; then
        log_message "Error: Missing subject or body for email notification of type '$type'."
        return 1
    fi

    # Apply MAX_ALERTS logic to all offline notifications
    if [ "$type" = "offline" ] && [ "${context[sent_alert_count]}" -ge "$MAX_ALERTS" ]; then
        log_message "Max alerts reached for offline notifications. No email sent."
        return 0
    fi

    send_email "$subject" "$body"
    log_message "Email Sent: $subject"

    # Increment sent_alert_count for offline notifications
    if [ "$type" = "offline" ]; then
        local new_sent_alert_count=$((context[sent_alert_count] + 1))
        state_update sent_alert_count "$new_sent_alert_count"
    fi
}

# Centralized function to send emails
# Sends an email with the specified subject and body using msmtp.
# Arguments:
#   $1 - The subject of the email.
#   $2 - The body of the email.
send_email() {
    if [ "$EMAIL_ENABLED" -ne 0 ]; then
        log_message "Email not sent. Running in log-only mode."
        return 0
    fi

    local subject=$1
    local body=$2
    # Extract the 'from' address from the .msmtprc file
    local from_address
    from_address=$(grep -m 1 "^from[[:space:]]" "$MSMTPRC_FILE" | awk '{print $2}')
    if [ -z "$from_address" ]; then
        log_message "Error: Unable to extract 'from' address from .msmtprc. Email not sent."
        return 1
    fi
    # Construct the email with an explicit 'From:' header
    echo -e "From: $from_address\nTo: $RECIPIENT_EMAIL\nSubject: $subject\n\n$body" | msmtp --logfile=/dev/stdout "$RECIPIENT_EMAIL"
}

# State Management Module
state_read() {
    local key=$1
    jq -r ".${key}" "$RUNTIME_FILE"
}

state_update() {
    local key=$1
    local value=$2
    jq --argjson val "$value" ".${key} = \$val" "$RUNTIME_FILE" > "$RUNTIME_FILE.tmp" && mv "$RUNTIME_FILE.tmp" "$RUNTIME_FILE"
}

# Main function to run the script
main() {
    # Check if email testing is enabled
    if [ "$EMAIL_TESTING" = "true" ]; then
        local subject="Test Email from Pocketnet Node"
        local body="This is a test email from the Pocketnet node script.\n\nSMTP Host: $SMTP_HOST\nSMTP Port: $SMTP_PORT\nRecipient Email: $RECIPIENT_EMAIL\nFrom: $MSMTP_FROM\nUser: $MSMTP_USER\nTLS: $MSMTP_TLS\nAuth: $MSMTP_AUTH"
        log_message "EMAIL_TESTING is enabled. A test email will be sent with the following parameters:\nSubject: $subject\nBody:\n$body\n"
        send_notification "test" "$body"
        exit 0
    fi

    # Get seed IP addresses
    seed_node_ips=($(get_seed_ips))

    # Check if the seed IPs array is empty
    if [ ${#seed_node_ips[@]} -eq 0 ]; then
        # Log the message
        log_message "No seed nodes retrieved. The seed IPs array is empty."

        # Notify the user via email
        send_notification "seed_failure" "No seed nodes retrieved. The seed IPs array is empty."
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

    # Fetch local node information
    local local_node_info=$(fetch_node_info "localhost")
    local local_height=$(echo "$local_node_info" | awk '{print $1}')
    local node_online="true"
    if [[ "$local_node_info" == "unreachable" ]]; then
        node_online="false"
        local_height="unknown"
    fi

    # Log local node information
    log_message "ip: localhost block_height: $local_height"

    # Fetch remote node information
    seed_node_ips=($(get_seed_ips))
    for node_ip in "${seed_node_ips[@]}"; do
        local remote_node_info=$(fetch_node_info "$node_ip")
        log_message "ip: $node_ip info: $remote_node_info"
    done

    # Get peer count
    local peer_count=$(echo "$peer_info" | jq -r 'length')

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

    # Read runtime variables using state_read
    local offline_check_count=$(state_read offline_check_count)
    local previous_node_online=$(state_read previous_node_online)
    local sent_alert_count=$(state_read sent_alert_count)
    local online_start_time=$(state_read online_start_time)
    local offline_start_time=$(state_read offline_start_time)

    # Normalize the previous_node_online value after reading it
    if [ "$previous_node_online" = "true" ]; then
        previous_node_online="true"
    else
        previous_node_online="false"
    fi

    # Handle state change notifications
    if [ "$previous_node_online" != "$node_online" ]; then
        if [ "$node_online" = "false" ]; then
            # Transition to offline
            offline_check_count=$((offline_check_count + 1))
            state_update offline_check_count "$offline_check_count"
            state_update offline_start_time "\"$timestamp\""

            declare -A context=(
                [timestamp]="$timestamp"
                [local_height]="$local_height"
                [mbh]="$mbh"
                [on_chain]="$on_chain"
                [node_online]="$node_online"
                [peer_count]="$peer_count"
                [offline_check_count]="$offline_check_count"
                [sent_alert_count]="$sent_alert_count"
            )
            send_notification "offline" context[@]
        elif [ "$node_online" = "true" ]; then
            # Transition to online
            offline_check_count=0
            state_update offline_check_count "$offline_check_count"
            state_update online_start_time "\"$timestamp\""

            declare -A context=(
                [timestamp]="$timestamp"
                [local_height]="$local_height"
                [mbh]="$mbh"
                [on_chain]="$on_chain"
                [node_online]="$node_online"
                [peer_count]="$peer_count"
                [offline_check_count]="$offline_check_count"
                [sent_alert_count]="$sent_alert_count"
            )
            send_notification "online" context[@]

            # Reset sent_alert_count when transitioning back online
            sent_alert_count=0
            state_update sent_alert_count "$sent_alert_count"
        fi
    fi

    # Handle offline notifications when no state change occurs
    if [ "$previous_node_online" = "false" ] && [ "$node_online" = "false" ]; then
        offline_check_count=$((offline_check_count + 1))
        state_update offline_check_count "$offline_check_count"

        declare -A context=(
            [timestamp]="$timestamp"
            [local_height]="$local_height"
            [mbh]="$mbh"
            [on_chain]="$on_chain"
            [node_online]="$node_online"
            [peer_count]="$peer_count"
            [offline_check_count]="$offline_check_count"
            [sent_alert_count]="$sent_alert_count"
        )
        send_notification "offline" context[@]
    fi

    # Validate critical data before sending notifications
    if [ -z "$local_height" ] || [ -z "$mbh" ] || [ -z "$peer_count" ]; then
        log_message "Error: Missing critical data (local_height, mbh, or peer_count). Skipping notifications."
        exit 1
    fi

    # Standardize log messages
    log_message "State Change Detected: $previous_node_online -> $node_online"
    log_message "Offline Check Count: $offline_check_count"
    log_message "Sent Alert Count: $sent_alert_count"

    # Handle threshold exceeded (only if no state change occurred)
    if [ "$previous_node_online" = "false" ] && [ "$offline_check_count" -ge "$THRESHOLD" ]; then
        if [ "$sent_alert_count" -lt "$MAX_ALERTS" ]; then
            declare -A context=(
                [timestamp]="$timestamp"
                [local_height]="$local_height"
                [mbh]="$mbh"
                [on_chain]="$on_chain"
                [node_online]="$node_online"
                [peer_count]="$peer_count"
                [offline_check_count]="$offline_check_count"
                [sent_alert_count]="$sent_alert_count"
            )
            send_notification "threshold" context[@]
            sent_alert_count=$((sent_alert_count + 1))
            state_update sent_alert_count "$sent_alert_count"
        fi
    fi

    # Save the current node online status for the next run
    state_update previous_node_online "$node_online"
}

# Run the main function
main