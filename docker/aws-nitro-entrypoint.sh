#!/bin/bash

set -e

echo "Using config hash: $EXPECTED_CONFIG_SHA256"

ENCLAVE_CONFIG_SOURCE_DIR=/mnt/config # temporary mounted directory in enclave to read config from parent instance
PARENT_SOURCE_CONFIG_DIR=/home/ec2-user/config # config path on parent directory
ENCLAVE_CONFIG_TARGET_DIR=/config # directory to copy config contents to inside enclave
PARENT_SOURCE_DB_DIR=/home/ec2-user/.arbitrum # database path on parent directory

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
    echo "ERROR: Failed to calculate config sha256"
    exit 1
}

CONFIG_FILE="${ENCLAVE_CONFIG_TARGET_DIR}/config-verification.json"
BYPASS=false
if [ -f "${CONFIG_FILE}" ]; then
    if jq -e '.bypass == true' "${CONFIG_FILE}" >/dev/null 2>&1; then
        echo "WARNING: Bypass flag is set to true in config-verification.json"
        BYPASS=true
    fi
fi

if [ "$BYPASS" != true ] && [ "$CONFIG_SHA" != "$EXPECTED_CONFIG_SHA256" ]; then
    echo "ERROR: Config sha256 mismatch"
    echo "Expected: $EXPECTED_CONFIG_SHA256"
    echo "Actual:   $CONFIG_SHA"
    exit 1
fi

echo "Config sha256 verified"

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