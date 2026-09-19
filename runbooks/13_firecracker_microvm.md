# Firecracker microVM on Linux

This runbook starts a disposable Firecracker microVM on a Linux host. It follows the upstream demonstration workflow and uses upstream CI artifacts. Those artifacts are explicitly not intended for production.

Firecracker is a Linux VMM that requires KVM and read and write access to `/dev/kvm`. It supports `x86_64` and `aarch64`. It does not run natively on macOS because macOS does not provide the Linux KVM interface.

## Contents

- [Prerequisites](#prerequisites)
- [Install Firecracker](#install-firecracker)
- [Prepare a kernel and root filesystem](#prepare-a-kernel-and-root-filesystem)
- [Start and configure the microVM](#start-and-configure-the-microvm)
- [Networking](#networking)
- [Production note](#production-note)
- [Sources](#sources)

## Prerequisites

Confirm the architecture, KVM device, and loaded KVM modules:

```bash
uname -m
ls -l /dev/kvm
lsmod | grep '^kvm'
```

Confirm that the current user can read and write the KVM device:

```bash
[ -r /dev/kvm ] && [ -w /dev/kvm ] && echo "OK" || echo "FAIL"
```

On distributions that use the `kvm` group for device access, add the current user and start a new login session:

```bash
[ "$(stat -c "%G" /dev/kvm)" = kvm ] && sudo usermod -aG kvm "${USER}" \
&& echo "Access granted."
```

When an ACL is used instead, the upstream guide provides this alternative:

```bash
sudo setfacl -m u:${USER}:rw /dev/kvm
```

## Install Firecracker

On Arch Linux and Omarchy:

```bash
sudo pacman -Syu firecracker
firecracker --version
```

On other Linux distributions, download a release from the official Firecracker releases page or build from source using the upstream development tooling. The upstream release-download workflow is:

```bash
ARCH="$(uname -m)"
release_url="https://github.com/firecracker-microvm/firecracker/releases"
latest="$(basename "$(curl -fsSLI -o /dev/null -w %{url_effective} "${release_url}/latest")")"
curl -L "${release_url}/download/${latest}/firecracker-${latest}-${ARCH}.tgz" | tar -xz
mv "release-${latest}-$(uname -m)/firecracker-${latest}-${ARCH}" firecracker
```

For the upstream demonstration root filesystem workflow, install the tools that create and inspect ext4 and squashfs images. On Arch Linux:

```bash
sudo pacman -S --needed curl e2fsprogs openssh squashfs-tools
```

## Prepare a kernel and root filesystem

Create a disposable directory. The generated ext4 image is 1 GiB.

```bash
mkdir -p ~/firecracker-poc
cd ~/firecracker-poc
```

The commands below select the latest upstream Firecracker CI artifact set for the current architecture, download a tested kernel and Ubuntu root filesystem, add a newly generated SSH public key to the guest, and create an ext4 root filesystem:

```bash
set -euo pipefail

ARCH="$(uname -m)"
S3="https://s3.amazonaws.com/spec.ccfc.min"
CI_ARTIFACTS_PREFIX="$(
  curl -fsSL "$S3?list-type=2&prefix=firecracker-ci/&delimiter=/" |
    grep -oP '(?<=<Prefix>)firecracker-ci/[0-9]{8}-[^/]+/(?=</Prefix>)' |
    sort |
    tail -1
)"

latest_kernel_key="$(
  curl -fsSL "$S3?list-type=2&prefix=${CI_ARTIFACTS_PREFIX}${ARCH}/vmlinux-" |
    grep -oP "(?<=<Key>)(${CI_ARTIFACTS_PREFIX}${ARCH}/vmlinux-[0-9]+\.[0-9]+\.[0-9]{1,3})(?=</Key>)" |
    sort -V |
    tail -1
)"
curl -fLO "$S3/$latest_kernel_key"

latest_ubuntu_key="$(
  curl -fsSL "$S3?list-type=2&prefix=${CI_ARTIFACTS_PREFIX}${ARCH}/ubuntu-" |
    grep -oP "(?<=<Key>)(${CI_ARTIFACTS_PREFIX}${ARCH}/ubuntu-[0-9]+\.[0-9]+\.squashfs)(?=</Key>)" |
    sort -V |
    tail -1
)"
ubuntu_version="$(basename "$latest_ubuntu_key" .squashfs | grep -oE '[0-9]+\.[0-9]+')"
curl -fLo "ubuntu-${ubuntu_version}.squashfs.upstream" "$S3/$latest_ubuntu_key"

unsquashfs "ubuntu-${ubuntu_version}.squashfs.upstream"
ssh-keygen -f id_rsa -N ""
cp -v id_rsa.pub squashfs-root/root/.ssh/authorized_keys
mv -v id_rsa "./ubuntu-${ubuntu_version}.id_rsa"

sudo chown -R root:root squashfs-root
truncate -s 1G "ubuntu-${ubuntu_version}.ext4"
sudo mkfs.ext4 -d squashfs-root -F "ubuntu-${ubuntu_version}.ext4"
```

Verify the files:

```bash
KERNEL="$(ls vmlinux-* | tail -1)"
[ -f "$KERNEL" ] && echo "Kernel: $KERNEL" || echo "ERROR: kernel does not exist"

ROOTFS="$(ls *.ext4 | tail -1)"
e2fsck -fn "$ROOTFS" >/dev/null && echo "Rootfs: $ROOTFS" || echo "ERROR: invalid rootfs"

KEY_NAME="$(ls *.id_rsa | tail -1)"
[ -f "$KEY_NAME" ] && echo "SSH key: $KEY_NAME" || echo "ERROR: SSH key does not exist"
```

## Start and configure the microVM

Start Firecracker in one terminal. Keep it running:

```bash
cd ~/firecracker-poc
API_SOCKET="/tmp/firecracker.socket"
rm -f "$API_SOCKET"
./firecracker --api-sock "$API_SOCKET"
```

If Firecracker was installed by the package manager, use `firecracker` instead of `./firecracker`.

In a second terminal, configure the guest and start it:

```bash
cd ~/firecracker-poc

API_SOCKET="/tmp/firecracker.socket"
KERNEL="./$(ls vmlinux-* | tail -1)"
ROOTFS="./$(ls *.ext4 | tail -1)"
KERNEL_BOOT_ARGS="console=ttyS0 reboot=k panic=1"

sudo curl -X PUT --unix-socket "${API_SOCKET}" \
  --data "{\"kernel_image_path\":\"${KERNEL}\",\"boot_args\":\"${KERNEL_BOOT_ARGS}\"}" \
  "http://localhost/boot-source"

sudo curl -X PUT --unix-socket "${API_SOCKET}" \
  --data "{\"drive_id\":\"rootfs\",\"path_on_host\":\"${ROOTFS}\",\"is_root_device\":true,\"is_read_only\":false}" \
  "http://localhost/drives/rootfs"

sudo curl -X PUT --unix-socket "${API_SOCKET}" \
  --data '{"action_type":"InstanceStart"}' \
  "http://localhost/actions"
```

The first terminal displays the guest serial console. A current upstream Ubuntu CI image may log in as `root` automatically. Run `reboot` in the guest to stop it.

## Networking

The upstream network example creates a TAP interface, enables host IPv4 forwarding, configures NAT, adds a Firecracker virtual network interface, then configures the guest route and DNS resolver. These steps expose the guest to more host and network resources than the serial-console-only boot above.

Follow the upstream [network setup documentation](https://github.com/firecracker-microvm/firecracker/blob/main/docs/network-setup.md) only after defining the workload's required destinations and host access. Remove TAP devices and firewall rules after the test.

## Production note

The upstream quickstart deliberately omits the `jailer` to make the VMM API easy to inspect. For production, Firecracker documents `jailer` as the mechanism for an execution jail around the VMM process. It is an additional security control, not a replacement for host patching, restricted networking, least-privilege credentials, and a disposable host for untrusted workloads.

## Sources

- https://firecracker-microvm.github.io/
- https://github.com/firecracker-microvm/firecracker/blob/main/docs/getting-started.md
- https://github.com/firecracker-microvm/firecracker/blob/main/docs/network-setup.md
- https://github.com/firecracker-microvm/firecracker/releases
- https://archlinux.org/packages/extra/x86_64/firecracker/
