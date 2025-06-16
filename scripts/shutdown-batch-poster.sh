#!/bin/bash

MESSAGE="TERMINATE"
PORT=8005

if [ $# -ne 1 ]; then
    echo "Usage: $0 <CID>"
    exit 1
fi

CID=$1

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