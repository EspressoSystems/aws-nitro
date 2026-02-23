# syntax=docker/dockerfile:1
# Multi-stage build: Create EIF from op-batcher-tee, package for AWS Nitro

# ============================================================================
# Stage 1: Build the EIF from pre-built op-batcher-tee image
# ============================================================================
FROM ubuntu:22.04 AS eif-builder

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    docker.io \
    grep \
    sed \
    && rm -rf /var/lib/apt/lists/*

# Install enclaver
ARG ENCLAVER_VERSION=v1.1.5
RUN curl -L "https://github.com/edgebitio/enclaver/releases/download/${ENCLAVER_VERSION}/enclaver-linux-amd64" \
    -o /usr/local/bin/enclaver && \
    chmod +x /usr/local/bin/enclaver

# Build arguments
ARG SOURCE_IMAGE=ghcr.io/espressosystems/optimism-espresso-integration/op-batcher-tee:latest
ARG ENCLAVE_NAME=op-batcher-enclave
ARG CPU_COUNT=2
ARG MEMORY_MB=4096

# Create enclaver manifest
RUN cat > /tmp/manifest.yaml <<EOF
version: v1
name: ${ENCLAVE_NAME}
target: ${ENCLAVE_NAME}
sources:
  app: ${SOURCE_IMAGE}
defaults:
  cpu_count: ${CPU_COUNT}
  memory_mb: ${MEMORY_MB}
egress:
  proxy_port: 10000
  allow:
    - "0.0.0.0/0"
    - "**"
    - "::/0"
ingress:
  - listen_port: 8337
EOF

# Build the EIF and extract measurements
RUN --mount=type=bind,from=docker,source=/var/run/docker.sock,target=/var/run/docker.sock \
    set -x && \
    enclaver build --file /tmp/manifest.yaml 2>&1 | tee /tmp/build_output.log && \
    grep -m1 -oE 'PCR0[=:][[:space:]]*(0x)?[[:xdigit:]]{64,}' /tmp/build_output.log \
    | sed -E 's/^PCR0[=:][[:space:]]*(0x)?//' > /tmp/pcr0.txt && \
    echo "PCR0: $(cat /tmp/pcr0.txt)" && \
    ls -lah /root/.cache/enclaver/images/

# ============================================================================
# Stage 2: Runtime image - based on SOURCE_IMAGE to reuse enclave-tools
# ============================================================================
FROM ${SOURCE_IMAGE}

# Switch to root for setup
USER root

# Install additional runtime dependencies (if needed)
RUN apk add --no-cache docker-cli

# Copy the pre-built EIF file
COPY --from=eif-builder /root/.cache/enclaver/images/*.eif /opt/enclave/
COPY --from=eif-builder /tmp/pcr0.txt /opt/enclave/

# Copy wrapper entrypoint
COPY scripts/nitro-entrypoint.sh /opt/enclave/
RUN chmod +x /opt/enclave/nitro-entrypoint.sh

# Expose PCR0 as metadata
ARG PCR0
ENV ENCLAVE_PCR0=${PCR0}
LABEL enclave.pcr0=${PCR0}
LABEL enclave.name=${ENCLAVE_NAME}
LABEL enclave.source_image=${SOURCE_IMAGE}
LABEL org.opencontainers.image.title="OP Batcher AWS Nitro Enclave"
LABEL org.opencontainers.image.description="Pre-built AWS Nitro Enclave image for OP Stack Batcher"

WORKDIR /opt/enclave

# Use wrapper entrypoint
ENTRYPOINT ["/opt/enclave/nitro-entrypoint.sh"]
CMD ["run"]