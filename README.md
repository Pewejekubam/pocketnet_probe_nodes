# Pocketnet Node Monitor

A robust monitoring script for Pocketnet blockchain nodes that tracks node status, block height, and detects when your node is lagging behind the network's majority block height.

## Features

- **Network Consensus Monitoring**: Calculates the Majority Block Height (MBH) across the network
- **LAG Detection**: Alerts when your node falls behind the network consensus
- **Node Status Tracking**: Monitors when your node goes offline or comes back online
- **Email Notifications (Optional)**: Sends alerts when issues are detected
- **Logging-Only Mode**: Operates without email notifications if email settings are left blank
- **Runtime Statistics**: Maintains statistics between script executions
- **Configurable Thresholds**: Customize alert sensitivity based on your needs

## Requirements

- A running Pocketnet node
- Bash shell
- `jq` (JSON processor)
- `curl` (HTTP client)
- `msmtp` (SMTP client for email notifications, optional)

## Installation

1. Clone this repository or download the script:

```bash
git clone https://github.com/yourusername/pocketnet-node-monitor.git
cd pocketnet-node-monitor
```

2. Make the script executable:

```bash
chmod +x probe_nodes-08.sh
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
  "SEED_NODES_URL": "https://raw.githubusercontent.com/pocketnetteam/pocketnet.core/76b20a013ee60d019dcfec3a4714a4e21a8b432c/contrib/seeds/nodes_main.txt",
  "MAX_ALERTS": 5,
  "THRESHOLD": 3,
  "POCKETCOIN_CLI_ARGS": "-datadir=/path/to/pocketcoin/data",
  "SMTP_HOST": "smtp.example.com",
  "SMTP_PORT": 587,
  "RECIPIENT_EMAIL": "your-email@example.com",
  "MSMTP_FROM": "node-monitor@example.com",
  "MSMTP_USER": "smtp-username",
  "MSMTP_PASSWORD": "smtp-password",
  "MSMTP_TLS": "true",
  "MSMTP_AUTH": "true",
  "EMAIL_TESTING": "false",
  "MAJORITY_LAG_THRESH": 300
}
```

### Logging-Only Mode

The script can operate in a logging-only mode if email notifications are not required. To enable this mode:

1. Leave the `SMTP_HOST`, `RECIPIENT_EMAIL`, and `MSMTP_FROM` fields blank in the configuration file.
2. Ensure `EMAIL_TESTING` is set to `false`.

In this mode, the script will log all activity to the log file specified in the `CONFIG_DIR` but will not send any email alerts. This is useful for users who only need monitoring and logging without email notifications.

### Email Notifications (Optional)

If you wish to enable email notifications, configure the following fields in `probe_nodes_conf.json`:

- `SMTP_HOST`: SMTP server hostname
- `SMTP_PORT`: SMTP server port
- `RECIPIENT_EMAIL`: Email address to receive alerts
- `MSMTP_FROM`: Sender email address
- `EMAIL_TESTING`: Set to `true` to test email functionality

If these fields are not configured, the script will default to logging-only mode.

### Example Configuration for Logging-Only Mode

```json
{
  "CONFIG_DIR": "/path/to/config/directory",
  "SEED_NODES_URL": "https://raw.githubusercontent.com/pocketnetteam/pocketnet.core/76b20a013ee60d019dcfec3a4714a4e21a8b432c/contrib/seeds/nodes_main.txt",
  "SMTP_HOST": "",
  "SMTP_PORT": "",
  "RECIPIENT_EMAIL": "",
  "MSMTP_FROM": "",
  "EMAIL_TESTING": false,
  "MAJORITY_LAG_THRESH": 300
}
```

In this configuration, the script will only log activity and not send any email alerts.

### Configuration Parameters

| Parameter | Description |
|-----------|-------------|
| `CONFIG_DIR` | Directory to store runtime data and logs |
| `SEED_NODES_URL` | URL to retrieve seed node IP addresses |
| `MAX_ALERTS` | Maximum number of consecutive alerts to send |
| `THRESHOLD` | Number of consecutive offline checks before alerting |
| `POCKETCOIN_CLI_ARGS` | Arguments to pass to pocketcoin-cli |
| `SMTP_HOST` | SMTP server hostname |
| `SMTP_PORT` | SMTP server port |
| `RECIPIENT_EMAIL` | Email address to receive alerts |
| `MSMTP_FROM` | Sender email address |
| `MSMTP_USER` | SMTP username (optional) |
| `MSMTP_PASSWORD` | SMTP password (optional) |
| `MSMTP_TLS` | Use TLS for SMTP connection ("true" or "false") |
| `MSMTP_AUTH` | Use authentication for SMTP connection ("true" or "false") |
| `EMAIL_TESTING` | Enable email testing mode ("true" or "false") |
| `MAJORITY_LAG_THRESH` | Maximum allowed block difference from majority height |

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
*/15 * * * * /path/to/probe_nodes-08.sh > /dev/null 2>&1
```

### Testing Email Configuration

Set `EMAIL_TESTING` to `true` in your configuration file and run the script. It will send a test email and exit:

```bash
./probe_nodes.sh
```

After confirming email functionality works, set `EMAIL_TESTING` back to `false`.

## How It Works

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

## Log Files

The script creates these files in your configured `CONFIG_DIR`:

- `probe_nodes.log` - Main log file with script activity
- `probe_nodes_runtime.json` - Runtime data persisted between executions

## Troubleshooting

### Common Issues

1. **Script fails to run**:
   - Ensure the script is executable (`chmod +x probe_nodes-08.sh`)
   - Check that all dependencies are installed (`jq`, `curl`, `msmtp`)

2. **No emails are sent**:
   - Verify SMTP configuration
   - Check that `msmtp` is installed and working
   - Try the test mode by setting `EMAIL_TESTING` to `true`

3. **Script reports "No seed nodes retrieved"**:
   - Check your internet connection
   - Verify the `SEED_NODES_URL` is correct and accessible

4. **False positive LAG alerts**:
   - Increase `MAJORITY_LAG_THRESH` to be more tolerant of small variations
   - Check network connectivity to ensure all nodes are reachable

5. **Invalid block height values**:
   - Ensure your Pocketnet node is fully synced
   - Check if your node's API is working properly

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

- **Lower values** (e.g., 3-5 blocks): More sensitive, potentially more false positives
- **Higher values** (e.g., 200-300 blocks): Less sensitive, might miss smaller lags

Choose a value appropriate for your network's block time and acceptable sync delay.

### Alert Frequency

To avoid alert fatigue:

1. Set `MAX_ALERTS` to limit consecutive alerts
2. Adjust the cron schedule to run less frequently
3. Increase `THRESHOLD` to require more consecutive failures

## License

MIT License - See the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request