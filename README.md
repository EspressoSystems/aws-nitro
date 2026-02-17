# AWS Nitro Enclaves Multi-Stack Repository

This repository contains configurations and workflows for running different stacks in AWS Nitro Enclaves.

## Repository Structure

- `nitro/`: Arbitrum Nitro batch poster implementation
- `op/`: OP Stack implementation (coming soon)
- `.github/workflows/`: CI/CD workflows for building enclave images

## Nitro Stack

The Nitro stack enables the creation of an `Enclave Image File (EIF)` from a specified Nitro Node image for use in AWS Nitro Enclaves. By providing the SHA256 hash of the configuration and specifying the Nitro image, the tool generates a Dockerfile incorporating the resulting EIF file. This process, facilitated by [Enclaver](https://github.com/enclaver-io/enclaver), will provide network connectivity between our enclave and the outside world.

### Nitro Directory Structure

- `nitro/docker`: Contains the Dockerfile that pulls the Nitro Node image and configures a Docker image, which is then converted into an Enclave Image File (EIF).
- `nitro/enclaver`: Configuration for the [Enclaver](https://github.com/enclaver-io/enclaver) tool, generating a Docker image that includes the EIF file.
- `nitro/scripts`: Includes scripts to install, and run the tools needed on the parent EC2 instance, preparing it to run and communicate with the Batch Poster within the enclave.

## Workflow Prerequisites
To run this workflow you need the latest nitro image tag as well as the sha256 hash of the batch poster config. To get the hash of the batch poster config run:
```shell
jq -cS . "path/to/poster_config.json" | sha256sum | cut -d' ' -f1
```

### Nitro Scripts
To run the scripts you can clone this repository and cd into the Nitro scripts directory:
```shell
cd aws-nitro/nitro/scripts
```
Next install the tools needed on the parent instance:
```shell
./installation-tools.sh
```

Then you can setup and run the tools needed on the EC2 Instance by running:
```shell
./setup-ec2-instance.sh
```

Finally, you can start the enclaver. First, edit `../docker/docker-compose.yml` to uncomment the `image` line and provide your image tag:
```yaml
image: ghcr.io/espressosystems/aws-nitro-poster:<created-docker-tag>
```

Then, from the `nitro/scripts` directory, run:
```shell
(cd ../docker && docker pull ghcr.io/espressosystems/aws-nitro-poster:<created-docker-tag> && docker compose up -d)
```

To safely shut down the batch poster and ensure we write state to the database, run the following command from the `nitro/scripts` directory:
```shell
./shutdown-batch-poster.sh
```
