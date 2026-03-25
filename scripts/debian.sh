#!/bin/sh
## @file    scripts/debian.sh
## @brief   Install a Debian 13 (trixie) ARMhf root filesystem onto a block device.
##
## @details This script is meant to be called by scripts/image.sh, which
##          creates a blank image file, attaches it to a loop device, and
##          passes the loop device path as the sole argument to this script.
##
##          The script partitions the device, formats it, debootstraps Debian
##          into the ext4 partition, installs Linux kernel modules from the
##          in-tree build, and populates the FAT boot partition with the files
##          U-Boot needs to load the kernel and device tree at runtime.
##
## @par File locations
##          The script reads file paths from environment variables so it can
##          work both when invoked from the Makefile (which sets PROJ_*) and
##          when called manually with the original flat-directory layout.
##          Each variable has a fallback that matches the pre-Makefile paths.
##
## @code
##   Variable            Fallback             Description
##   ------------------  -------------------  ---------------------------------
##   PROJ_BOOT_BIN       boot-rootfs.bin      FSBL + U-Boot binary
##   PROJ_ROOTFS_DTB     rootfs.dtb           Compiled device tree blob
##   PROJ_UENV           uEnv-rootfs.txt      U-Boot environment file
##   PROJ_LINUX_DIR      tmp/linux-6.12       Kernel source tree (for modules)
## @endcode
##
## @param $1  Block device path, e.g. /dev/loop0
##
## @par Partition layout:
## @code
##   +------------------+  offset 4 MiB
##   |  FAT16 boot      |  12 MiB  -- boot.bin, zImage.bin, rootfs.dtb, uEnv.txt
##   +------------------+  offset 16 MiB
##   |  ext4 root       |  remainder of image
##   +------------------+
## @endcode

device=$1

# ---------------------------------------------------------------------------
# Resolve file paths from environment with fallbacks to the legacy locations.
# ---------------------------------------------------------------------------

# FSBL + U-Boot binary written to the FAT partition as boot.bin.
boot_bin=${PROJ_BOOT_BIN:-boot-rootfs.bin}

# Device tree blob for the rootfs boot path.
rootfs_dtb=${PROJ_ROOTFS_DTB:-rootfs.dtb}

# U-Boot environment file. Copied to the FAT partition as uEnv.txt.
uenv_file=${PROJ_UENV:-uEnv-rootfs.txt}

# Kernel source tree. Used to install compiled kernel modules into the rootfs.
linux_dir=${PROJ_LINUX_DIR:-tmp/linux-6.12}

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

boot_dir=`mktemp -d /tmp/BOOT.XXXXXXXXXX`
root_dir=`mktemp -d /tmp/ROOT.XXXXXXXXXX`

linux_ver=6.12.52-xilinx

# Choose mirror automatically depending on geographic and network location.
mirror=http://deb.debian.org/debian

distro=trixie
arch=armhf

passwd=changeme
timezone=Europe/Brussels

# ---------------------------------------------------------------------------
# Partition and format
# ---------------------------------------------------------------------------

parted -s $device mklabel msdos
parted -s $device mkpart primary fat16  4MiB  16MiB
parted -s $device mkpart primary ext4  16MiB  100%

boot_dev=/dev/`lsblk -ln -o NAME -x NAME $device | sed '2!d'`
root_dev=/dev/`lsblk -ln -o NAME -x NAME $device | sed '3!d'`

mkfs.vfat -v $boot_dev
mkfs.ext4 -F -j $root_dev

# ---------------------------------------------------------------------------
# Mount
# ---------------------------------------------------------------------------

mount $boot_dev $boot_dir
mount $root_dev $root_dir

# ---------------------------------------------------------------------------
# Populate FAT boot partition
# ---------------------------------------------------------------------------
# U-Boot reads uEnv.txt at startup and uses it to load zImage.bin and
# rootfs.dtb from this same FAT partition into RAM before booting the kernel.

cp $boot_bin    $boot_dir/boot.bin
cp $rootfs_dtb  $boot_dir/rootfs.dtb
cp $uenv_file   $boot_dir/uEnv.txt
cp zImage.bin   $boot_dir/zImage.bin

# ---------------------------------------------------------------------------
# Install Debian base system into the ext4 root partition
# ---------------------------------------------------------------------------

debootstrap --foreign --arch $arch $distro $root_dir $mirror

# ---------------------------------------------------------------------------
# Install Linux kernel modules
# ---------------------------------------------------------------------------

modules_dir=$root_dir/lib/modules/$linux_ver

mkdir -p $modules_dir/kernel

find $linux_dir -name \*.ko -printf '%P\0' | \
  tar --directory=$linux_dir --owner=0 --group=0 \
      --null --files-from=- -zcf - | \
  tar -zxf - --directory=$modules_dir/kernel

cp $linux_dir/modules.order $linux_dir/modules.builtin $modules_dir/

depmod -a -b $root_dir $linux_ver

# ---------------------------------------------------------------------------
# Add missing configuration files and packages
# ---------------------------------------------------------------------------

cp /etc/resolv.conf $root_dir/etc/
cp /usr/bin/qemu-arm-static $root_dir/usr/bin/

rm $root_dir/etc/apt/sources.list

cp -r debian/etc/apt      $root_dir/etc/
cp -r debian/etc/systemd  $root_dir/etc/

chroot $root_dir <<- EOF_CHROOT
export LANG=C
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

/debootstrap/debootstrap --second-stage

apt-get update
apt-get -y upgrade

apt-get -y install locales

sed -i "/^# en_US.UTF-8 UTF-8$/s/^# //" etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

ln -sf /usr/share/zoneinfo/$timezone etc/localtime
dpkg-reconfigure tzdata

apt-get -y install openssh-server ca-certificates chrony fake-hwclock \
  usbutils psmisc lsof parted curl vim wpasupplicant hostapd dnsmasq \
  firmware-atheros firmware-brcm80211 firmware-mediatek firmware-realtek \
  iw iptables dhcpcd-base ntfs-3g libubootenv-tool

systemctl enable dhcpcd

systemctl disable hostapd
systemctl disable dnsmasq
systemctl disable nftables
systemctl disable wpa_supplicant

sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' etc/ssh/sshd_config

echo root:$passwd | chpasswd

apt-get clean

service chrony stop
service ssh stop

history -c

sync
EOF_CHROOT

cp -r debian/etc $root_dir/

rm $root_dir/etc/resolv.conf
rm $root_dir/usr/bin/qemu-arm-static

# ---------------------------------------------------------------------------
# Unmount and finalize
# ---------------------------------------------------------------------------

umount $boot_dir $root_dir

rmdir $boot_dir $root_dir

zerofree $root_dev
