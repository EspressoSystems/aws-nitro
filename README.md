# Batch Poster in AWS Nitro
This tool enables the creation of an `Enclave Image File (EIF)` from a specified Nitro Node image for use in AWS Nitro Enclaves. By providing the SHA256 hash of the configuration and specifying the Nitro image, the tool generates a Dockerfile incorporating the resulting EIF file. This process, facilitated by [Enclaver](https://github.com/enclaver-io/enclaver), will provide network connectivity between our enclave and the outside world. The layout of the repository is as follows:

- `docker`: Contains the Dockerfile that pulls the Nitro Node image and configures a Docker image, which is then converted into an Enclave Image File (EIF).
- `enclaver`: Configuration for the [Enclaver](https://github.com/enclaver-io/enclaver) tool, generating a Docker image that includes the EIF file.
- `scripts`: Includes scripts to install, and run the tools needed on the parent EC2 instance, preparing it to run and communicate with the Batch Poster within the enclave.

## Workflow Prerequisites
To run this workflow you need the latest nitro image tag as well as the sha256 hash of the batch poster config. To get the hash of the batch poster config run:
```shell
jq -cS . "path/to/poster_config.json" | sha256sum | cut -d' ' -f1
```

## CI Testing

The GitHub Actions workflow now uses Nix for reproducible builds. To test enclave hash consistency:

1. Push this branch
2. Go to Actions → "Build Enclaver Docker Image"
3. Click "Run workflow" twice with the same inputs:
   - `config_hash`: SHA256 of your poster config JSON
   - `nitro_node_image_path`: `ghcr.io/espressosystems/nitro-espresso-integration/nitro-node:xxx`
4. Compare the `ENCLAVE_HASH` outputs - they should be identical

**Note**: PCR0 hash extraction bypasses config verification for testing (uses `{"bypass": true}` in runtime config).

## Scripts
To run the scripts you can clone this repository and cd into scripts directory:
```shell
cd aws-nitro/scripts
```
Next install the tools needed on the parent instance:
```shell
./installation-tools.sh
```

Then you can setup and run the tools needed on the EC2 Instance by running:
```shell
./setup-ec2-instance.sh
```

Finally you can start the enclaver by using the enclaver run command:
```shell
sudo enclaver run enclaver-batch-poster-<BRANCH_NAME>:latest -p 8547:8547
```

To safely shut down the batch poster and ensure we write state to the database you need to use the following command:
```shell
./shutdown-batch-poster.sh
```
