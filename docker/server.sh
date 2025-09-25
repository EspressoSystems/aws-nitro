#!/bin/bash

set -e
while read -r message; do
    if [ "$message" = "TERMINATE" ]; then
        echo "Received TERMINATE signal"
        pkill -INT -f "/usr/local/bin/nitro"
    elif [ "$message" = "STATS" ]; then
        echo "=== STATS ==="
        echo "=== ENCLAVE MEM ==="
        free -h | awk '/Mem:/ {printf "Total: %s, Used: %s, Free: %s, Available: %s\n", $2, $3, $4, $7}'
        echo "=== SOCAT ==="
        pgrep -f "socat.*TCP-LISTEN:2049" || { echo "socat not running"; }
        echo "=== NITRO PID ==="
        nitro_pid=$(pgrep -f "/usr/local/bin/nitro" || echo "none")
        if [ "$nitro_pid" = "none" ]; then
            echo "nitro not running"
        else
            echo "$nitro_pid"
            echo "=== NITRO MEM ==="
            ps -p "$nitro_pid" -o rss --no-headers | awk '{printf "Memory Used: %.2f MB\n", $1/1024}'
        fi  
    else
        echo "Ignoring message: $message"
    fi
done