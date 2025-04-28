#!/bin/bash

set -e

echo "Start vsock proxy"
socat TCP-LISTEN:2049,bind=127.0.0.1,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8004,keepalive &
sleep 2

echo "Mount NFS"
mount -t nfs4 127.0.0.1:/ /home/user/.arbitrum

echo "Starting tcp listener on port 8005 for INT signal"
start_vsock_termination_server() {
    socat VSOCK-LISTEN:8005,fork,keepalive SYSTEM:'
        while read -r message; do
            if [ "$message" = "TERMINATE" ]; then
                echo "Received TERMINATE signal"
                pkill -INT -f "/usr/local/bin/nitro"
                break
            else
                echo "Ignoring message: $message"
            fi
        done
    '
}

start_vsock_termination_server &

# Start Nitro process
exec /usr/local/bin/nitro \
  --validation.wasm.enable-wasmroots-check=false \
  --conf.file /config/poster_config.json 