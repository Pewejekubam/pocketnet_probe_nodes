#!/bin/bash

# Function to get address groupings and capture the wallet address with the highest balance
get_highest_balance_address() {
    pocketcoin-cli listaddressgroupings | jq -r '.[0] | max_by(.[1]) | .[0]'
}

# Function to get wallet info
get_wallet_info() {
    pocketcoin-cli getwalletinfo | jq -r '.sql_balance'
}

# Function to get general info
get_general_info() {
    pocketcoin-cli -getinfo | jq -r '"Version: \(.version) | Connections: \(.connections.total)"'
}

# Function to get block and difficulty info
get_block_difficulty_info() {
    pocketcoin-cli -getinfo | jq -r '"Blocks: \(.blocks) | Difficulty: \(.difficulty)"'
}

# Function to get staking info
get_staking_info() {
    pocketcoin-cli getstakinginfo | jq -r '"Expectedtime: \(.expectedtime) | Netstakeweight: \(.netstakeweight)"'
}

# Function to get staking status
get_staking_status() {
    pocketcoin-cli getstakinginfo | grep "staking" | grep "false"
}

# Function to get stake time
get_stake_time() {
    pocketcoin-cli getstakinginfo | jq -r '.["stake-time"]'
}

# Function to get last stake reward time
get_last_stake_reward() {
    pocketcoin-cli getstakereport | grep "Last stake time" | awk -F': ' '{print $2}'
}

# Function to get stake report
get_stake_report() {
    pocketcoin-cli getstakereport | head -n 7 | tail -n +2
}

# Function to get memory usage
get_memory_usage() {
    free -h
}

# Function to get debug log
get_debug_log() {
    tail -n 10 ~/.pocketcoin/debug.log
}

# Function to display metrics
display_metrics() {
    tput civis # Hide the cursor trap 'tput cnorm; exit' INT TERM # Show the cursor on exit
    printf "%-32s\n" "$(date +"%a %Y-%m-%d %H:%M:%S %Z")"
    printf "%-32s\n" "Wallet Address: $(get_highest_balance_address)"
    printf "%-32s | %-32s | %-32s\n" "Wallet Balance: $(get_wallet_info)" "Version: $(pocketcoin-cli -getinfo | jq -r '.version')" "Connections: $(pocketcoin-cli -getinfo | jq -r '.connections.total')"
    printf "%-32s | %-32s | %-32s\n" "Blocks: $(pocketcoin-cli -getinfo | jq -r '.blocks')" "Difficulty: $(pocketcoin-cli -getinfo | jq -r '.difficulty')" "Stake Time: $(get_stake_time)"
    printf "%-32s | %-32s\n" "Netstakeweight: $(pocketcoin-cli getstakinginfo | jq -r '.netstakeweight')" "Expectedtime: $(pocketcoin-cli getstakinginfo | jq -r '.expectedtime')"
    if [ "$(get_staking_status)" ]; then
        printf "%-32s\n" "Staking Status: false"
    fi
    printf "%-32s\n" "Staking Report:"
    get_stake_report
    printf "%-32s\n" "Local Memory Usage:"
    get_memory_usage
    get_debug_log
}

# Main loop
clear
counter=0
while true; do
    tput cup 0 0
    display_metrics
    sleep 5
    counter=$((counter + 1))
    if [ $counter -eq 15 ]; then
        clear
        counter=0
    fi
done
