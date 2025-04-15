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

# Function to get a configuration value from the JSON file
# Arguments:
#   $1 - The key to retrieve from the configuration file.
# Returns:
#   The value associated with the key.
get_config_value() {
    local key=$1
    jq -r ".${key}" "$CONFIG_FILE"
}

# Read configuration parameters from JSON file
CONFIG_DIR=$(get_config_value "CONFIG_DIR")
LOG_FILE="$CONFIG_DIR/probe_nodes.log"

# Function to log messages
# Logs a message with a timestamp to both the console and the log file.
# Arguments:
#   $1 - The message to log.
log_message() {
    local message=$1
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $message" | tee -a "$LOG_FILE"
}

# Continue with the rest of the configuration
RUNTIME_FILE="$CONFIG_DIR/probe_nodes_runtime.json"
SEED_NODES_URL=$(get_config_value "SEED_NODES_URL")
MAX_ALERTS=$(get_config_value "MAX_ALERTS")
THRESHOLD=$(get_config_value "THRESHOLD")
POCKETCOIN_CLI_ARGS=$(get_config_value "POCKETCOIN_CLI_ARGS")
SMTP_HOST=$(get_config_value "SMTP_HOST")
SMTP_PORT=$(get_config_value "SMTP_PORT")
RECIPIENT_EMAIL=$(get_config_value "RECIPIENT_EMAIL")
MSMTP_FROM=$(get_config_value "MSMTP_FROM")
MSMTP_USER=$(get_config_value "MSMTP_USER")
MSMTP_PASSWORD=$(get_config_value "MSMTP_PASSWORD")
MSMTP_TLS=$(get_config_value "MSMTP_TLS")
MSMTP_AUTH=$(get_config_value "MSMTP_AUTH")
EMAIL_TESTING=$(get_config_value "EMAIL_TESTING")
MAJORITY_LAG_THRESH=$(get_config_value "MAJORITY_LAG_THRESH")

# Ensure the runtime file exists
if [ ! -f "$RUNTIME_FILE" ]; then
    echo '{"comment": "This file is used exclusively by the script and should not be edited manually.", "offline_check_count": 0, "previous_node_online": true, "sent_alert_count": 0, "online_start_time": "", "offline_start_time": "", "consecutive_lag_checks": 0}' > "$RUNTIME_FILE"
fi

# Function to validate JSON keys
# Arguments:
#   $1 - The key to check in the configuration file.
validate_config_key() {
    local key=$1
    if ! jq -e ". | has(\"$key\")" "$CONFIG_FILE" > /dev/null; then
        log_message "Missing required parameter in configuration file: $key"
        exit 1
    fi
}

# Check required parameters
validate_config_key "CONFIG_DIR"
validate_config_key "SEED_NODES_URL"
validate_config_key "MAX_ALERTS"
validate_config_key "THRESHOLD"
validate_config_key "POCKETCOIN_CLI_ARGS"
validate_config_key "SMTP_HOST"
validate_config_key "SMTP_PORT"
validate_config_key "RECIPIENT_EMAIL"
validate_config_key "MSMTP_FROM"
validate_config_key "MAJORITY_LAG_THRESH"

# Create the necessary directories if they don't exist
mkdir -p "$CONFIG_DIR"

# Function to get the seed IP addresses
# Fetches a list of seed node IPs from the SEED_NODES_URL.
# Returns:
#   A list of IP addresses.
get_seed_ips() {
    curl -s $SEED_NODES_URL | grep -oP '^[^:]+' 
}

# Function to get block height and version from a node with a timeout of 1 second
# Queries a node for its block height and version with a timeout of 1 second.
# Arguments:
#   $1 - The IP address of the node.
# Returns:
#   The block height and version, or "unreachable" if the node is not reachable.
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

# Embedded JSON for subject line templates
SUBJECT_TEMPLATES=$(cat <<EOF
{
    "offline": "OFFLINE | Peers: {peer_count}",
    "online": "ONLINE | Synced, Peers: {peer_count}",
    "lag": "LAG | {block_lag} blocks behind MBH",
    "seed_failure": "ALERT | No seed nodes found",
    "threshold": "THRESHOLD | Offline checks: {offline_check_count}"
}
EOF
)

# Function to get subject line from template
# Generates an email subject line based on a template and variable substitutions.
# Arguments:
#   $1 - The template key (e.g., "offline", "online").
#   $2+ - Key-value pairs for variable substitutions (e.g., "peer_count=5").
# Returns:
#   The generated subject line.
get_subject_line() {
    local template_key=$1
    local template=$(echo "$SUBJECT_TEMPLATES" | jq -r ".${template_key}")
    shift
    for var in "$@"; do
        local key=$(echo "$var" | cut -d= -f1)
        local value=$(echo "$var" | cut -d= -f2-)
        template=${template//\{$key\}/$value}
    done
    echo "$template"
}

# Centralized function to send emails
# Sends an email with the specified subject and body using msmtp.
# Arguments:
#   $1 - The subject of the email.
#   $2 - The body of the email.
send_email() {
    local subject=$1
    local body=$2
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

# Centralized function to handle email notifications
# Sends an email notification with a given subject and body.
# Arguments:
#   $1 - The type of notification (e.g., "offline", "online").
#   $2 - The body of the email.
#   $3+ - Key-value pairs for subject line substitutions.
send_notification() {
    local type=$1
    shift
    local body=$1
    shift
    local subject=$(get_subject_line "$type" "$@")
    if [ -z "$subject" ] || [ -z "$body" ]; then
        log_message "Error: Missing subject or body for email notification of type '$type'."
        return 1
    fi
    send_email "$subject" "$body"
    log_message "Email Sent: $subject"
}

# Function to detect state changes
detect_state_change() {
    local current_state=$1
    local previous_state=$2
    if [ "$current_state" != "$previous_state" ]; then
        echo "true"
    else
        echo "false"
    fi
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

state_reset() {
    local key=$1
    jq ".${key} = 0" "$RUNTIME_FILE" > "$RUNTIME_FILE.tmp" && mv "$RUNTIME_FILE.tmp" "$RUNTIME_FILE"
}

# Email Notification Module
send_email_notification() {
    local type=$1
    local body=$2
    local subject=$(get_subject_line "$type" "$@")
    if [ -z "$subject" ] || [ -z "$body" ]; then
        log_message "Error: Missing subject or body for email notification of type '$type'."
        return 1
    fi
    _send_email "$subject" "$body"
    log_message "Email Sent: $subject"
}

# Private helper function for sending emails
_send_email() {
    local subject=$1
    local body=$2
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

# Node Monitoring Module
check_node_status() {
    local node_ip=$1
    local node_info=$(get_node_info "$node_ip")
    if [[ "$node_info" != "unreachable" ]]; then
        local block_height=$(echo "$node_info" | awk '{print $1}')
        local version=$(echo "$node_info" | awk '{print $2}')
        echo "$block_height $version"
    else
        echo "unreachable"
    fi
}

update_node_frequencies() {
    local origin=$1
    shift
    local -n freq_map=$1
    shift
    local node_ips=("$@")
    for node_ip in "${node_ips[@]}"; do
        local node_info=$(check_node_status "$node_ip")
        if [[ "$node_info" != "unreachable" ]]; then
            local block_height=$(echo "$node_info" | awk '{print $1}')
            ((freq_map[$block_height]++))
        fi
    done
}

# Function to calculate duration in human-readable format
# Arguments:
#   $1 - Start timestamp.
#   $2 - End timestamp.
# Returns:
#   Duration in "X Days, Y Hours, Z Minutes" format.
calculate_duration() {
    local start_time=$1
    local end_time=$2
    local duration_seconds=$((end_time - start_time))
    printf '%d Days, %d Hours, %d Minutes' \
        $((duration_seconds / 86400)) \
        $(((duration_seconds % 86400) / 3600)) \
        $(((duration_seconds % 3600) / 60))
}

# Function to check if a node's block height is lagging
# Arguments:
#   $1 - Local block height.
#   $2 - Majority block height.
#   $3 - Lag threshold.
# Returns:
#   "true" if lagging, "false" otherwise.
is_lagging() {
    local local_height=$1
    local mbh=$2
    local threshold=$3
    if [[ "$local_height" =~ ^[0-9]+$ ]] && [[ "$mbh" =~ ^[0-9]+$ ]]; then
        local block_lag=$((mbh - local_height))
        if ((block_lag > threshold)); then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
    fi
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
    local consecutive_lag_checks=$(state_read consecutive_lag_checks)

    # Normalize the previous_node_online value after reading it
    if [ "$previous_node_online" = "true" ]; then
        previous_node_online="true"
    else
        previous_node_online="false"
    fi

    # Increment offline check count if node is offline
    if [ "$node_online" = "false" ]; then
        offline_check_count=$((offline_check_count + 1))
        log_message "Node Offline - Consecutive Offline Checks: $offline_check_count"
        state_update offline_check_count "$offline_check_count"

        # Update offline start time if transitioning to offline
        if [ "$previous_node_online" = "true" ]; then
            state_update offline_start_time "\"$timestamp\""

            # Send email notification for online-to-offline transition
            send_notification "offline" \
                "Timestamp: $timestamp\nLocal Node Block Height: $local_height\nMajority Block Height: $mbh\nOn-Chain: $on_chain\nNode Online: $node_online\nPeer Count: $peer_count\nOffline Check Count: $offline_check_count" \
                "peer_count=$peer_count"
        fi

        # Reset LAG-related counters
        state_reset consecutive_lag_checks
    else
        # Reset offline check count if node is back online
        if [ "$previous_node_online" = "false" ]; then
            offline_check_count=0
            log_message "Node Online - Resetting Offline Checks Count"
        else
            offline_check_count=0
        fi
        state_update offline_check_count "$offline_check_count"

        # Send email if node has come back online
        if [ "$previous_node_online" = "false" ]; then
            # Reset sent alert count
            sent_alert_count=0
            state_update sent_alert_count "$sent_alert_count"

            # Calculate offline duration
            local offline_duration=$(calculate_duration "$(date -d "$offline_start_time" +%s)" "$(date +%s)")

            send_notification "online" \
                "Timestamp: $timestamp\nLocal Node Block Height: $local_height\nMajority Block Height: $mbh\nOn-Chain: $on_chain\nNode Online: $node_online\nPeer Count: $peer_count\nOffline Duration: $offline_duration" \
                "peer_count=$peer_count"

            # Log the human-readable offline duration
            log_message "Node was offline for $offline_duration"

            # Update online start time
            state_update online_start_time "\"$timestamp\""
        fi

        # Check if node's block height exceeds the majority lag threshold
        if [ "$local_height" != "unknown" ]; then
            if [[ "$local_height" =~ ^[0-9]+$ ]] && [[ "$mbh" =~ ^[0-9]+$ ]]; then
                if [ "$(is_lagging "$local_height" "$mbh" "$MAJORITY_LAG_THRESH")" = "true" ]; then
                    consecutive_lag_checks=$((consecutive_lag_checks + 1))
                    log_message "Node Lag Detected - Consecutive Lag Checks: $consecutive_lag_checks"
                    state_update consecutive_lag_checks "$consecutive_lag_checks"
                else
                    consecutive_lag_checks=0
                    state_reset consecutive_lag_checks
                fi
            else
                log_message "Invalid block height values for comparison: mbh=$mbh, local_height=$local_height"
            fi
        fi
    fi

    # Save the current node online status for the next run
    if [ "$node_online" = "true" ]; then
        state_update previous_node_online true
    else
        state_update previous_node_online false
    fi

    # Send email if threshold is exceeded
    if [ "$offline_check_count" -ge "$THRESHOLD" ]; then
        if [ "$sent_alert_count" -lt "$MAX_ALERTS" ]; then
            send_notification "threshold" \
                "Timestamp: $timestamp\nLocal Node Block Height: $local_height\nMajority Block Height: $mbh\nOn-Chain: $on_chain\nNode Online: $node_online\nPeer Count: $peer_count\nOffline Check Count: $offline_check_count" \
                "offline_check_count=$offline_check_count"
            sent_alert_count=$((sent_alert_count + 1))
            state_update sent_alert_count "$sent_alert_count"
        fi
    fi

    # Detect state changes
    local state_changed=$(detect_state_change "$node_online" "$previous_node_online")

    # Handle state change notifications
    if [ "$state_changed" = "true" ]; then
        if [ "$node_online" = "false" ]; then
            send_notification "offline" \
                "Timestamp: $timestamp\nLocal Node Block Height: $local_height\nMajority Block Height: $mbh\nOn-Chain: $on_chain\nNode Online: $node_online\nPeer Count: $peer_count\nOffline Check Count: $offline_check_count" \
                "peer_count=$peer_count"
        elif [ "$node_online" = "true" ]; then
            local offline_duration=$(calculate_duration "$(date -d "$offline_start_time" +%s)" "$(date +%s)")
            send_notification "online" \
                "Timestamp: $timestamp\nLocal Node Block Height: $local_height\nMajority Block Height: $mbh\nOn-Chain: $on_chain\nNode Online: $node_online\nPeer Count: $peer_count\nOffline Duration: $offline_duration" \
                "peer_count=$peer_count"
        fi
    fi

    # Handle lag detection
    if [ "$node_online" = "true" ] && (( block_lag > MAJORITY_LAG_THRESH )); then
        send_notification "lag" \
            "Timestamp: $timestamp\nLocal Node Block Height: $local_height\nMajority Block Height: $mbh\nOn-Chain: $on_chain\nNode Online: $node_online\nPeer Count: $peer_count\nNode Lag Behind Majority Block Height: $block_lag blocks" \
            "block_lag=$block_lag"
    fi

    # Handle seed node retrieval failure
    if [ ${#seed_node_ips[@]} -eq 0 ]; then
        send_notification "seed_failure" \
            "Timestamp: $timestamp\nNo seed nodes retrieved. The seed IPs array is empty."
    fi

    # Handle threshold exceeded
    if [ "$offline_check_count" -ge "$THRESHOLD" ] && [ "$sent_alert_count" -lt "$MAX_ALERTS" ]; then
        send_notification "threshold" \
            "Timestamp: $timestamp\nLocal Node Block Height: $local_height\nMajority Block Height: $mbh\nOn-Chain: $on_chain\nNode Online: $node_online\nPeer Count: $peer_count\nOffline Check Count: $offline_check_count" \
            "offline_check_count=$offline_check_count"
    fi
}

# Run the main function
main