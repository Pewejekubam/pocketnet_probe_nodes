# Log Rotation Setup for probe_nodes.sh

## Problem
The probe_nodes.log file grows unbounded. On production servers, it has reached 226MB+, which:
- Wastes disk space
- Slows down log viewing/searching
- May impact performance when writing to large files

## Solution
Use `logrotate` to automatically manage log file rotation.

## Installation

### Step 1: Copy the configuration file
```bash
sudo cp probe_nodes.logrotate /etc/logrotate.d/probe_nodes
```

### Step 2: Set correct permissions
```bash
sudo chmod 644 /etc/logrotate.d/probe_nodes
sudo chown root:root /etc/logrotate.d/probe_nodes
```

### Step 3: Verify configuration syntax
```bash
sudo logrotate -d /etc/logrotate.d/probe_nodes
```

This runs in debug mode and shows what would happen without actually rotating files.

### Step 4: (Optional) Force first rotation to test
```bash
sudo logrotate -f /etc/logrotate.d/probe_nodes
```

This forces an immediate rotation to verify everything works correctly.

## Configuration Details

The logrotate configuration will:
- **Rotate daily** - Checks once per day
- **Keep 14 days** - Retains 2 weeks of logs
- **Compress old logs** - Saves disk space (uses gzip)
- **Delay compression** - Most recent rotated file stays uncompressed for easy access
- **Use copytruncate** - Copies log then truncates original (safe for running scripts)
- **Date-based naming** - Files named like `probe_nodes.log-20251102`

## Verification

### Check if logrotate is running
```bash
sudo systemctl status logrotate.timer
```

### View logrotate logs
```bash
sudo journalctl -u logrotate
```

### Check when last rotation occurred
```bash
ls -lh /home/pocketnet/probe_nodes/probe_nodes.log*
```

### Expected file structure after rotation
```
probe_nodes.log              # Current log
probe_nodes.log-20251102     # Yesterday (uncompressed)
probe_nodes.log-20251101.gz  # 2 days ago (compressed)
probe_nodes.log-20251031.gz  # 3 days ago (compressed)
...
```

## Deployment Commands

### Deploy to pocketnet-node11
```bash
scp probe_nodes.logrotate pocketnet-node11:/tmp/
ssh pocketnet-node11 "sudo mv /tmp/probe_nodes.logrotate /etc/logrotate.d/probe_nodes && \
                      sudo chmod 644 /etc/logrotate.d/probe_nodes && \
                      sudo chown root:root /etc/logrotate.d/probe_nodes && \
                      sudo logrotate -d /etc/logrotate.d/probe_nodes"
```

### Deploy to pocketnet-node12
```bash
scp probe_nodes.logrotate pocketnet-node12:/tmp/
ssh pocketnet-node12 "sudo mv /tmp/probe_nodes.logrotate /etc/logrotate.d/probe_nodes && \
                      sudo chmod 644 /etc/logrotate.d/probe_nodes && \
                      sudo chown root:root /etc/logrotate.d/probe_nodes && \
                      sudo logrotate -d /etc/logrotate.d/probe_nodes"
```

## Troubleshooting

### Logrotate not running automatically
Check the timer:
```bash
sudo systemctl status logrotate.timer
sudo systemctl enable logrotate.timer
sudo systemctl start logrotate.timer
```

### Permission errors
Ensure the pocketnet user can write to the log file:
```bash
sudo chown pocketnet:pocketnet /home/pocketnet/probe_nodes/probe_nodes.log
```

### Logs not being compressed
Check if gzip is installed:
```bash
which gzip
```

### Force immediate rotation for testing
```bash
sudo logrotate -f /etc/logrotate.d/probe_nodes
```

## Notes

- Logrotate typically runs once per day via cron or systemd timer
- The `copytruncate` option is used because the script keeps the log file open
- Old logs beyond 14 days are automatically deleted
- Compressed logs can be viewed with: `zcat probe_nodes.log-20251101.gz`
