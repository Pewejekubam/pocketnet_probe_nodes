
# Pocketnet Node Monitoring Script

## by Pewejekubam -- a Pocketnet node operator

## Overview

This script monitors Pocketnet nodes and sends alerts via email when certain conditions are met. It retrieves seed node IP addresses, checks block heights, and determines the majority block height (MBH). The script can also send test emails to verify email configuration.

## Prerequisites

- jq (for processing JSON)
- curl (for making HTTP requests)
- msmtp (for sending emails)

## Configuration

probe_nodes_conf.json 

```json
{
    "CONFIG_DIR": "/home/pocketnet/probe_nodes",
    "SEED_NODES_URL": "https://raw.githubusercontent.com/pocketnetteam/pocketnet.core/76b20a013ee60d019dcfec3a4714a4e21a8b432c/contrib/seeds/nodes_main.txt",
    "MAX_ALERTS": 3,
    "THRESHOLD": 3,
    "POCKETCOIN_CLI_ARGS": "",
    "SMTP_HOST": "smtp.example.com",
    "SMTP_PORT": 587,
    "RECIPIENT_EMAIL": "alert@example.com",
    "MSMTP_FROM": "node@example.com",
    "MSMTP_USER": "your_email@example.com",
    "MSMTP_PASSWORD": "your_password",
    "MSMTP_TLS": true,
    "MSMTP_AUTH": false,
    "EMAIL_TESTING": false
}
```

### Parameter Descriptions

 1. CONFIG_DIR: The directory where the script will store log files, runtime files, and other necessary data.
 2. SEED_NODES_URL: The URL to retrieve the list of seed node IP addresses.
 3. MAX_ALERTS: The maximum number of alert emails that the script will send if a node is offline or off-chain. This helps prevent flooding the recipient with too many emails in case of persistent issues.
 4. THRESHOLD: The number of consecutive times the script detects that the node is offline or off-chain before it sends an alert email. This helps to avoid false positives due to transient network issues.
 5. POCKETCOIN_CLI_ARGS: The command-line arguments to pass to the pocketcoin-cli command. This can be useful for specifying additional parameters or options when interacting with the Pocketnet node.
 6. SMTP_HOST: The hostname or IP address of the SMTP server used to send alert emails. This should be configured to match your email provider's SMTP server.
 7. SMTP_PORT: The port number to connect to the SMTP server. Common port numbers are 25, 465 (SSL), and 587 (TLS).
 8. RECIPIENT_EMAIL: The email address where the alert notifications will be sent. This should be a valid email address that you or the intended recipient can monitor.
 9. MSMTP_FROM: The email address that appears as the sender of the alert emails. This should be a valid email address that is recognized by the SMTP server.
10. MSMTP_USER: The username for authenticating with the SMTP server. This is typically the same as the email address used to send the emails.
11. MSMTP_PASSWORD: The password for authenticating with the SMTP server. Ensure this is handled securely to prevent unauthorized access.
12. MSMTP_TLS: A boolean value indicating whether to use TLS (Transport Layer Security) for secure communication with the SMTP server. Set to true to enable TLS.
13. MSMTP_AUTH: A boolean value indicating whether to use authentication when connecting to the SMTP server. Set to true to enable authentication.
14. EMAIL_TESTING: A boolean value indicating whether to send a test email to verify the email configuration. Set to true to send a test email; the script will exit after sending the test email.

## Usage

1. Ensure the probe_nodes_conf.json configuration file is in the same directory as the script.
2. Make the script executable:

   ```bash
   chmod +x your_script.sh
   ```
3. Run the script:

   ```bash
   ./probe_nodes.sh
   ```

## Functions

- get_seed_ips(): Retrieves seed IP addresses.
- get_node_info(node_ip): Gets block height and version from a node.
- update_frequency_map(origin, freq_map, node_ips): Updates frequency map with block heights.
- determine_mbh(freq_map): Determines the Majority Block Height (MBH).
- send_email(subject, body): Sends an email notification.
- main(): Main function to run the script.

## Logging

Logs are stored in the probe_nodes.log file within the CONFIG_DIR directory. Logs include timestamps, IP addresses, block heights, and any errors encountered during execution.

## Error Handling

The script ensures that required parameters are present in the configuration file and checks the validity of the JSON format. If any issues are encountered, appropriate error messages are logged, and the script exits.

## License

This project is licensed under the MIT License. See the LICENSE file for details.