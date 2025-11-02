# Pocketnet Node Monitor

A robust monitoring script for Pocketnet blockchain nodes that tracks node status, block height, and detects when your node is lagging behind the network's majority block height.

**Version**: `v0.8.0` (November 2025 Update)

## Table of Contents
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [How It Works](#how-it-works)
  - [Runtime State Management](#runtime-state-management)
  - [Dynamic Subject Lines](#dynamic-subject-lines)
  - [Seed Node Retrieval Failure Handling](#seed-node-retrieval-failure-handling)
  - [Lag Detection Logic](#lag-detection-logic)
- [Email Configuration](#email-configuration)
  - [Using `.msmtprc` for Email Notifications](#using-msmtprc-for-email-notifications)
- [Troubleshooting](#troubleshooting)
- [Dependencies Installation](#dependencies-installation)
- [Advanced Configuration](#advanced-configuration)
- [Setting Up Log Rotation](#setting-up-log-rotation)
- [License](#license)
- [Contributing](#contributing)

## Features

- **Network Consensus Monitoring**: Calculates the Majority Block Height (MBH) across the network.
- **LAG Detection**: Alerts when your node falls behind the network consensus.
- **Node Status Tracking**: Monitors when your node goes offline or comes back online.
- **Email Notifications (Optional)**: Sends alerts when issues are detected.
- **Logging-Only Mode**: Operates without email notifications if `.msmtprc` is not configured.
- **Runtime Statistics**: Maintains statistics between script executions with atomic updates.
- **Configurable Thresholds**: Customize alert sensitivity based on your needs.
- **Curated Node List**: Uses regularly updated list of high-performance v0.22.19 nodes.
- **Data Validation**: Validates block heights and prevents errors from corrupt data.
- **Test Suites**: Includes automated tests for reliability verification.

## Requirements

- A running Pocketnet node.
- Bash shell.
- `jq` (JSON processor).
- `curl` (HTTP client).
- `msmtp` (SMTP client for email notifications, optional).

## Installation

1. Clone this repository or download the script:

```bash
git clone https://github.com/Pewejekubam/pocketnet_probe_nodes.git
cd pocketnet_probe_nodes
```

2. Make the script executable:

```bash
chmod +x pocketnet_probe_nodes.sh
```

3. Create the configuration file (`probe_nodes_conf.json`):

```bash
cp probe_nodes_conf.example.json probe_nodes_conf.json
```

4. Edit the configuration file with your settings:

```bash
nano probe_nodes_conf.json
```

## Configuration

Edit `probe_nodes_conf.json` with your specific settings:

```json
{
  "CONFIG_DIR": "/path/to/config/directory",
  "SEED_NODES_URL": "https://raw.githubusercontent.com/Pewejekubam/pocketnet_probe_nodes/refs/heads/main/APDs-node-list-20251102.txt",
  "MAX_ALERTS": 5,
  "THRESHOLD": 3,
  "POCKETCOIN_CLI_ARGS": "-datadir=/path/to/pocketcoin/data",
  "SMTP_HOST": "smtp.example.com",
  "SMTP_PORT": 587,
  "RECIPIENT_EMAIL": "your-email@example.com",
  "EMAIL_TESTING": "false",
  "MAJORITY_LAG_THRESH": 300
}
```

### Logging-Only Mode

The script can operate in a logging-only mode if email notifications are not required. To enable this mode do not configure a `~/.msmtprc` file
In this mode, the script will log all activity to the log file specified in the `CONFIG_DIR` but will not send any email alerts.

## Email Configuration

### Using `.msmtprc` for Email Notifications

To enable email notifications, you must configure the `.msmtprc` file in your home directory. This file is used by `msmtp` to send emails.

1. **Create the `.msmtprc` file**:

```bash
nano ~/.msmtprc
```

2. **Add the following configuration**:

```plaintext
# Example .msmtprc configuration
account default
host smtp.example.com
port 587
from node-monitor@example.com
auth on
user smtp-username
password smtp-password
tls on
logfile ~/probe_nodes/msmtp.log
```

3. **Set the correct permissions**:

```bash
chmod 600 ~/.msmtprc
```

4. **Verify the configuration**:

Run the following command to test the email setup:

```bash
echo "Test email body" | msmtp --debug --from=node-monitor@example.com -t your-email@example.com
```

## Usage

### Manual Execution

Run the script manually:

```bash
./probe_nodes.sh
```

### Setting up a Cron Job

To run the script automatically at regular intervals:

1. Edit your crontab:

```bash
crontab -e
```

2. Add an entry to run the script every 15 minutes:

```
*/15 * * * * /path/to/probe_nodes.sh > /dev/null 2>&1
```

### Testing Email Configuration

Set `EMAIL_TESTING` to `true` in your configuration file and run the script. It will send a test email and exit:

```bash
./probe_nodes.sh
```

After confirming email functionality works, set `EMAIL_TESTING` back to `false`.

## How It Works

### Runtime State Management

The script uses a runtime file (`probe_nodes_runtime.json`) to persist state between executions. This file tracks:
- Offline/online status
- Consecutive offline checks
- Consecutive lag checks
- Alert counters

These values are reset or updated based on the node's current status, ensuring accurate monitoring and avoiding redundant alerts.

### Dynamic Subject Lines

The script dynamically generates email subject lines based on templates. For example:
- "OFFLINE | Peers: 5"
- "LAG | 300 blocks behind MBH"
- "ALERT | No seed nodes found"

These subject lines provide a quick summary of the issue being reported.

### Seed Node Retrieval Failure Handling

If no seed nodes are retrieved from the configured `SEED_NODES_URL`, the script logs an error and sends an email notification. This ensures you are alerted to potential network or configuration issues.

### Lag Detection Logic

The script tracks consecutive lag checks using the `consecutive_lag_checks` counter. This helps avoid false positives by requiring the lag condition to persist across multiple checks before sending an alert.

### Runtime File Initialization

If the runtime file (`probe_nodes_runtime.json`) does not exist, the script will automatically create it with the following default values:

```json
{
  "comment": "This file is used exclusively by the script and should not be edited manually.",
  "offline_check_count": 0,
  "previous_node_online": true,
  "sent_alert_count": 0,
  "online_start_time": "",
  "offline_start_time": "",
  "consecutive_lag_checks": 0
}
```

This file is used to persist runtime data between script executions, such as the node's online/offline status and alert counters.

### Majority Block Height (MBH) Calculation

The script determines the network consensus by:

1. Retrieving a list of seed nodes
2. Collecting block heights from seed nodes
3. Collecting block heights from connected peers
4. Finding the most frequent block height (the majority)

### Seed Node Retrieval

The script retrieves a list of seed node IP addresses from the URL specified in the `SEED_NODES_URL` parameter. These seed nodes are queried to collect block height information, which is used to calculate the Majority Block Height (MBH). If no seed nodes are retrieved, the script logs an error and sends an email notification.

### Peer Node Monitoring

In addition to seed nodes, the script queries connected peer nodes to collect block height information. This data is combined with seed node data to calculate the Majority Block Height (MBH), ensuring a more accurate representation of the network's consensus.

### LAG Detection Logic

The script considers your node to be lagging when:

1. Your node is online
2. Your node's block height is lower than the Majority Block Height (MBH)
3. The difference exceeds the configured `MAJORITY_LAG_THRESH` value
4. This condition persists for multiple checks (tracked by `consecutive_lag_checks`)

### On-Chain Status

Your node is considered "on-chain" when:

1. The node is online
2. The node's block height is within `MAJORITY_LAG_THRESH` blocks of the MBH

### Offline Detection

The script tracks offline status by:

1. Attempting to query node information via CLI and API
2. Incrementing an offline counter for each failed check
3. Sending an alert when the counter exceeds the configured threshold
4. Tracking the duration of offline periods

### Email Testing Mode

To verify that email notifications are working correctly, set `EMAIL_TESTING` to `true` in your configuration file and run the script. The script will send a test email with the configured SMTP settings and exit without performing any other operations.

Example test email content:
```
Subject: Test Email from Pocketnet Node
Body:
This is a test email from the Pocketnet node script.

SMTP Host: smtp.example.com
SMTP Port: 587
Recipient Email: your-email@example.com
From: node-monitor@example.com
User: smtp-username
TLS: true
Auth: true
```
After confirming that the test email is received, set `EMAIL_TESTING` back to `false` to resume normal script operation.

### Offline Duration Tracking

When the node transitions from offline to online, the script calculates the duration of the offline period and includes this information in the email notification. The duration is displayed in a human-readable format (e.g., "2 Days, 3 Hours, 15 Minutes").

### Counter Resets

The script resets specific counters under the following conditions:
- `offline_check_count`: Reset when the node transitions from offline to online.
- `consecutive_lag_checks`: Reset when the node's block height catches up to the Majority Block Height (MBH).

These resets ensure that the script accurately tracks the node's status and avoids redundant alerts.

## Recent Improvements (v0.8.0 - November 2025)

### Bug Fixes
- **Email notifications**: Fixed associative array bug causing "context" to appear in emails instead of actual values
- **Missing timestamp**: Added timestamp variable initialization preventing empty timestamps
- **Threshold notifications**: Fixed missing "threshold" notification type
- **Seed node handling**: Script now exits properly when no seed nodes are retrieved

### Reliability Improvements
- **Atomic state updates**: Uses `flock` to prevent race conditions during concurrent executions
- **Numeric validation**: Validates block heights are numbers before arithmetic operations
- **Updated node list**: Curated list of 50 high-performance v0.22.19 nodes sorted by peer count

### Testing
Run the included test suites to verify installation:
```bash
./test_phase1_fixes.sh  # Tests critical bug fixes
./test_phase2_fixes.sh  # Tests reliability improvements
```

## Log Files

The script creates these files in your configured `CONFIG_DIR`:

- `probe_nodes.log` - Main log file with script activity
- `probe_nodes_runtime.json` - Runtime data persisted between executions
- `probe_nodes_runtime.json.lock` - Lock file for atomic state updates

## Troubleshooting

### Common Issues

1. **Script fails to run**:
   - Ensure the script is executable (`chmod +x probe_nodes.sh`).
   - Check that all dependencies are installed (`jq`, `curl`, `msmtp`).

2. **No emails are sent**:
   - Verify `.msmtprc` configuration.
   - Check that `msmtp` is installed and working.
   - Try the test mode by setting `EMAIL_TESTING` to `true`.

3. **Script reports "No seed nodes retrieved"**:
   - Check your internet connection.
   - Verify the `SEED_NODES_URL` is correct and accessible.

4. **False positive LAG alerts**:
   - Increase `MAJORITY_LAG_THRESH` to be more tolerant of small variations.
   - Check network connectivity to ensure all nodes are reachable.

5. **Invalid block height values**:
   - Ensure your Pocketnet node is fully synced.
   - Check if your node's API is working properly.

## Dependencies Installation

### Ubuntu/Debian

```bash
sudo apt-get update
sudo apt-get install jq curl msmtp
```

### CentOS/RHEL

```bash
sudo yum install epel-release
sudo yum install jq curl
sudo yum install msmtp
```

### macOS (using Homebrew)

```bash
brew install jq curl msmtp
```

## Advanced Configuration

### Tuning LAG Thresholds

The `MAJORITY_LAG_THRESH` parameter controls how sensitive the script is to your node falling behind:

- **Lower values** (e.g., 3-5 blocks): More sensitive, potentially more false positives.
- **Higher values** (e.g., 200-300 blocks): Less sensitive, might miss smaller lags.

Choose a value appropriate for your network's block time and acceptable sync delay.

### Alert Frequency

To avoid alert fatigue:

1. Set `MAX_ALERTS` to limit consecutive alerts.
2. Adjust the cron schedule to run less frequently.
3. Increase `THRESHOLD` to require more consecutive failures.

## Setting Up Log Rotation

To prevent log files from growing indefinitely (they can reach 200MB+), use the included logrotate configuration.

### Installation

1. **Copy the configuration file**:
   ```bash
   sudo cp probe_nodes.logrotate /etc/logrotate.d/probe_nodes
   sudo chmod 644 /etc/logrotate.d/probe_nodes
   sudo chown root:root /etc/logrotate.d/probe_nodes
   ```

2. **Edit if needed**:
   If your log file is in a non-standard location, edit the path on line 15:
   ```bash
   sudo nano /etc/logrotate.d/probe_nodes
   # Update: /home/pocketnet/probe_nodes/probe_nodes.log
   # To your CONFIG_DIR path
   ```

3. **Add the `su` directive** (required for proper permissions):
   The config file needs to specify which user owns the logs. Add this line after the opening `{`:
   ```
   su pocketnet pocketnet
   ```
   Replace `pocketnet` with your actual username if different.

4. **Verify the setup**:
   ```bash
   sudo logrotate -d /etc/logrotate.d/probe_nodes
   ```
   This simulates rotation without making changes.

5. **Force first rotation** (optional, for testing):
   ```bash
   sudo logrotate -f /etc/logrotate.d/probe_nodes
   ```

### Configuration Details

The included `probe_nodes.logrotate` file configures:
- **Daily rotation**: Logs rotated once per day
- **14 day retention**: Keeps 2 weeks of history
- **Compression**: Old logs compressed with gzip to save space
- **Safe rotation**: Uses `copytruncate` so script continues writing
- **Date-based naming**: Rotated files named like `probe_nodes.log-20251102`

### Troubleshooting

**Permission errors**: Ensure the `su` directive matches the user running the script.

**Logs not rotating**: Check if logrotate is enabled:
```bash
sudo systemctl status logrotate.timer
sudo systemctl enable logrotate.timer
```

**View rotated logs**:
```bash
zcat probe_nodes.log-20251102.gz
```

## License

MIT License - See the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository.
2. Create your feature branch (`git checkout -b feature/amazing-feature`).
3. Commit your changes (`git commit -m 'Add some amazing feature'`).
4. Push to the branch (`git push origin feature/amazing-feature`).
5. Open a Pull Request.