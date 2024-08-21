# WoeUSB

## Description
Sometimes, you should be required to build also USBKey with windows image to install Win10 or Win11  
Build the USB Key from windows is super easy, Microsoft has it's own utility, or also Rufus works well.  
Doing the USB Key from Linux or MacOS could be triky.  After some documentation I found a way to build the key from   
Fedora40 with [WoeUSB](https://github.com/WoeUSB/WoeUSB).  

## Installation
I tested this steps on Fedora40 on other distro the commands has to be changed accordingly

*PreReqPackages*
```
sudo dnf install coreutils util-linux gawk parted wget p7zip wimlib-utils

```

*WoeUSB*
You should download the latest version from the GitHub repository and run it on your computer.
I build the USBKey with the following command, please verify the mount point of the USB Key in your environment (mine was /dev/sdb)  

*cmd*
```
sudo ./woeusb-5.2.4.bash --device ./Win10_22H2_EnglishInternational_x64v1.iso /dev/sdb --target-filesystem ntfs
```


## Useful resources
I reccomend to check the following article and the issue on the GitHub repos to find useful infos in case  
of needs.  

- Linux Uprising [article](https://www.linuxuprising.com/2020/10/how-to-make-bootable-windows-10-usb-on.html)
- GitHub [Issues on WoeUSB Repo](https://github.com/jsamr/bootiso/issues/) 