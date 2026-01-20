#!/bin/bash

set -e

echo "Using config hash: $EXPECTED_CONFIG_SHA256"

ENCLAVE_CONFIG_SOURCE_DIR=/mnt/config        # temporary mounted directory in enclave to read config from parent instance
PARENT_SOURCE_CONFIG_DIR=/opt/nitro/config   # config path on parent directory
ENCLAVE_CONFIG_TARGET_DIR=/config            # directory to copy config contents to inside enclave
PARENT_SOURCE_DB_DIR=/opt/nitro/arbitrum     # database path on parent directory
ENV_FILE="${ENCLAVE_CONFIG_TARGET_DIR}/.env" # env variables file including ETH wallet private key

echo "Set memory"
echo 'net.ipv4.tcp_rmem = 4096 87380 16777216' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_wmem = 4096 87380 16777216' >> /etc/sysctl.conf
echo 'net.core.rmem_max = 16777216' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 16777216' >> /etc/sysctl.conf
sysctl -p

echo "Start vsock proxy"
socat -b65536 TCP-LISTEN:2049,bind=127.0.0.1,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8004,keepalive,rcvbuf-late=16384,sndbuf-late=16384 >/dev/null 2>&1 &
sleep 2

echo "Mount config from ${PARENT_SOURCE_CONFIG_DIR} to ${ENCLAVE_CONFIG_SOURCE_DIR}"
mount -t nfs4 "127.0.0.1:${PARENT_SOURCE_CONFIG_DIR}" "${ENCLAVE_CONFIG_SOURCE_DIR}"

echo "Checking Mounts:"
mount -t nfs4

echo "Copying config files from ${ENCLAVE_CONFIG_SOURCE_DIR} to ${ENCLAVE_CONFIG_TARGET_DIR}"
if ! cp -a "${ENCLAVE_CONFIG_SOURCE_DIR}/." "${ENCLAVE_CONFIG_TARGET_DIR}/"; then
    echo "ERROR: Failed to copy config files"
    exit 1
fi

# Verify files were copied
if [ -z "$(ls -A "${ENCLAVE_CONFIG_TARGET_DIR}")" ]; then
    echo "ERROR: No files were copied to target directory"
    exit 1
fi

# Unmount config as we copied files out of mnt directory
echo "Unmounting config"
umount "${ENCLAVE_CONFIG_SOURCE_DIR}"

CONFIG_SHA=$(jq -cS {chain} "$ENCLAVE_CONFIG_TARGET_DIR/poster_config.json" | sha256sum | cut -d' ' -f1) || {
    echo "ERROR: Failed to calculate config sha256"
    exit 1
}

if [ "$CONFIG_SHA" != "$EXPECTED_CONFIG_SHA256" ]; then
    echo "ERROR: Config sha256 mismatch"
    echo "Expected: $EXPECTED_CONFIG_SHA256"
    echo "Actual:   $CONFIG_SHA"
    exit 1
fi

if [ -f "${ENV_FILE}" ]; then
    echo "Loading environment variables from ${ENV_FILE}"
    set -a
    source "${ENV_FILE}"
    set +a
fi

echo "Config sha256 verified"

echo "Starting vsock server"
socat VSOCK-LISTEN:8005,fork,keepalive SYSTEM:./server.sh &
sleep 5

echo "Mount NFS database from ${PARENT_SOURCE_DB_DIR}"
mount -t nfs4 -o rsize=16384,wsize=16384 "127.0.0.1:${PARENT_SOURCE_DB_DIR}" "/home/user/.arbitrum"

echo "Checking Mounts:"
mount -t nfs4

# TODO: All configurable values to be passed in command line
exec /usr/local/bin/nitro \
  --validation.wasm.enable-wasmroots-check=false \
  --conf.file "${ENCLAVE_CONFIG_TARGET_DIR}/poster_config.json" \
  --node.batch-poster.parent-chain-wallet.private-key="${PRIVATE_KEY}" \ 
  | while IFS= read -r line; do [ ${#line} -gt 4096 ] && echo "${line:0:4076}... [line truncated]" || echo "$line"; done
