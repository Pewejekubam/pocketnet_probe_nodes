# Pocketnet Node Monitor

A robust monitoring script for Pocketnet blockchain nodes that tracks node status, block height, and detects when your node is lagging behind the network's majority block height.

## Features

- **Network Consensus Monitoring**: Calculates the Majority Block Height (MBH) across the network
- **LAG Detection**: Alerts when your node falls behind the network consensus
- **Node Status Tracking**: Monitors when your node goes offline or comes back online
- **Email Notifications**: Sends alerts when issues are detected
- **Runtime Statistics**: Maintains statistics between script executions
- **Configurable Thresholds**: Customize alert sensitivity based on your needs

## Requirements

- A running Pocketnet node
- Bash shell
- `jq` (JSON processor)
- `curl` (HTTP client)
- `msmtp` (SMTP client for email notifications)

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

### Majority Block Height (MBH) Calculation

The script determines the network consensus by:

1. Retrieving a list of seed nodes
2. Collecting block heights from seed nodes
3. Collecting block heights from connected peers
4. Finding the most frequent block height (the majority)

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