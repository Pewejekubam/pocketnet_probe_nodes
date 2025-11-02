#!/usr/bin/env bash
set -euo pipefail

# ==========================
# Configuration
# ==========================
SOURCE_DIR="$(pwd)"
TARGET_ROOT="/data/codebu"

REMOTE_HOST="biz-san21"
REMOTE_USER="sysadmin"
REMOTE_KEY="/home/sysadmin/.ssh/id_ecdsa_oval.priv.sshd"
REMOTE_PATH="/mnt/EXTHDD6/internetwork-dropbox/code-backup/"

# ==========================
# Prepare environment
# ==========================
if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "❌ Current directory '$SOURCE_DIR' is not valid."
  exit 1
fi

mkdir -p "$TARGET_ROOT"
DIR_NAME="$(basename "$SOURCE_DIR")"

# ==========================
# Git metadata
# ==========================
GIT_HASH=$(git -C "$SOURCE_DIR" rev-parse --short HEAD 2>/dev/null || echo "nogit")
GIT_MESSAGE=$(git -C "$SOURCE_DIR" log -1 --format=%s 2>/dev/null || echo "No commit message available")

# ==========================
# Archive setup
# ==========================
TIMESTAMP=$(date +"%Y%m%d%H%M")
ARCHIVE_NAME="${DIR_NAME}-${TIMESTAMP}-${GIT_HASH}.tar"
TARGET_PATH="${TARGET_ROOT}/${ARCHIVE_NAME}"
COMMIT_FILE="${SOURCE_DIR}/commit_message.txt"
REMOTE_ARCHIVE_PATH="${REMOTE_PATH}${ARCHIVE_NAME}"

if [[ -f "$TARGET_PATH" ]]; then
  echo "❌ Target archive '$TARGET_PATH' already exists."
  exit 1
fi

# ==========================
# Create archive
# ==========================
echo "$GIT_MESSAGE" > "$COMMIT_FILE"
trap 'rm -f "$COMMIT_FILE"' EXIT

tar -cf "$TARGET_PATH" -C "$SOURCE_DIR" .

rm -f "$COMMIT_FILE"
trap - EXIT

# ==========================
# Archive stats
# ==========================
ARCHIVE_SIZE=$(du -sh "$TARGET_PATH" | cut -f1)
FOLDER_COUNT=$(find "$SOURCE_DIR" -type d | wc -l)
FILE_COUNT=$(find "$SOURCE_DIR" -type f | wc -l)

# ==========================
# Remote backup
# ==========================
REMOTE_SUCCESS="false"
echo "🔄 Attempting remote transfer..."

if ssh -i "$REMOTE_KEY" -o ConnectTimeout=10 -o BatchMode=yes \
    "$REMOTE_USER@$REMOTE_HOST" "test -d '$REMOTE_PATH'" 2>/dev/null; then
  if scp -i "$REMOTE_KEY" "$TARGET_PATH" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH"; then
    REMOTE_SUCCESS="true"
  fi
fi

# ==========================
# Summary
# ==========================
if [[ "$REMOTE_SUCCESS" == "true" ]]; then
  echo "✅ Local and Remote Backups Created Successfully"
else
  echo "✅ Local Backup Created Successfully (Remote Failed)"
fi

echo "------------------------------"
echo "Git Commit:   $GIT_HASH"
echo "Message:      $GIT_MESSAGE"
echo "Folders:      $FOLDER_COUNT"
echo "Files:        $FILE_COUNT"
echo "Size:         $ARCHIVE_SIZE"
echo "Local Target: $TARGET_PATH"
if [[ "$REMOTE_SUCCESS" == "true" ]]; then
  echo "Remote Target: $REMOTE_USER@$REMOTE_HOST:$REMOTE_ARCHIVE_PATH"
else
  echo "Remote Target: Failed to transfer to $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH"
fi
