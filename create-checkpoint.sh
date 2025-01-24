#!/bin/bash

# User Editable Configuration Parameters
# Set to true for interactive execution, false for non-interactive execution
interactive_execution=false
# Set to true for testing mode, false for normal execution
testing_mode=true
# Repository server with locally connected bulk storage
repository_server=biz-san21
# Local process root directory
local_process_root=/mnt/EXTHDD6/
# Source node IP address or hostname
source_node=192.168.12.36
# Source node user
source_node_user=pocketnet
# Path to the private key for SSH connection
private_key=/home/sysadmin/.ssh/id_ecdsa_square
# Pocketnet node root directory
pocketnet_node_root=/home/pocketnet/

# Non-User Editable Configuration Parameters
absolute_pocketnet_node_root="${pocketnet_node_root}.pocketcoin"
remote_log_dir="${pocketnet_node_root}pocketnet_snapshot"
local_working_directory="${local_process_root}pocketnet_snapshot"

# Function to log messages
log_message() {
    local message="$1"
    local log_file="${local_working_directory}/create-checkpoint.log"
    mkdir -p "$(dirname "$log_file")"  # Create the directory if it doesn't exist
    if [ "$interactive_execution" = true ]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') - $message" | tee -a "$log_file"
    else
        echo "$(date +'%Y-%m-%d %H:%M:%S') - $message" >> "$log_file"
    fi
}

# Function to execute remote commands in the background
execute_remote_command() {
    local command="$1"
    local remote_output="$remote_log_dir/remote_command_output"
    local remote_checksum="$remote_log_dir/remote_command_output_checksum"

    # Ensure the remote log directory exists
    ssh -i "$private_key" "$source_node_user@$source_node" "mkdir -p $remote_log_dir"

    log_message "Executing remote command: $command"
    ssh -i "$private_key" "$source_node_user@$source_node" "$command > $remote_output 2>&1"
    log_message "Remote Command Executed: $command"

    # Calculate checksum on the remote host
    ssh -i "$private_key" "$source_node_user@$source_node" "sha256sum $remote_output > $remote_checksum"
    remote_checksum_value=$(ssh -i "$private_key" "$source_node_user@$source_node" "awk '{print \$1}' $remote_checksum")
    log_message "Remote Original Command Capture File Checksum Value: $remote_checksum_value"

    # Ensure the local directory exists
    mkdir -p "$local_working_directory"

    # Retrieve remote command output and checksum
    log_message "Retrieving remote command capture file and checksum"
    scp -i "$private_key" "$source_node_user@$source_node:$remote_output" "${local_working_directory}/remote_command_output"
    scp -i "$private_key" "$source_node_user@$source_node:$remote_checksum" "${local_working_directory}/remote_command_output_checksum"
    log_message "Remote command capture file and checksum retrieved"

    # Calculate checksum on the local host of the copied command output file
    local local_checksum_value=$(sha256sum $local_working_directory/remote_command_output | awk '{ print $1 }')
    local remote_checksum_value=$(awk '{ print $1 }' $local_working_directory/remote_command_output_checksum)
    log_message "Local Copy of Command Capture File Checksum Value: $local_checksum_value"

    # Compare checksums
    if [ "$local_checksum_value" != "$remote_checksum_value" ]; then
        log_message "Checksum verification failed. The file may be corrupted."
        exit 1
    else
        log_message "Checksum verification succeeded. The file was copied intact."
    fi

    if [ ! -f $local_working_directory/remote_command_output ]; then
        log_message "Failed to retrieve remote command output."
        exit 1
    fi

}

# Function to clean up remote host
cleanup_remote_host() {
	ssh -i "$private_key" "$source_node_user@$source_node" "rm -rf $remote_log_dir"
}


# Begin Script
clear
# Clean up log file from the last run
rm ${local_working_directory}/create-checkpoint.log

log_message "Starting script execution."
log_message "Interactive Execution: $interactive_execution"
log_message "Testing Mode: $testing_mode"

if [ "$interactive_execution" = true ]; then
    log_message "Press Enter to continue..."
    read -r
fi

# Download and extract the latest 7zip compression program
log_message "Downloading the latest 7zip compression program..."
wget -q -P "$local_working_directory" https://github.com/ip7z/7zip/releases/download/24.09/7z2409-linux-x64.tar.xz

# Validate the download
log_message "Validating the download..."
downloaded_file="$local_working_directory/7z2409-linux-x64.tar.xz"
expected_size=1565344
actual_size=$(stat -c%s "$downloaded_file")
if [ "$actual_size" -ne "$expected_size" ]; then
    log_message "Download validation failed. Expected size: $expected_size, Actual size: $actual_size"
    if [ "$interactive_execution" = true ]; then
        log_message "Press Enter to continue or stop execution to investigate manually..."
        read -r
    else
        exit 1
    fi
fi

log_message "Extracting the '7zzs' file from the archive..."
tar -xvf "$downloaded_file" -C "$local_working_directory" --wildcards --no-anchored '7zzs'
log_message "Deleting the source archive..."
rm "$downloaded_file"
log_message "Setting the file mode for '7zzs' to executable..."
chmod +x "$local_working_directory/7zzs"

log_message "Initial setup completed."

# Get Node Daemon Version
log_message "Getting the Pocketnet daemon version on the source node..."

# Execute the remote command to get node info
execute_remote_command "pocketcoin-cli -getinfo"

# Retrieve the command output file locally
output_file="${local_working_directory}/remote_command_output"

# Parse the JSON output to get the version
if [ -f "$output_file" ]; then
	node_info=$(cat "$output_file")
	node_version=$(echo "$node_info" | grep -oP '"version": \K\d+')
	log_message "Node daemon version: $node_version"
else
	log_message "Failed to retrieve node daemon version. Command output file not found."
	exit 1
fi

# Shutdown Node
log_message "Shutting down the Pocketnet daemon on the source node..."
execute_remote_command "pocketcoin-cli stop"

# Wait for graceful shutdown
log_message "Waiting for graceful shutdown..."
shutdown_complete=false
current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
log_message "Current Time: $current_time"
for i in {1..40}; do
    log_message "Checking for 'Shutdown: In progress...' entry in $local_working_directory/remote_command_output"
    
    # Poll the latest contents of the 'debug.log' file using execute_remote_command
    execute_remote_command "tail -n 50 /home/pocketnet/.pocketcoin/debug.log"
    
    in_progress_entry=$(tac $local_working_directory/remote_command_output | grep 'Shutdown: In progress...' | head -n 1)
    log_message "In Progress Entry: $in_progress_entry"
    if [ -n "$in_progress_entry" ]; then
        in_progress_time=$(echo "$in_progress_entry" | awk '{print $1}')
        log_message "In Progress Time: $in_progress_time"
        log_message "Checking for 'Shutdown: done' entry in $local_working_directory/remote_command_output"
        done_entry=$(tac $local_working_directory/remote_command_output | grep 'Shutdown: done' | head -n 1)
        log_message "Done Entry: $done_entry"
        if [ -n "$done_entry" ]; then
            done_time=$(echo "$done_entry" | awk '{print $1}')
            log_message "Done Time: $done_time"
            if [[ "$done_time" > "$in_progress_time" ]]; then
                log_message "Shutdown complete."
                shutdown_complete=true
                break
            fi
        fi
    fi
    log_message "Shutdown not complete, checking again in 15 seconds..."
    sleep 15
done

if [ "$shutdown_complete" = true ]; then
    log_message "Node shutdown gracefully."
else
    log_message "Node did not shutdown gracefully within the expected time."
    exit 1
fi

# Capture Block Height and Block Hash from debug.log
log_message "Capturing Block Height and Block Hash from debug.log"

# Find the very last entry in the 'remote_command_output' file
last_bh_entry=$(tac $local_working_directory/remote_command_output | grep 'BestHeader:' | head -n 1)

# Extract Block Height
block_height=$(echo "$last_bh_entry" | awk -F'BestHeader: ' '{print $2}' | awk '{print $1}')
log_message "Block Height: $block_height"

# Extract Block Hash
block_hash=$(echo "$last_bh_entry" | awk -F'BestHeader: ' '{print $2}' | awk '{print $2}')
log_message "Block Hash: $block_hash"

# Copy from Remote Node to Local Compression Host and Create the Archive
if [ "$testing_mode" = true ]; then
    log_message "Testing mode enabled. Skipping rsync functions and creating empty directory structure."
    mkdir -p "$local_working_directory/snapshot/blocks"
    mkdir -p "$local_working_directory/snapshot/indexes"
    mkdir -p "$local_working_directory/snapshot/pocketdb"
else
    log_message "Copying data from the remote node to the local compression host..."
    rsync -avz --delete --progress -e "ssh -i $private_key" "$source_node_user@$source_node:$absolute_pocketnet_node_root/blocks" "$local_working_directory/snapshot/"
    rsync -avz --delete --progress -e "ssh -i $private_key" "$source_node_user@$source_node:$absolute_pocketnet_node_root/indexes" "$local_working_directory/snapshot/"
    rsync -avz --delete --progress -e "ssh -i $private_key" "$source_node_user@$source_node:$absolute_pocketnet_node_root/pocketdb" "$local_working_directory/snapshot/"
fi

# Test volume of captured data
log_message "Testing the volume of captured data..."
data_volume_bytes=$(du -sb "$local_working_directory/snapshot" | cut -f1)
log_message "Captured Data Volume: $data_volume_bytes bytes"
data_volume_gb=$(awk "BEGIN {printf \"%.0f\", $data_volume_bytes / 1024 / 1024 / 1024}")
if [ "$testing_mode" = false ] && [ "$data_volume_bytes" -lt 100 ]; then
    log_message "Captured volume is suspect invalid due to unexpected volume of data."
    if [ "$interactive_execution" = true ]; then
        log_message "Press Enter to continue to the COMPRESSION phase or stop execution to investigate manually..."
        read -r
    fi
fi

# Start the pocketcoind Daemon on the Remote Node
log_message "Starting the pocketcoind daemon on the remote node..."
execute_remote_command "pocketcoind -daemon"

# Compress the Archive
log_message "Compressing the archive..."
cd "$local_working_directory/snapshot"
archive_name="snapshot-$block_height.7z"
"$local_working_directory/7zzs" a -mx=9 -mhe=off "$local_working_directory/$archive_name" "blocks" "indexes" "pocketdb"
cd -
cp "$local_working_directory/$archive_name" "$local_working_directory/latest.7z"

# Create an MD5SUM of the archive
log_message "Creating an MD5SUM of the archive..."
snapshot_md5sum=$(md5sum "$local_working_directory/$archive_name" | awk '{print $1}')
echo "$snapshot_md5sum" > "$local_working_directory/snapshot-$block_height.md5"
cp "$local_working_directory/snapshot-$block_height.md5" "$local_working_directory/latest.md5"

# Create the Snapshot "Banner"
log_message "Creating the snapshot banner..."
banner_file="$local_working_directory/snapshot-$block_height-$(date +%Y%m%d).txt"
echo "Pocketnet Blockchain Snapshot" > "$banner_file"
echo "Snapshot Block Height: $block_height" >> "$banner_file"
echo "Block Hash at Block Height: $block_hash" >> "$banner_file"
echo "Node Version: $node_version" >> "$banner_file"
archive_size=$(du -sb "$local_working_directory/$archive_name" | cut -f1)
archive_size_gb=$(awk "BEGIN {printf \"%.0f\", $archive_size / 1024 / 1024 / 1024}")
echo "Uncompressed Size of Blockchain Data: $(printf "%'d" $data_volume_bytes) bytes / $data_volume_gb G" >> "$banner_file"
echo "Compressed Size of Archive: $(printf "%'d" $archive_size) bytes / $archive_size_gb G" >> "$banner_file"
echo "MD5SUM: $snapshot_md5sum" >> "$banner_file"
echo "Brought to you by AmericanPatriotDave" >> "$banner_file"

# Trap to do house cleaning on source_node
trap 'cleanup_remote_host' EXIT

# Prompt User to End
if [ "$interactive_execution" = true ]; then
    log_message "Prompting user to end..."
    cat "$banner_file"
    log_message "Confirm the archive data above.  Type Ctl-C here to stop or press <ENTER> to perform automatic housecleaning and end the operation."
    log_message "Press Enter to continue..."
    read -r
fi

# Cleanup blockchain data
log_message "Cleaning up blockchain data..."
rm -rf "$local_working_directory/snapshot"
rm -rf "$local_working_directory/7zzs"
rm -rf "$local_working_directory/remote_command_output_checksum"
rm -rf "$local_working_directory/remote_command_output"
log_message "Blockchain data cleaned up."


