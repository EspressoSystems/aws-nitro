#!/bin/bash
# Nitro Enclave Wrapper Entrypoint
# Delegates to enclave-tools from the base op-batcher-tee image

set -e

# Read pre-built PCR0
PCR0=$(cat /opt/enclave/pcr0.txt)
EIF_PATH="/opt/enclave/op-batcher-enclave.eif"

# Command routing
case "${1:-run}" in
  "pcr0")
    # Print PCR0 value
    echo "$PCR0"
    exit 0
    ;;
    
  "info")
    # Print enclave information
    echo "=== Enclave Information ==="
    echo "PCR0: $PCR0"
    echo "EIF Path: $EIF_PATH"
    echo "Source Image: ${SOURCE_IMAGE:-unknown}"
    if [ -f "$EIF_PATH" ]; then
      echo "EIF Size: $(du -h $EIF_PATH | cut -f1)"
    else
      echo "WARNING: EIF file not found at $EIF_PATH"
    fi
    echo "=========================="
    exit 0
    ;;
    
  "register")
    # Register PCR0 with BatchAuthenticator contract
    # Delegates to enclave-tools from base image
    echo "═══════════════════════════════════════════════════════════"
    echo "PCR0 Registration"
    echo "═══════════════════════════════════════════════════════════"
    echo "PCR0: $PCR0"
    echo ""
    
    # Validate required environment variables
    : ${BATCH_AUTHENTICATOR_ADDRESS:?Error: BATCH_AUTHENTICATOR_ADDRESS is required}
    : ${L1_RPC_URL:?Error: L1_RPC_URL is required}
    : ${OPERATOR_PRIVATE_KEY:?Error: OPERATOR_PRIVATE_KEY is required}
    
    echo "Authenticator: $BATCH_AUTHENTICATOR_ADDRESS"
    echo "L1 RPC URL: $L1_RPC_URL"
    echo ""
    
    # Delegate to enclave-tools from the base image
    exec enclave-tools register \
      --authenticator "$BATCH_AUTHENTICATOR_ADDRESS" \
      --l1-url "$L1_RPC_URL" \
      --private-key "$OPERATOR_PRIVATE_KEY" \
      --pcr0 "$PCR0"
    ;;
    
  "is-registered"|"verify")
    # Check if PCR0 is registered (read-only)
    : ${BATCH_AUTHENTICATOR_ADDRESS:?Error: BATCH_AUTHENTICATOR_ADDRESS is required}
    : ${L1_RPC_URL:?Error: L1_RPC_URL is required}
    
    echo "Verifying PCR0 registration..."
    echo "PCR0: $PCR0"
    echo "Authenticator: $BATCH_AUTHENTICATOR_ADDRESS"
    echo ""
    
    # Delegate to enclave-tools from the base image
    if enclave-tools is-registered \
        --authenticator "$BATCH_AUTHENTICATOR_ADDRESS" \
        --l1-url "$L1_RPC_URL" \
        --pcr0 "$PCR0"; then
      echo "✓ PCR0 is registered"
      exit 0
    else
      echo "✗ PCR0 is NOT registered"
      echo ""
      echo "Register it with:"
      echo "  docker run --rm \\"
      echo "    -e BATCH_AUTHENTICATOR_ADDRESS=$BATCH_AUTHENTICATOR_ADDRESS \\"
      echo "    -e L1_RPC_URL=$L1_RPC_URL \\"
      echo "    -e OPERATOR_PRIVATE_KEY=<key> \\"
      echo "    <image> register"
      exit 1
    fi
    ;;
    
  "run")
    # Run the enclave
    echo "=== Starting AWS Nitro Enclave ==="
    echo "PCR0: $PCR0"
    echo "EIF: $EIF_PATH"
    
    # Validate required environment variables
    : ${L1_RPC_URL:?Error: L1_RPC_URL is required}
    : ${L2_RPC_URL:?Error: L2_RPC_URL is required}
    : ${ROLLUP_RPC_URL:?Error: ROLLUP_RPC_URL is required}
    : ${ESPRESSO_URL1:?Error: ESPRESSO_URL1 is required}
    : ${ESPRESSO_ATTESTATION_SERVICE_URL:?Error: ESPRESSO_ATTESTATION_SERVICE_URL is required}
    : ${EIGENDA_PROXY_URL:?Error: EIGENDA_PROXY_URL is required}
    
    # Verify PCR0 is registered (if authenticator provided)
    if [ -n "$BATCH_AUTHENTICATOR_ADDRESS" ]; then
      echo "Verifying PCR0 registration..."
      
      if enclave-tools is-registered \
          --authenticator "$BATCH_AUTHENTICATOR_ADDRESS" \
          --l1-url "$L1_RPC_URL" \
          --pcr0 "$PCR0"; then
        echo "✓ PCR0 verified as registered"
      else
        echo ""
        echo "ERROR: PCR0 is NOT registered!"
        echo ""
        echo "Register it first with:"
        echo "  docker run --rm \\"
        echo "    -e BATCH_AUTHENTICATOR_ADDRESS=$BATCH_AUTHENTICATOR_ADDRESS \\"
        echo "    -e L1_RPC_URL=$L1_RPC_URL \\"
        echo "    -e OPERATOR_PRIVATE_KEY=<key> \\"
        echo "    $(docker inspect --format='{{index .Config.Image}}' $(hostname)) register"
        exit 1
      fi
    else
      echo "⚠ WARNING: BATCH_AUTHENTICATOR_ADDRESS not set"
      echo "⚠ Skipping PCR0 verification (testing mode only!)"
    fi
    
    # Check EIF exists
    if [ ! -f "$EIF_PATH" ]; then
      echo "ERROR: EIF file not found at $EIF_PATH"
      exit 1
    fi
    
    echo ""
    echo "Launching enclave container..."
    
    # Run the enclave
    CONTAINER_NAME="batcher-enclave-$(date +%s)"
    docker run \
      --rm \
      -d \
      --privileged \
      --net=host \
      --device=/dev/nitro_enclaves \
      --name="$CONTAINER_NAME" \
      "$EIF_PATH" || {
        echo "ERROR: Failed to start enclave container"
        exit 1
      }
    
    echo "✓ Enclave container started: $CONTAINER_NAME"
    
    # Wait for enclave to initialize
    echo "Waiting for enclave to initialize..."
    sleep 5
    
    # Check if container is still running
    if ! docker ps --format '{{.Names}}' | grep -q "$CONTAINER_NAME"; then
      echo "ERROR: Enclave container exited unexpectedly"
      docker logs "$CONTAINER_NAME" 2>&1 || true
      exit 1
    fi
    
    echo "✓ Enclave is running"
    echo ""
    echo "Monitoring enclave logs..."
    
    # Follow logs
    docker logs -f "$CONTAINER_NAME"
    ;;
    
  *)
    echo "Unknown command: $1"
    echo ""
    echo "Available commands:"
    echo "  pcr0         - Print the PCR0 measurement"
    echo "  info         - Show enclave information"
    echo "  register     - Register PCR0 with BatchAuthenticator (requires OPERATOR_PRIVATE_KEY)"
    echo "  is-registered - Check if PCR0 is registered (alias: verify)"
    echo "  run          - Run the enclave (default)"
    echo ""
    echo "Examples:"
    echo "  docker run <image> pcr0"
    echo "  docker run <image> info"
    echo "  docker run -e OPERATOR_PRIVATE_KEY=... <image> register"
    echo "  docker run <image> verify"
    echo "  docker run <image> run"
    exit 1
    ;;
esac