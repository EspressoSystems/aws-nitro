MESSAGE="TERMINATE"
PORT=8005
echo "Starting VSOCK connection attempts at CID $CID, port $PORT..."
CID=16
MAX_CID=100
# When running inside the enclaver it is not possible to get enclave context id
# Which is why we have to have this script incrementing the $CID
# See issue: https://github.com/enclaver-io/enclaver/issues/215
while [ $CID -le $MAX_CID ]; do
    echo "Trying CID $CID..."
    
    # Run socat and capture output and exit status
    OUTPUT=$(echo "$MESSAGE" | socat - VSOCK-CONNECT:$CID:$PORT 2>&1)
    EXIT_STATUS=$?
    
    # Check if the output contains "Connection timed out"
    if echo "$OUTPUT" | grep -q "Connection timed out"; then
        echo "Connection timed out for CID $CID: $OUTPUT"
        # Increment CID and continue
        CID=$((CID + 1))
    else
        # Success or different error
        echo "Connection attempt for CID $CID completed with exit status $EXIT_STATUS"
        echo "Output: $OUTPUT"
        if [ $EXIT_STATUS -eq 0 ]; then
            echo "Success: Connected to CID $CID, port $PORT"
            break
        else
            echo "Non-timeout error occurred for CID $CID. Stopping."
            break
        fi
    fi
done

if [ $CID -gt $MAX_CID ]; then
    echo "Reached maximum CID ($MAX_CID) without success."
    exit 1
fi

exit 0