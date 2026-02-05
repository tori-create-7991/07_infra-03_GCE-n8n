#!/bin/bash
set -e

# --- 1. Mount Data Disk ---
# Use the predictable Google persistent disk ID
DISK_DEVICE="/dev/disk/by-id/google-n8n_data_disk"
MOUNT_POINT="/mnt/n8n-data"

# Check if the device exists
if [ -L "$DISK_DEVICE" ]; then
  # Check if the disk is already formatted
  if ! blkid "$DISK_DEVICE"; then
    echo "Formatting data disk..."
    mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard "$DISK_DEVICE"
  else
    echo "Data disk already formatted."
  fi

  # Create mount point
  mkdir -p "$MOUNT_POINT"

  # Mount the disk if not already mounted
  if ! mountpoint -q "$MOUNT_POINT"; then
      mount -o discard,defaults "$DISK_DEVICE" "$MOUNT_POINT"
  fi

  # Add to /etc/fstab for persistent mount on reboot
  if ! grep -qs "$MOUNT_POINT" /etc/fstab; then
    UUID=$(blkid -s UUID -o value "$DISK_DEVICE")
    echo "UUID=$UUID $MOUNT_POINT ext4 discard,defaults,nofail 0 2" >> /etc/fstab
  fi

  # Set permissions
  chmod 777 "$MOUNT_POINT"
else
  echo "Data disk not found at $DISK_DEVICE"
fi

# --- 2. Setup Swap (Crucial for e2-micro) ---
SWAP_FILE="/swapfile"
if [ ! -f "$SWAP_FILE" ]; then
  echo "Setting up swap..."
  fallocate -l 2G "$SWAP_FILE"
  chmod 600 "$SWAP_FILE"
  mkswap "$SWAP_FILE"
  swapon "$SWAP_FILE"
  echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
fi

# --- 3. Install Docker ---
if ! command -v docker &> /dev/null; then
  echo "Installing Docker..."
  apt-get update
  apt-get install -y docker.io
  systemctl enable --now docker
fi

# --- 4. Run n8n ---
# Ensure n8n directory exists on the data disk
N8N_DATA_DIR="$MOUNT_POINT/.n8n"
mkdir -p "$N8N_DATA_DIR"
# Fix permissions so the node user in the container (uid 1000) can write
chown -R 1000:1000 "$N8N_DATA_DIR"

# Stop existing container if running (for updates)
docker stop n8n || true
docker rm n8n || true

# Run n8n
# - Restart automatically
# - Expose port 5678
# - Mount the data directory from the persistent disk
# - Use specific version to avoid Docker compatibility issues with debian docker.io package
# - Disable secure cookie for HTTP access (required for webhooks without HTTPS)
docker run -d \
  --name n8n \
  --restart unless-stopped \
  -p 5678:5678 \
  -v "$N8N_DATA_DIR":/home/node/.n8n \
  -e N8N_PORT=5678 \
  -e N8N_SECURE_COOKIE=false \
  n8nio/n8n:1.70.3

echo "n8n startup complete."
