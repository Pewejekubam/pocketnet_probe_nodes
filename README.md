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
SMTP_HOST="10.168.32.63"
SMTP_PORT=25
SENDER_DOMAIN="dennen.us"
RECIPIENT_EMAIL="pocket_node_alert@dennen.com"
MSMTP_ACCOUNT="pocketnet-node12"
MSMTP_FROM="pocketnet-node12.12project@dennen.us"