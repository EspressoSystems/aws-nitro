# Batch Poster in AWS Nitro

This repository builds reproducible Enclave Image Files (EIF) for AWS Nitro Enclaves using [nix-enclaver](https://github.com/joshdoman/nix-enclaver).

## Repository Structure

- `docker/` - Dockerfile and entrypoint scripts for the enclave
- `enclaver/` - Configuration for Enclaver
- `nix/` - Nix expressions for reproducible builds
- `scripts/` - EC2 instance setup scripts

## CI Workflow

The GitHub Actions workflow builds reproducible EIFs with consistent PCR0 hashes.

### Inputs

- `config_hash` - SHA256 hash of the batch poster config
- `nitro_node_image_path` - Docker image path (e.g., `ghcr.io/espressosystems/nitro-espresso-integration/nitro-node:v3.5.6`)

### Get Config Hash

```shell
jq -cS . "path/to/poster_config.json" | sha256sum | cut -d' ' -f1
```

### Run Workflow

1. Go to **Actions** → **Build Reproducible EIF**
2. Click **Run workflow**
3. Enter the config hash and nitro image path
4. The workflow outputs:
   - `PCR0` - The enclave measurement
   - `Enclave Hash` - Keccak hash of PCR0 for on-chain use

## Local Development

```shell
# Enter dev shell
nix develop

# Build EIF (requires Linux or Linux builder)
nix build '.#x86_64-eif'
```

## EC2 Setup

```shell
cd scripts
./installation-tools.sh
./setup-ec2-instance.sh
sudo enclaver run enclaver-batch-poster:latest -p 8547:8547
./shutdown-batch-poster.sh
```
