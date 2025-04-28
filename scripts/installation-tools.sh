#!/bin/bash

# Exit immediately on error and show commands
set -ex

# Update system packages
echo "Updating system packages..."
sudo yum update -y || { echo "ERROR: Failed to update packages"; exit 1; }

# Install Docker
echo "Installing docker..."
sudo yum install -y docker || { echo "ERROR: Failed to install docker"; exit 1; }
sudo systemctl enable docker || { echo "ERROR: Failed to enable docker"; exit 1; }
sudo systemctl start docker || { echo "ERROR: Failed to start docker"; exit 1; }
sudo usermod -aG docker ec2-user || echo "WARNING: Failed to add user to docker group"

# Install nitro-cli
echo "Installing aws-nitro-enclaves-cli..."
sudo dnf install -y aws-nitro-enclaves-cli || { echo "ERROR: Failed to install nitro-cli"; exit 1; }

# Install dev tools
echo "Installing development tools..."
sudo dnf install -y aws-nitro-enclaves-cli-devel || { echo "ERROR: Failed to install nitro-cli-devel"; exit 1; }

# Add user to ne group
sudo usermod -aG ne ec2-user || echo "WARNING: Failed to add user to ne group"

# Install socat
echo "Installing socat..."
sudo yum install -y socat || { echo "ERROR: Failed to install socat"; exit 1; }
socat -V || { echo "ERROR: socat verification failed"; exit 1; }

# Install NFS
echo "Installing NFS..."
sudo yum install -y nfs-utils || { echo "ERROR: Failed to install nfs-utils"; exit 1; }

echo "All installations completed successfully!"