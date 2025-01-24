### Description

The `probe_nodes.sh` script is designed to monitor the status of a Pocketnet node by performing the following tasks:

1. Fetch Seed Node IP Addresses:
   - Retrieves a list of seed node IP addresses from a specified URL and saves them to a file.

2. Get Block Heights and Versions:
   - For each seed node and connected node, the script queries the node to get its current block height and version.
   - Logs the block height and version information to a log file.

3. Calculate Average Block Height:
   - Calculates the average block height from the collected block heights of seed and connected nodes.

4. Identify and Ban Outdated Nodes:
   - Identifies nodes that are significantly behind the average block height (more than a specified threshold).
   - Adds these nodes to a ban list to prevent them from affecting the network.

5. Monitor Local Node Status:
   - Queries the local node to get its current block height and peer count.
   - Logs the local node's block height, peer count, and online status.

6. Check On-Chain Condition:
   - Determines if the local node is "on-chain" by checking if its block height is within a specified range of the average block height.

7. Send Alerts:
   - Sends email alerts if the local node is offline or significantly behind the average block height.
   - Limits the number of alerts sent to avoid spamming.

8. Log Information:
   - Logs all relevant information, including block heights, on-chain status, node online status, and peer count, to a log file for monitoring and troubleshooting.

The script is intended to be run periodically (e.g., every 10 minutes) using a cron job to ensure continuous monitoring of the Pocketnet node's status.

### Configuration

Before running the script, you need to modify the configuration parameters block to match your environment. This includes setting the appropriate values for the `msmtp` parameters used for sending email alerts.

Here is the configuration block you need to modify:

```bash
# Configuration parameters
# Note: Not all parameters are necessary to configure for your particular email setup.
# Leave blank ("") any parameters that are not to be passed to the MTA.
CONFIG_DIR="$HOME/probe_nodes"
LOG_FILE="$CONFIG_DIR/probe_nodes.log"
TEMP_LOG_FILE="$CONFIG_DIR/probe_nodes_temp.log"
SEED_NODES_URL="https://example.com/seeds/nodes_main.txt"
MAX_ALERTS=3
ALERT_COUNT_FILE="$CONFIG_DIR/alert_count.txt"
THRESHOLD=3
THRESHOLD_COUNT_FILE="$CONFIG_DIR/threshold_count.txt"
BAN_LIST_FILE="$CONFIG_DIR/ban_list.txt"
BAN_THRESHOLD=10000  # Number of blocks behind to consider banning
SMTP_HOST="smtp.example.com"
SMTP_PORT=587
SENDER_DOMAIN="example.com"
RECIPIENT_EMAIL="alert@example.com"
MSMTP_FROM="node@example.com"
MSMTP_USER="your_email@example.com"
MSMTP_PASSWORD="your_password"
MSMTP_TLS=true
MSMTP_AUTH=true

Sure, here is the updated `README.md` content in a single block for easy copying and pasting:

```markdown
### Description

The `probe_nodes.sh` script is designed to monitor the status of a Pocketnet node by performing the following tasks:

1. Fetch Seed Node IP Addresses:
   - Retrieves a list of seed node IP addresses from a specified URL and saves them to a file.

2. Get Block Heights and Versions:
   - For each seed node and connected node, the script queries the node to get its current block height and version.
   - Logs the block height and version information to a log file.

3. Calculate Average Block Height:
   - Calculates the average block height from the collected block heights of seed and connected nodes.

4. Identify and Ban Outdated Nodes:
   - Identifies nodes that are significantly behind the average block height (more than a specified threshold).
   - Adds these nodes to a ban list to prevent them from affecting the network.

5. Monitor Local Node Status:
   - Queries the local node to get its current block height and peer count.
   - Logs the local node's block height, peer count, and online status.

6. Check On-Chain Condition:
   - Determines if the local node is "on-chain" by checking if its block height is within a specified range of the average block height.

7. Send Alerts:
   - Sends email alerts if the local node is offline or significantly behind the average block height.
   - Limits the number of alerts sent to avoid spamming.

8. Log Information:
   - Logs all relevant information, including block heights, on-chain status, node online status, and peer count, to a log file for monitoring and troubleshooting.

The script is intended to be run periodically (e.g., every 10 minutes) using a cron job to ensure continuous monitoring of the Pocketnet node's status.

### Configuration

Before running the script, you need to modify the configuration parameters block to match your environment. This includes setting the appropriate values for the `msmtp` parameters used for sending email alerts.

Here is the configuration block you need to modify:

```bash
# Configuration parameters
# Note: Not all parameters are necessary to configure for your particular email setup.
# Leave blank ("") any parameters that are not to be passed to the MTA.
CONFIG_DIR="$HOME/probe_nodes"
LOG_FILE="$CONFIG_DIR/probe_nodes.log"
TEMP_LOG_FILE="$CONFIG_DIR/probe_nodes_temp.log"
SEED_NODES_URL="https://example.com/seeds/nodes_main.txt"
MAX_ALERTS=3
ALERT_COUNT_FILE="$CONFIG_DIR/alert_count.txt"
THRESHOLD=3
THRESHOLD_COUNT_FILE="$CONFIG_DIR/threshold_count.txt"
BAN_LIST_FILE="$CONFIG_DIR/ban_list.txt"
BAN_THRESHOLD=10000  # Number of blocks behind to consider banning
SMTP_HOST="smtp.example.com"
SMTP_PORT=587
SENDER_DOMAIN="example.com"
RECIPIENT_EMAIL="alert@example.com"
MSMTP_FROM="node@example.com"
MSMTP_USER="your_email@example.com"
MSMTP_PASSWORD="your_password"
MSMTP_TLS=true
MSMTP_AUTH=true
```

Make sure to update the following parameters to match your environment:
- `CONFIG_DIR`: Directory where logs and temporary files will be stored.
- `SEED_NODES_URL`: URL to fetch the list of seed node IP addresses.
- `SMTP_HOST`: SMTP server host for sending email alerts.
- `SMTP_PORT`: SMTP server port.
- `SENDER_DOMAIN`: Domain for the sender email address.
- `RECIPIENT_EMAIL`: Email address to receive alerts.
- `MSMTP_FROM`: Sender email address for `msmtp`.
- `MSMTP_USER`: Username for SMTP authentication.
- `MSMTP_PASSWORD`: Password for SMTP authentication.
- `MSMTP_TLS`: Boolean to enable/disable TLS.
- `MSMTP_AUTH`: Boolean to enable/disable authentication.

### Requirements

This script requires `msmtp` to send email alerts. You can install `msmtp` using your package manager. For example, on Debian-based systems, you can install it with:

```bash
sudo apt-get install msmtp
```

After updating the configuration parameters and installing `msmtp`, you can run the script to monitor your Pocketnet node.
```