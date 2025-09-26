#!/bin/bash

set -e
while read -r message; do
    if [ "$message" = "TERMINATE" ]; then
        echo "Received TERMINATE signal"
        pkill -INT -f "/usr/local/bin/nitro"
    elif [ "$message" = "TERMINATE_SOCAT" ]; then
        echo "Received TERMINATE_SOCAT signal"
        pkill -KILL -f "socat.*TCP-LISTEN:2049" || echo "Failed to kill socat"
        socat -d -d TCP-LISTEN:2049,bind=127.0.0.1,fork,reuseaddr,keepalive VSOCK-CONNECT:3:8004,keepalive,retry=10,interval=2 >>/home/user/.arbitrum/socat.log 2>&1 &
    elif [ "$message" = "KILL_NITRO" ]; then
        echo "Received KILL_NITRO signal"
        echo "Attempting SIGTERM for nitro..."
        pkill -TERM -f "/usr/local/bin/nitro" || {
            echo "SIGTERM failed, attempting SIGKILL..."
            pkill -KILL -f "/usr/local/bin/nitro" || echo "Failed to kill nitro"
        }
        sleep 2
        if pgrep -f "/usr/local/bin/nitro" > /dev/null; then
            echo "Nitro still running after pkill"
        else
            echo "Nitro terminated"
        fi
    elif [ "$message" = "ADVANCED_KILL" ]; then
        echo "Received ADVANCED_KILL signal"
        nitro_pid=$(pgrep -f "/usr/local/bin/nitro" || echo "none")
        if [ "$nitro_pid" = "none" ]; then
            echo "Nitro not running"
            continue
        fi
        echo "Targeting PID $nitro_pid"
        for signal in TERM HUP QUIT KILL; do
            echo "Attempting SIG$signal..."
            kill -"$signal" "$nitro_pid" 2>/dev/null || echo "SIG$signal failed"
            sleep 1
            if ! kill -0 "$nitro_pid" 2>/dev/null; then
                echo "Nitro terminated with SIG$signal"
                break
            fi
        done
        if kill -0 "$nitro_pid" 2>/dev/null; then
            echo "Nitro still running after all signals"
        fi
    elif [ "$message" = "STATS" ]; then
        echo "=== STATS ==="
        echo "=== ENCLAVE MEM ==="
        free -h | awk '/Mem:/ {printf "Total: %s, Used: %s, Free: %s, Available: %s\n", $2, $3, $4, $7}'
        echo "=== ENCLAVE CPU ==="
        top -bn1 | grep "%Cpu(s)" | awk '{printf "CPU Usage: %.1f%% (User: %.1f%%, System: %.1f%%)\n", $2 + $4, $2, $4}'
        echo "=== SOCAT ==="
        pgrep -f "socat.*TCP-LISTEN:2049" || { echo "socat not running"; }
        echo "=== SOCAT LOGS ==="
        tail -30 cat /tmp/socat.log
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
    else
        echo "Ignoring message: $message"
    fi
done