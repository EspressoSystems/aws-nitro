#!/bin/bash
set -e
while true; do
  echo "Starting socat at \$(date)" >> /tmp/socat.log
  /usr/bin/socat -d -d -d -d -T5 TCP-LISTEN:2049,bind=127.0.0.1,reuseaddr,rcvbuf=65536,sndbuf=65536 VSOCK-CONNECT:3:8004,rcvbuf=65536,sndbuf=65536 &> /tmp/socat.log
  echo "socat exited with \$? at \$(date), restarting in 10 seconds" >> /tmp/socat.log
  sleep 10
done