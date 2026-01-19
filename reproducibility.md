# The Problem

AWS Nitro Enclaves use PCR (Platform Configuration Register) values for attestation. PCR0 is a SHA-384 hash of the entire enclave image. For security-critical applications, you need:

1. **Reproducibility**: Same source code → same PCR0 every time
2. **Verifiability**: Anyone can rebuild and verify they get the same measurement

Traditional Docker-based builds fail this because:

- Docker images contain timestamps in layer metadata
- `apt-get` produces non-deterministic file ordering
- Base image tags can resolve to different digests over time

## The Solution: nix-enclaver

[nix-enclaver](https://github.com/joshdoman/nix-enclaver) uses the Nix package manager to create bit-for-bit reproducible enclave images. Given the same inputs (pinned in `flake.lock`), the output is always identical.

---

## Challenges Faced

Achieving reproducible builds for AWS Nitro Enclaves required solving several interconnected problems:

### Challenge 1: Docker Builds Are Inherently Non-Reproducible

The original workflow used `docker build` + `enclaver build`:

```bash
docker build -t nitro-image .
enclaver build --file enclaver.yaml
```

This produced different PCR0 values on each run because:

| Source of Non-Determinism | Impact |
|---------------------------|--------|
| Docker layer timestamps | Each layer has build-time metadata |
| `apt-get` file ordering | Package manager doesn't guarantee order |
| Base image digest drift | `:latest` or even versioned tags can change |
| Build environment variations | Different runners have different states |

### Challenge 2: nix-enclaver Expects a Nix-Built Application

nix-enclaver's `makeAppEif` function expects an `appPackage` that is a Nix derivation. But our application (nitro-node) comes from a Docker image, not from Nix.

**The solution:** Extract the binary from Docker and wrap it in a Nix derivation:

```nix
nitroBinary = pkgs.stdenv.mkDerivation {
  pname = "nitro-node";
  src = ./build-outputs/nitro;  # Extracted from Docker
  installPhase = ''
    mkdir -p $out/bin
    cp $src $out/bin/nitro
  '';
};
```

### Challenge 3: Nix Flakes Only See Git-Tracked Files

Nix flakes copy the repository to the Nix store, but only include files tracked by git. The extracted nitro binary isn't in git.

**The solution:** Stage the binary temporarily in CI:

```bash
git add -f build-outputs/nitro
git commit -m "temp: stage nitro binary"
# After build, this commit is never pushed
```

We also added `build-outputs/` to `.gitignore` to prevent accidental commits locally, using `-f` to force-add in CI.

### Challenge 4: nixpkgs Version Compatibility

nix-enclaver v0.6.1 uses Rust edition 2024 features. When we tried to pin nixpkgs to an older version (for CGO_ENABLED compatibility), the build failed:

```bash
error: feature `edition2024` is required
Cargo (1.77.1) doesn't support this feature
```

**The solution:** Don't override nix-enclaver's nixpkgs - let it use its own pinned version that includes newer Rust:

```nix
nix-enclaver = {
  url = "github:joshdoman/nix-enclaver/v0.6.1";
  # Don't add: inputs.nixpkgs.follows = "nixpkgs";
};
```

### Challenge 5: First Build Takes 60-90 Minutes

nix-enclaver builds a complete Linux kernel and GCC cross-compiler from source. On a standard GitHub Actions runner, this takes over an hour.

**Why this happens:**

- Linux kernel: ~40 minutes to compile
- GCC musl cross-compiler: ~30 minutes
- Rust toolchain: ~15 minutes
- No binary cache hits for custom kernel config

**Mitigations:**

- GitHub Actions cache (`magic-nix-cache`) stores build artifacts
- Subsequent builds reuse cached kernel/toolchain (~5 minutes)
- Cache expires after 7 days of no use
- For permanent caching, use Cachix

### Challenge 6: Disk Space on GitHub Runners

The Linux kernel + toolchain compilation exceeds the ~14GB free disk on `ubuntu-latest`:

```bash
No space left on device
```

**The solution:** Pre-build cleanup step:

```bash
sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc
sudo docker system prune -af
```

This frees ~30GB before the Nix build starts.

### Challenge 7: Extracting PCR0 from Cached Builds

When the build is cached, the PCR0 isn't printed to the build log - Nix just downloads the pre-built artifact:

```bash
copying path '/nix/store/xxx-batcher-x86_64' from cache...
```

**The solution:** nix-enclaver outputs PCR values to `pcr.json`:

```bash
PCR0=$(jq -r '.PCR0' ./pcr.json)
```

This works regardless of whether the build ran or used cache.

### Challenge 8: Deployment Approach

The original deployment used `enclaver run <docker-image>`, which internally builds its own EIF (non-reproducible). 

**Solution: nix-enclaver provides its own `enclaver` binary**

nix-enclaver includes a modified `enclaver` binary that:

- Runs the reproducible EIF directly
- Deploys the **outer proxy** automatically for network communication
- No Docker image swapping required

From the [nix-enclaver README](https://github.com/joshdoman/nix-enclaver):
> To run the EIF, run `./enclaver`. This will deploy both the Enclave image file and the outer proxy, which is needed to communicate with the enclave.

**Deployment flow:**

1. CI builds the reproducible EIF + `enclaver` binary
2. Upload both as artifacts
3. On EC2: run `./enclaver` which handles everything

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Extract binary from Docker | Nitro-node isn't available as standalone release |
| Temporary git staging | Nix flakes require git-tracked files |
| Don't override nix-enclaver's nixpkgs | Avoids Rust version conflicts |
| Read PCR0 from JSON file | Works for both fresh and cached builds |
| Use nix-enclaver's `enclaver` binary | Handles both EIF deployment and network proxy |
| Disk cleanup before build | GitHub runners have limited space |

---

## Architecture Overview

```bash
┌─────────────────────────────────────────────────────────────────┐
│                        CI Workflow                               │
├─────────────────────────────────────────────────────────────────┤
│  1. Extract nitro binary from Docker image                      │
│  2. Stage it for Nix (git add)                                  │
│  3. nix build .#x86_64-eif  → enclave.eif + pcr.json            │
│  4. nix build .#enclaver   → enclaver binary                    │
│  5. Upload all as artifacts                                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      EC2 Deployment                              │
├─────────────────────────────────────────────────────────────────┤
│  1. Download artifacts (enclave.eif, enclaver, pcr.json)        │
│  2. Run: sudo ./enclaver                                        │
│     → Deploys EIF to Nitro Enclave                              │
│     → Starts outer proxy for network communication              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        flake.nix                                 │
├─────────────────────────────────────────────────────────────────┤
│  inputs:                                                         │
│    - nixpkgs (pinned)                                           │
│    - nix-enclaver v0.6.1                                        │
│                                                                  │
│  outputs:                                                        │
│    - nitroBinary    → from build-outputs/nitro                  │
│    - appPackage     → scripts + SRS file + nitro binary         │
│    - x86_64-eif     → final enclave image                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   nix-enclaver.makeAppEif                        │
├─────────────────────────────────────────────────────────────────┤
│  Creates:                                                        │
│    - Minimal Linux kernel (built from source)                   │
│    - initramfs with the application                            │
│    - Enclaver runtime for networking                            │
│                                                                  │
│  Outputs:                                                        │
│    - batcher.eif   (the enclave image)                          │
│    - pcr.json      (PCR0, PCR1, PCR2 measurements)              │
│    - log.txt       (build log)                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## How It Works In Detail

### 1. The Nitro Binary Problem

The nitro-node binary (the application) comes from a Docker image:

```bash
ghcr.io/espressosystems/nitro-espresso-integration/nitro-node:v3.5.6-celestia-1528844
```

For Nix reproducibility, we need this binary with a **known hash**. The CI workflow:

1. Pulls the Docker image
2. Extracts `/usr/local/bin/nitro` to `build-outputs/nitro`
3. Computes its SHA-256 hash (stored as `NITRO_HASH`)
4. Stages it in git so Nix can reference it

```yaml
# From .github/workflows/build-eif.yml
CONTAINER_ID=$(docker create "${{ env.NITRO_IMAGE }}" /bin/true)
docker cp "${CONTAINER_ID}:/usr/local/bin/nitro" "build-outputs/nitro"
```

### 2. Nix Flake Structure

**`flake.nix`** defines the build:

```nix
nitroBinary = pkgs.stdenv.mkDerivation {
  pname = "nitro-node";
  version = "extracted";
  src = ./build-outputs/nitro;  # The extracted binary
  installPhase = ''
    mkdir -p $out/bin
    cp $src $out/bin/nitro
    chmod +x $out/bin/nitro
  '';
};

appPackage = pkgs.callPackage ./nix/app { inherit nitroBinary; };

x86Eif = enclaverLib.x86_64.makeAppEif {
  appPackage = appPackage;
  configFile = ./enclaver/enclaver.yaml;
};
```

### 3. Application Package

**`nix/app/default.nix`** bundles everything the enclave needs:

```nix
# Runtime dependencies (all from Nix, version-pinned)
runtimePackages = with pkgs; [
  bashInteractive coreutils findutils gnugrep gnused
  gawk jq socat procps iproute2 nettools util-linux nfs-utils
];

# SRS file (cryptographic setup, fixed hash)
srsFile = pkgs.fetchurl {
  url = "https://github.com/EspressoSystems/ark-srs/releases/download/v0.2.0/kzg10-aztec20-srs-1048584.bin";
  sha256 = "17ghkq397r1f8c093lwaah9gwm39k57kf3rfrgjgwjab5vl87vfd";
};

# Patch scripts to use Nix paths
substituteInPlace $out/bin/aws-nitro-entrypoint.sh \
  --replace "/usr/local/bin/nitro" "${nitroBinary}/bin/nitro"
```

### 4. What nix-enclaver Builds

When you run `nix build .#x86_64-eif`, nix-enclaver:

1. **Builds a Linux kernel** from source (for the enclave VM)
2. **Creates an initramfs** containing:
   - Your `appPackage` (scripts, nitro binary, SRS file)
   - All runtime dependencies (bash, coreutils, etc.)
   - The enclaver supervisor for network proxying
3. **Packages everything** into an EIF (Enclave Image File)
4. **Computes PCR values** and outputs them to `pcr.json`

The output directory contains:

```bash
/nix/store/xxxxx-batcher-x86_64/
├── batcher.eif   # The enclave image (284 MB)
├── pcr.json      # PCR measurements
└── log.txt       # Build log
```

### 5. PCR Values

`pcr.json` contains the enclave measurements:

```json
{
  "HashAlgorithm": "Sha384 { ... }",
  "PCR0": "2b6478a242d1b2a0f409defec513bc11663e522d16c6e880537b57398de55f59e24e76a44893ecf83fd51d0b46c4103e",
  "PCR1": "393ab1e602b971787d4c3fe7033e823399defd651dd573192ad71227b818ffb4408d02c9dedf182afa796b769954631f",
  "PCR2": "19347edfa1916c0fd9b6f1416c255b6d1eb3dff46f6b4306bb51d7715428eb8666460a6ac9eba1945294437caecb87a3"
}
```

- **PCR0**: Hash of the enclave image (kernel + initramfs)
- **PCR1**: Hash of the Linux kernel
- **PCR2**: Hash of the application (your code)

The CI computes `ENCLAVE_HASH = keccak256(PCR0)` for on-chain use.

---

## Why Reproducibility Works

1. **Pinned inputs**: `flake.lock` pins exact versions of nixpkgs, nix-enclaver, and all dependencies
2. **Deterministic builds**: Nix builds are pure - same inputs always produce same outputs
3. **Fixed timestamps**: `SOURCE_DATE_EPOCH=0` ensures no timestamps leak into the build
4. **Content-addressed**: The nitro binary is identified by its hash, not by mutable tags

**Rebuild guarantee**: If you run the CI twice with:

- Same git commit
- Same `nitro_node_image_path` input

You will get **identical PCR0 values**.

---

## Repository Structure

```bash
aws-nitro/
├── .github/workflows/
│   └── build-eif.yml       # CI workflow
├── docker/
│   ├── Dockerfile.aws-nitro-poster
│   ├── aws-nitro-entrypoint.sh
│   └── server.sh
├── enclaver/
│   └── enclaver.yaml       # Enclave config (memory, CPU, egress)
├── nix/
│   └── app/
│       └── default.nix     # Application package definition
├── scripts/
│   ├── installation-tools.sh
│   ├── setup-ec2-instance.sh
│   └── shutdown-batch-poster.sh
├── flake.nix               # Nix flake definition
├── flake.lock              # Pinned dependency versions
└── README.md
```

---

### Build Outputs

The workflow produces:

- **Artifacts** (downloadable from GitHub Actions):
  - `enclave.eif` - The reproducible EIF to run on EC2
  - `enclaver` - Binary that deploys EIF + outer network proxy
  - `pcr.json` - PCR0, PCR1, PCR2 measurements
  - `build-info.json` - Build metadata (source image, hashes, git SHA)
- **Logs**: PCR0 and ENCLAVE_HASH are printed in the workflow summary

---

## Caching

First build takes **60-90 minutes** (compiles Linux kernel + toolchain). Subsequent builds use cached artifacts:

| Component | First Build | Cached |
|-----------|-------------|--------|
| Linux kernel | ~40 min | instant |
| GCC toolchain | ~30 min | instant |
| Rust/Cargo | ~15 min | instant |
| Your app | ~2 min | ~2 min |

Cache is stored via `magic-nix-cache` (GitHub Actions cache). For persistent caching, add [Cachix](https://cachix.org).

---