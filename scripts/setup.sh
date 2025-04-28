# Setup Arbitrum directory
echo "Setting up Arbitrum directory..."
mkdir -p /home/ec2-user/.arbitrum
sudo chown -R ec2-user:ec2-user /home/ec2-user/.arbitrum

# Start socat proxy in background with logging
echo "Starting socat proxy..."
sudo socat VSOCK-LISTEN:8004,fork,keepalive TCP:127.0.0.1:2049,keepalive &

# Configure NFS exports
echo "/home/ec2-user/.arbitrum 127.0.0.1/32(rw,insecure,fsid=0,crossmnt,no_subtree_check,sync,all_squash,anonuid=1000,anongid=1000)" | sudo tee -a /etc/exports
sudo exportfs -ra
sudo systemctl enable nfs-server
sudo systemctl start nfs-server

# Verify services
echo "Verifying services..."
sudo systemctl is-active --quiet nfs-server || { echo "NFS server failed to start"; exit 1; }
pgrep -x socat >/dev/null || { echo "socat proxy not running"; exit 1; }