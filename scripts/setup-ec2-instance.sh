#!/bin/bash

# Exit immediately if any command fails
set -e

# Setup Arbitrum directory
echo "Setting up Arbitrum db directory..."
mkdir -p /home/ec2-user/.arbitrum || { echo "Failed to create .arbitrum directory"; exit 1; }
sudo chown -R ec2-user:ec2-user /home/ec2-user/.arbitrum || { echo "Failed to set permissions for .arbitrum"; exit 1; }

# Setup config directory
echo "Setting up config directory..."
mkdir -p /home/ec2-user/config || { echo "Failed to create config directory"; exit 1; }
sudo chown -R ec2-user:ec2-user /home/ec2-user/config || { echo "Failed to set permissions for config"; exit 1; }

# Start socat proxy in background with logging
echo "Starting socat proxy..."
sudo socat VSOCK-LISTEN:8004,fork,keepalive TCP:127.0.0.1:2049,keepalive &

# Configure NFS exports
echo "/home/ec2-user/.arbitrum 127.0.0.1/32(rw,insecure,crossmnt,no_subtree_check,sync,all_squash,anonuid=1000,anongid=1000)" | sudo tee -a /etc/exports || { echo "Failed to configure NFS exports"; exit 1; }
echo "/home/ec2-user/config 127.0.0.1/32(ro,insecure,crossmnt,no_subtree_check,sync,all_squash,anonuid=1000,anongid=1000)" | sudo tee -a /etc/exports || { echo "Failed to configure NFS exports"; exit 1; }
sudo exportfs -ra || { echo "Failed to reload NFS exports"; exit 1; }

# Enable and start NFS server
sudo systemctl enable nfs-server || { echo "Failed to enable NFS server"; exit 1; }
sudo systemctl start nfs-server || { echo "Failed to start NFS server"; exit 1; }

# Verify services
echo "Verifying services..."
sudo systemctl is-active --quiet nfs-server || { echo "ERROR: NFS server not running"; exit 1; }
pgrep -x socat >/dev/null || { echo "ERROR: socat process not found"; exit 1; }

sudo sed -i \
  -e '/^cpu_count:/s/:.*$/: 4/' \
  -e '/^memory_mib:/s/:.*$/: 8192/' \
  "/etc/nitro_enclaves/allocator.yaml"

sudo systemctl enable --now nitro-enclaves-allocator.service

echo "All services configured successfully!"