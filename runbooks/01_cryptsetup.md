# cryptsetup

## Description
**cryptsetup** is an utility included in almost the majority of the linux distributions, and could be used
to encrypt and manage filesystems.
To install it on you distro just use the package manager and install it like the following examples:
- sudo apt install cryptsetup
- sudo pacman -S cryptsetup

The purpose of this runbook is to use it to encrypt USB drives.

## The beginning
**lsblk** could be used to identify the devices without any doubt
**fdisk** could be used to create/remove partitions 
**cryptsetup** is the utility to create and manage the encrypted partitions ( open | close | luksFormat )



## To encrypt 
When ready, with the device and the identified partition, the following command could to perform
the encryption:

```
cryptsetup luksFormat /dev/sdx1
```
this command require a password creation that will be used to unlok the drive

## Interact with the encrypted drive
When an encrypted drive is inserted in a modern linux deskop probably the password will asked
and than the disk will be mounted authomatically.
In case this will not happens or in a terminal environment

### Open and mount the encrypted drive
to open an encrypted partition cryptsetup require a string, that will be used to identify and mount
the partition

```
cryptsetup open /dev/sdx1 <string>
```
the password will be asked and password and the partition mounted under:  
```
/dev/mapper/<string>
```

To mount the drive after the previous command:
```
mount /dev/mapper/<string> /mnt/usb
```

### Create the Filesystem inside the encrypted partition
After the creation and the first open, it's time to create a filesystem inside the encrypted partition.
The filesytem type could vary, it depends for example by the devices where will be used.

eg. to create a btrfs filesystem from the terminal

```
mkfs.btrfs /dev/mapper/<string>
```
**Note:**The fs needs to be created with /dev/mapper/ path and not /dev/sdx1 to not override the encryption 


### Close the encrypted drive
To close and terminate the use of the drive
```
cryptsetup close /dev/sdx1 <string>
```