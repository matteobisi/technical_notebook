# How to Resize a Linux Partition on RHEL 9.x

When working with Linux virtual machines, it is often necessary to expand disks and partitions to accommodate growing data or system requirements. This guide describes how to expand a disk and the underlying LVM (Logical Volume Manager) structures on a RHEL 9.x server.

**Disclaimer:** Always perform a backup of your data before attempting any of the operations described in this guide. Incorrectly modifying partitions can lead to data loss.

## Table of Contents

- [Scenario 1: Expanding a Data Disk](#scenario-1-expanding-a-data-disk)
- [Scenario 2: Expanding the System Disk](#scenario-2-expanding-the-system-disk)

---

## Scenario 1: Expanding a Data Disk

This is the most common scenario, where you need to expand a non-system disk (e.g., a disk used for application data).

### Step 1: Increase the Disk Size in the Hypervisor

The first step is to increase the size of the virtual disk in your hypervisor (e.g., VMware, Hyper-V, KVM). This operation is performed outside the Linux VM.

### Step 2: Rescan the SCSI Bus

After increasing the disk size in the hypervisor, you need to make the Linux kernel aware of the new size. You can do this by rescanning the SCSI bus.

First, identify the disk you want to rescan. You can use the `lsblk` command to list the block devices.

```bash
lsblk
```

Once you have identified the disk (e.g., `sdb`), you can rescan it using the following command:

```bash
echo 1 > /sys/class/scsi_disk/X:X:X:X/device/rescan
```

Replace `X:X:X:X` with the correct SCSI address of your disk. You can find this information in the output of the `dmesg` command after booting the system.

Alternatively, you can rescan all SCSI hosts:

```bash
for host in /sys/class/scsi_host/host*; do echo "- - -" > $host/scan; done
```

After rescanning, you can use `lsblk` or `fdisk -l` to verify that the new size is detected.

### Step 3: Expand the Physical Volume (PV)

Now that the kernel sees the new disk size, you need to expand the LVM Physical Volume. Use the `pvresize` command with the device name of the physical volume.

```bash
pvresize /dev/sdb
```

### Step 4: Expand the Logical Volume (LV)

Next, expand the Logical Volume to use the additional space. You can use the `lvextend` command. You can choose to extend the volume by a specific size or to use all the available free space.

To extend the volume by a specific size (e.g., 100GB):

```bash
lvextend -L +100G /dev/vg_name/lv_name
```

To extend the volume to use all the available free space in the Volume Group:

```bash
lvextend -l +100%FREE /dev/vg_name/lv_name
```

Replace `vg_name` and `lv_name` with the names of your Volume Group and Logical Volume.

### Step 5: Resize the Filesystem

The final step is to resize the filesystem to use the new space in the Logical Volume. The command to use depends on the filesystem type.

For **XFS** filesystems (the default for RHEL):

```bash
xfs_growfs /path/to/mountpoint
```

For **ext4** filesystems:

```bash
resize2fs /dev/vg_name/lv_name
```

After this step, your filesystem should have the new, larger size. You can verify this with the `df -h` command.

---

## Scenario 2: Expanding the System Disk

Expanding the system disk (the disk that contains the root partition) is a more critical operation. The steps are similar to expanding a data disk, but you need to be more careful.

**Note:** It is highly recommended to take a snapshot of the VM before proceeding.

### Step 1: Increase the Disk Size and Rescan

Follow the same steps as for a data disk to increase the disk size in the hypervisor and rescan the SCSI bus.

### Step 2: Identify the Root Partition

Use the `lsblk` or `df -h` command to identify the device and partition that contains the root filesystem (`/`).

### Step 3: Expand the Physical and Logical Volumes

Follow the same `pvresize` and `lvextend` commands as for a data disk, using the correct device names for the system disk.

### Step 4: Resize the Root Filesystem

Follow the same `xfs_growfs` or `resize2fs` command as for a data disk, using the mountpoint of the root filesystem (`/`).

```bash
# For XFS
xfs_growfs /

# For ext4
resize2fs /dev/vg_name/root_lv_name
```

The operation should be performed online without any downtime.

---

This guide provides a general overview of the process. Always refer to the official RHEL documentation for the most accurate and up-to-date information.
