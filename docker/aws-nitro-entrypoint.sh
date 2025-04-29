#!/bin/bash

set -e

echo "Start vsock proxy"
socat TCP-LISTEN:2049,bind=127.0.0.1,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8004,keepalive &
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

CONFIG_SHA=$(jq -cS . "$ENCLAVE_CONFIG_TARGET_DIR/poster_config.json" | sha256sum | cut -d' ' -f1) || {
    echo "ERROR: Failed to calculate config checksum"
    exit 1
}
EXPECTED_CONFIG_SHA256=""
if [ "$CONFIG_SHA" != "$EXPECTED_CONFIG_SHA256" ]; then
    echo "ERROR: Config checksum mismatch"
    echo "Expected: $EXPECTED_CONFIG_SHA256"
    echo "Actual:   $CONFIG_SHA"
    exit 1
fi

echo "Config checksum verified"

echo "Mount NFS database from ${PARENT_SOURCE_DB_DIR}"
mount -t nfs4 "127.0.0.1:${PARENT_SOURCE_DB_DIR}" "/home/user/.arbitrum"

echo "Checking Mounts:"
mount -t nfs4

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

exec /usr/local/bin/nitro \
  --validation.wasm.enable-wasmroots-check=false \
  --conf.file "${ENCLAVE_CONFIG_TARGET_DIR}/poster_config.json"