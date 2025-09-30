#!/bin/bash

set -e
while read -r message; do
    if [ "$message" = "TERMINATE" ]; then
        echo "Received TERMINATE signal"
        pkill -INT -f "/usr/local/bin/nitro"
    elif [ "$message" = "TERMINATE_SOCAT" ]; then
        echo "Received TERMINATE_SOCAT signal"
        pkill -KILL -f "socat.*TCP-LISTEN:2049" || echo "Failed to kill socat"
        socat -d -d -d -d -b131072 -T30 TCP-LISTEN:2049,bind=127.0.0.1,fork,reuseaddr,so-keepalive,keepidle=60,keepintvl=30,keepcnt=5,rcvbuf=524288,sndbuf=524288,max-children=5 VSOCK-CONNECT:3:8004,so-keepalive,connect-timeout=10,retry=5,interval=5 &> /tmp/socat.log &
    elif [ "$message" = "STATS" ]; then
        echo "=== STATS ==="
        echo "=== ENCLAVE MEM ==="
        free -h | awk '/Mem:/ {printf "Total: %s, Used: %s, Free: %s, Available: %s\n", $2, $3, $4, $7}'
        echo "=== ENCLAVE CPU ==="
        top -bn1 | grep "%Cpu(s)" | awk '{printf "CPU Usage: %.1f%% (User: %.1f%%, System: %.1f%%)\n", $2 + $4, $2, $4}'
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
            echo "=== NITRO STATE ==="
            ps -p "$nitro_pid" -o state,cmd --no-headers || echo "No state info"
            echo "=== NITRO CPU ==="
            ps -p "$nitro_pid" -o %cpu --no-headers | awk '{printf "CPU Used: %.2f%%\n", $1}'
        fi
    elif [ "$message" = "LOG" ]; then
        tail -n 100 /tmp/socat.log
    else
        echo "Ignoring message: $message"
    fi
done