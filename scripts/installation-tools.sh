#!/bin/bash

# Exit on error and trace commands
set -e
set -x

# Update system packages
sudo yum update -y

# Install Docker
echo "Installing docker..."
sudo yum install -y docker
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user

# Install nitro-cli
sudo dnf install aws-nitro-enclaves-cli -y

# Install dev tools
sudo dnf install aws-nitro-enclaves-cli-devel -y

# Add user to ne group
sudo usermod -aG ne ec2-user

# Add user to docker group
sudo usermod -aG docker ec2-user

# Install and configure socat
echo "Installing socat..."
sudo yum install -y socat
socat -V || { echo "socat installation failed"; exit 1; }

# Install and configure NFS
echo "Installing NFS..."
sudo yum install -y nfs-utils