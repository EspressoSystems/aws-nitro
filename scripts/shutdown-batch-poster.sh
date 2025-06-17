#!/bin/bash

MESSAGE="TERMINATE"
PORT=8005
CID_FILE="/home/ec2-user/.arbitrum/enclave_cid.log"

# Read CID from file
if [ ! -f "$CID_FILE" ]; then
    echo "Error: CID file not found at $CID_FILE"
    exit 1
fi

# Extract the CID (last number in the file)
CID=$(tail -1 "$CID_FILE" | tr -d '[:space:]')
if [[ ! "$CID" =~ ^[0-9]+$ ]]; then
    echo "Error: No valid CID found in $CID_FILE"
    exit 1
fi

echo "Attempting VSOCK connection to CID $CID, port $PORT..."

# Run socat and capture output and exit status
OUTPUT=$(echo "$MESSAGE" | socat - VSOCK-CONNECT:$CID:$PORT 2>&1)
EXIT_STATUS=$?

if echo "$OUTPUT" | grep -q "Connection timed out"; then
    echo "Connection timed out for CID $CID: $OUTPUT"
    exit 1
elif [ $EXIT_STATUS -eq 0 ]; then
    echo "Success: Connected to CID $CID, port $PORT"
    exit 0
else
    echo "Error: Connection failed for CID $CID (Exit Status: $EXIT_STATUS)"
    echo "Output: $OUTPUT"
    exit 1
fi