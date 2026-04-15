# OpenBao — Installation

## Prerequisites

- A supported OS: Linux (amd64/arm64), macOS, Windows, FreeBSD.
- For Kubernetes: Helm 3.6+ and a running cluster (Kubernetes 1.30–1.33 officially supported).
- For source compilation: Go toolchain and `git`.

---

## Method 1: Package Manager

### macOS (Homebrew)

```bash
brew install openbao
```

### Arch Linux

```bash
pacman -Sy openbao
# List available plugins
pacman -Ss '^openbao-plugin'
```

### Fedora / RHEL (via EPEL)

```bash
# Enable EPEL first (RHEL only)
dnf install -y epel-release

# Install OpenBao
dnf install -y openbao
```

### Debian / Ubuntu

Packages are available on the [downloads page](https://openbao.org/downloads/). Follow the
repository setup instructions there for `apt`.

### FreeBSD

```bash
pkg install openbao
```

---

## Method 2: Container Image

OpenBao publishes Alpine-based and RHEL UBI-based container images to three registries.

### Alpine-based (default)

| Registry | Image |
|----------|-------|
| GitHub Container Registry | `ghcr.io/openbao/openbao` |
| Quay.io | `quay.io/openbao/openbao` |
| Docker Hub | `docker.io/openbao/openbao` |

### RHEL UBI-based

| Registry | Image |
|----------|-------|
| GitHub Container Registry | `ghcr.io/openbao/openbao-ubi` |
| Quay.io | `quay.io/openbao/openbao-ubi` |
| Docker Hub | `docker.io/openbao/openbao-ubi` |

```bash
# Run a dev server in Docker
docker run --rm \
  --memory-swappiness=0 \
  -p 8200:8200 \
  -e BAO_DEV_ROOT_TOKEN_ID=root \
  ghcr.io/openbao/openbao:latest \
  server -dev

# Run with Podman
podman run --rm \
  -p 8200:8200 \
  ghcr.io/openbao/openbao:latest \
  server -dev
```

> **Security note**: Always pass `--memory-swappiness=0` (Docker) or configure swap encryption
> on the host to prevent secrets from being written to disk via memory paging.

---

## Method 3: Precompiled Binary

1. Download the binary for your platform from the
   [releases page](https://github.com/openbao/openbao/releases).
2. Verify the checksum and GPG signature (see [Verification](#verification) below).
3. Extract and place the `bao` binary in your `PATH`.

```bash
# Example: download and install on Linux amd64
VERSION=$(curl -s https://api.github.com/repos/openbao/openbao/releases/latest \
  | grep tag_name | cut -d'"' -f4 | cut -c2-)
PLATFORM="linux_amd64"

wget "https://github.com/openbao/openbao/releases/download/v${VERSION}/bao_${VERSION}_${PLATFORM}.zip"
unzip "bao_${VERSION}_${PLATFORM}.zip"
chmod +x bao
sudo mv bao /usr/local/bin/

bao -h
```

---

## Method 4: Compile from Source

Requires Go and `git`.

```bash
mkdir -p $GOPATH/src/github.com/openbao
cd $GOPATH/src/github.com/openbao
git clone https://github.com/openbao/openbao.git
cd openbao

# Download and compile dependencies
make bootstrap

# Build for your current platform
make dev
# Binary is placed in ./bin/bao
```

---

## Method 5: Kubernetes (Helm)

The [OpenBao Helm chart](https://github.com/openbao/openbao-helm) is the recommended way to
deploy OpenBao on Kubernetes. Requires Helm 3.6+ and Kubernetes 1.30–1.33.

```bash
# Add the OpenBao Helm repository
helm repo add openbao https://openbao.github.io/openbao-helm
helm repo update

# Verify the chart is available
helm search repo openbao/openbao

# Install with default values (dev mode — NOT for production)
helm install openbao openbao/openbao

# Install a specific chart version
helm install openbao openbao/openbao --version 0.4.0

# Always dry-run before installing to review changes
helm install openbao openbao/openbao --dry-run
```

For HA production deployments, override values for Raft storage and replica count:

```yaml
# values-ha.yaml
server:
  ha:
    enabled: true
    replicas: 3
    raft:
      enabled: true
      setNodeId: true
      config: |
        ui = true
        listener "tcp" {
          tls_disable = 1
          address = "[::]:8200"
          cluster_address = "[::]:8201"
        }
        storage "raft" {
          path = "/vault/data"
        }
        service_registration "kubernetes" {}
```

```bash
helm install openbao openbao/openbao -f values-ha.yaml
```

---

## Verification

### SHA-256 Checksum

```bash
OS="linux"
ARCH="amd64"
VERSION=$(curl -s https://api.github.com/repos/openbao/openbao/releases/latest \
  | grep tag_name | cut -d'"' -f4 | cut -c2-)

wget "https://github.com/openbao/openbao/releases/download/v${VERSION}/bao_${VERSION}_${OS}_${ARCH}.zip"
wget "https://github.com/openbao/openbao/releases/download/v${VERSION}/checksums-${OS}.txt"

sha256sum --check checksums-${OS}.txt 2>/dev/null | grep "bao_${VERSION}_${OS}_${ARCH}"
```

### GPG Signature

```bash
# Import the OpenBao public key
wget https://openbao.org/assets/openbao-gpg-pub-20240618.asc
gpg2 --import openbao-gpg-pub-20240618.asc

# Verify the checksum file signature
wget "https://github.com/openbao/openbao/releases/download/v${VERSION}/checksums-${OS}.txt.gpgsig"
gpg2 --verify "checksums-${OS}.txt.gpgsig" "checksums-${OS}.txt"
```

---

## Verify the Installation

```bash
bao -h
# Expected: usage and flag documentation printed to stdout

bao version
# Expected: OpenBao vX.Y.Z
```

---

## Post-Installation Hardening

OpenBao protects secrets in memory, but OS swap can expose them. After installation:

| OS | Action |
|----|--------|
| Linux (systemd) | Verify `MemorySwapMax=0` in the service file: `systemctl cat openbao` |
| Linux (no systemd) | Set `memory.swap.max=0` via cgroup v2 |
| Docker | Use `--memory-swappiness=0` flag |
| macOS | Swap is always encrypted; no action needed |
| Windows | Run `fsutil behavior set encryptpagingfile 1` and reboot |
| FreeBSD / NetBSD / OpenBSD | Enable encrypted swap per distro documentation |

---

## Sources

- https://openbao.org/docs/install/
- https://openbao.org/docs/platform/k8s/helm/
