#!/bin/bash

MESSAGE="TERMINATE"
PORT=8005

# Get the latest CID from journal logs
CID=$(sudo journalctl -u socat-vsock.service -n 50 --no-pager | \
      grep -oP 'accepting connection from AF=40 cid:\K\d+' | \
      tail -n 1 | \
      tr -d '[:space:]')

# Validate CID
if [[ ! "$CID" =~ ^[0-9]+$ ]]; then
    echo "Error: No valid CID found in socat-vsock.service logs"
    exit 1
fi

echo "Attempting VSOCK connection to CID $CID, port $PORT..."

# Run socat and capture output and exit status
OUTPUT=$(echo "$MESSAGE" | socat - VSOCK-CONNECT:$CID:$PORT 2>&1)
EXIT_STATUS=$?

# Handle connection results
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