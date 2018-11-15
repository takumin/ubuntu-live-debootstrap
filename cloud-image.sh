#!/bin/bash

set -e

################################################################################
# Load Environment
################################################################################

if [ -n "$1" -a -r "$1" ]; then
  . "$1"
fi

################################################################################
# Default Variables
################################################################################

# Generic
: ${RELEASE:="bionic"}      # [trusty|xenial|bionic]
: ${KERNEL:="generic"}      # [generic|generic-hwe|signed-generic|signed-generic-hwe]
: ${PROFILE:="server"}      # [minimal|standard|server|desktop]

# Cloud
: ${DATASOURCES:="NoCloud"} # Cloud-Init Datasources

# Disk
: ${ROOTFS:="/run/rootfs"}  # Root File System Mount Point

# Mirror
: ${MIRROR_UBUNTU:="http://ftp.jaist.ac.jp/pub/Linux/ubuntu"}
: ${MIRROR_UBUNTU_PARTNER:="http://archive.canonical.com"}
: ${MIRROR_UBUNTU_JA:="http://ftp.jaist.ac.jp/pub/Linux/ubuntu-jp-archive/ubuntu"}
: ${MIRROR_UBUNTU_JA_NONFREE:="http://ftp.jaist.ac.jp/pub/Linux/ubuntu-jp-archive/ubuntu-ja-non-free"}
: ${MIRROR_NVIDIA_CUDA:="http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64"}

# Proxy
: ${NO_PROXY:=""}
: ${APT_PROXY:=""}
: ${FTP_PROXY:=""}
: ${HTTP_PROXY:=""}
: ${HTTPS_PROXY:=""}

################################################################################
# Check Environment
################################################################################

# Release
case "${RELEASE}" in
  'trusty' ) ;;
  'xenial' ) ;;
  'bionic' ) ;;
  * )
    echo "RELEASE: trusty or xenial or bionic"
    exit 1
    ;;
esac

# Kernel
case "${KERNEL}" in
  'generic' ) ;;
  'generic-hwe' ) ;;
  'signed-generic' ) ;;
  'signed-generic-hwe' ) ;;
  * )
    echo "KERNEL: generic or generic-hwe or signed-generic or signed-generic-hwe"
    exit 1
    ;;
esac

# Profile
case "${PROFILE}" in
  'minimal' ) ;;
  'standard' ) ;;
  'server' ) ;;
  'desktop' ) ;;
  * )
    echo "PROFILE: minimal or standard or server or desktop"
    exit 1
    ;;
esac

################################################################################
# Cleanup
################################################################################

# Check Release Directory
if [ -d "./release/${RELEASE}/${KERNEL}/${PROFILE}" ]; then
  # Cleanup Release Directory
  find "./release/${RELEASE}/${KERNEL}/${PROFILE}" -type f | xargs rm -f
else
  # Create Release Directory
  mkdir -p "./release/${RELEASE}/${KERNEL}/${PROFILE}"
fi

# Unmount Root Partition
awk '{print $2}' /proc/mounts | grep -s "${ROOTFS}" | sort -r | xargs --no-run-if-empty umount

################################################################################
# Disk
################################################################################

# Mount Root File System Partition
mkdir -p "${ROOTFS}"
mount -t tmpfs -o mode=0755 tmpfs "${ROOTFS}"

################################################################################
# Debootstrap
################################################################################

# Debootstrap Use Variant
VARIANT="--variant=minbase"

# Debootstrap Components
COMPONENTS="--components=main,restricted,universe,multiverse"

# Debootstrap Include Packages
INCLUDE="--include=gnupg"

# Install Base System
if [ "x${APT_PROXY_HOST}" != "x" -a "x${APT_PROXY_PORT}" != "x" ]; then
  env http_proxy="http://${APT_PROXY_HOST}:${APT_PROXY_PORT}" debootstrap "${VARIANT}" "${COMPONENTS}" "${INCLUDE}" "${RELEASE}" "${ROOTFS}" "${MIRROR_UBUNTU}"
else
  debootstrap "${VARIANT}" "${COMPONENTS}" "${INCLUDE}" "${RELEASE}" "${ROOTFS}" "${MIRROR_UBUNTU}"
fi

# Require Environment
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HOME="/root"
export LC_ALL="C"
export LANGUAGE="C"
export LANG="C"
export DEBIAN_FRONTEND="noninteractive"
export DEBIAN_PRIORITY="critical"
export DEBCONF_NONINTERACTIVE_SEEN="true"

# Cleanup Files
find "${ROOTFS}/dev"     -mindepth 1 | xargs --no-run-if-empty rm -fr
find "${ROOTFS}/proc"    -mindepth 1 | xargs --no-run-if-empty rm -fr
find "${ROOTFS}/run"     -mindepth 1 | xargs --no-run-if-empty rm -fr
find "${ROOTFS}/sys"     -mindepth 1 | xargs --no-run-if-empty rm -fr
find "${ROOTFS}/tmp"     -mindepth 1 | xargs --no-run-if-empty rm -fr
find "${ROOTFS}/var/tmp" -mindepth 1 | xargs --no-run-if-empty rm -fr

# Require Mount
mount -t devtmpfs                   devtmpfs "${ROOTFS}/dev"
mount -t devpts   -o gid=5,mode=620 devpts   "${ROOTFS}/dev/pts"
mount -t proc                       proc     "${ROOTFS}/proc"
mount -t tmpfs    -o mode=755       tmpfs    "${ROOTFS}/run"
mount -t sysfs                      sysfs    "${ROOTFS}/sys"
mount -t tmpfs                      tmpfs    "${ROOTFS}/tmp"
mount -t tmpfs                      tmpfs    "${ROOTFS}/var/tmp"
chmod 1777 "${ROOTFS}/dev/shm"

################################################################################
# Repository
################################################################################

# Official Repository
cat > "${ROOTFS}/etc/apt/sources.list" << __EOF__
# Official Repository
deb ${MIRROR_UBUNTU} ${RELEASE}          main restricted universe multiverse
deb ${MIRROR_UBUNTU} ${RELEASE}-updates  main restricted universe multiverse
deb ${MIRROR_UBUNTU} ${RELEASE}-security main restricted universe multiverse
__EOF__

# Partner Repository
cat > "${ROOTFS}/etc/apt/sources.list.d/ubuntu-partner.list" << __EOF__
# Partner Repository
deb ${MIRROR_UBUNTU_PARTNER} ${RELEASE} partner
__EOF__

# Japanese Team Repository
wget -qO "${ROOTFS}/tmp/ubuntu-ja-archive-keyring.gpg" https://www.ubuntulinux.jp/ubuntu-ja-archive-keyring.gpg
wget -qO "${ROOTFS}/tmp/ubuntu-jp-ppa-keyring.gpg" https://www.ubuntulinux.jp/ubuntu-jp-ppa-keyring.gpg
chroot "${ROOTFS}" apt-key add /tmp/ubuntu-ja-archive-keyring.gpg
chroot "${ROOTFS}" apt-key add /tmp/ubuntu-jp-ppa-keyring.gpg
cat > "${ROOTFS}/etc/apt/sources.list.d/ubuntu-ja.list" << __EOF__
# Japanese Team Repository
deb ${MIRROR_UBUNTU_JA} ${RELEASE} main
deb ${MIRROR_UBUNTU_JA_NONFREE} ${RELEASE} multiverse
__EOF__

################################################################################
# Upgrade
################################################################################

# Update Repository
chroot "${ROOTFS}" apt-get -y update

# Upgrade System
chroot "${ROOTFS}" apt-get -y dist-upgrade

################################################################################
# Minimal
################################################################################

# Minimal Package
chroot "${ROOTFS}" apt-get -y install ubuntu-minimal

################################################################################
# Standard
################################################################################

# Check Environment Variable
if [ "${PROFILE}" = 'standard' -o "${PROFILE}" = 'server' -o "${PROFILE}" = 'desktop' ]; then
  # Install Package
  chroot "${ROOTFS}" apt-get -y install ubuntu-standard
fi

################################################################################
# Server
################################################################################

# Check Environment Variable
if [ "${PROFILE}" = 'server' ]; then
  # Install Package
  chroot "${ROOTFS}" apt-get -y install ubuntu-server language-pack-ja
fi

################################################################################
# Desktop
################################################################################

# Check Environment Variable
if [ "${PROFILE}" = 'desktop' ]; then
  # HWE Version Xorg
  if [ "${RELEASE}-${KERNEL}" = 'trusty-generic-hwe' -o "${RELEASE}-${KERNEL}" = 'trusty-signed-generic-hwe' ]; then
    chroot "${ROOTFS}" apt-get -y install xserver-xorg-core-lts-xenial \
                                          xserver-xorg-input-all-lts-xenial \
                                          xserver-xorg-video-all-lts-xenial \
                                          libegl1-mesa-lts-xenial \
                                          libgbm1-lts-xenial \
                                          libgl1-mesa-dri-lts-xenial \
                                          libgl1-mesa-glx-lts-xenial \
                                          libgles1-mesa-lts-xenial \
                                          libgles2-mesa-lts-xenial \
                                          libwayland-egl1-mesa-lts-xenial
    chroot "${ROOTFS}" apt-get -y --no-install-recommends install xserver-xorg-lts-xenial
  elif [ "${RELEASE}-${KERNEL}" = 'xenial-generic-hwe' -o "${RELEASE}-${KERNEL}" = 'xenial-signed-generic-hwe' ]; then
    chroot "${ROOTFS}" apt-get -y install xserver-xorg-core-hwe-16.04 \
                                          xserver-xorg-input-all-hwe-16.04 \
                                          xserver-xorg-video-all-hwe-16.04 \
                                          xserver-xorg-legacy-hwe-16.04 \
                                          libgl1-mesa-dri
    chroot "${ROOTFS}" apt-get -y --no-install-recommends install xserver-xorg-hwe-16.04
  fi

  # Install Package
  chroot "${ROOTFS}" apt-get -y install ubuntu-desktop ubuntu-defaults-ja

  # Check Release Version
  if [ "${RELEASE}" = 'bionic' ]; then
    # Workaround: Fix System Log Error Message
    chroot "${ROOTFS}" apt-get -y install gir1.2-clutter-1.0 gir1.2-clutter-gst-3.0 gir1.2-gtkclutter-1.0

    # Install Input Method Package
    chroot "${ROOTFS}" apt-get -y install fcitx fcitx-mozc

    # Default Input Method for Fcitx
    echo '[org.gnome.settings-daemon.plugins.keyboard]' >  "${ROOTFS}/usr/share/glib-2.0/schemas/99_gsettings-input-method.gschema.override"
    echo 'active=false'                                 >> "${ROOTFS}/usr/share/glib-2.0/schemas/99_gsettings-input-method.gschema.override"
    chroot "${ROOTFS}" glib-compile-schemas /usr/share/glib-2.0/schemas
  fi
fi

################################################################################
# Cloud
################################################################################

# Require Package
chroot "${ROOTFS}" apt-get -y install cloud-init cloud-initramfs-copymods cloud-initramfs-dyn-netconf cloud-initramfs-rooturl overlayroot

# Clear Default Config
cat << __EOF__ > "${ROOTFS}/etc/cloud/cloud.cfg"
cloud_init_modules:
 - migrator
 - seed_random
 - bootcmd
 - write-files
 - growpart
 - resizefs
 - disk_setup
 - mounts
 - set_hostname
 - update_hostname
 - update_etc_hosts
 - ca-certs
 - rsyslog
 - users-groups
 - ssh
cloud_config_modules:
 - emit_upstart
 - snap
 - ssh-import-id
 - locale
 - set-passwords
 - grub-dpkg
 - apt-pipelining
 - apt-configure
 - ubuntu-advantage
 - ntp
 - timezone
 - disable-ec2-metadata
 - runcmd
 - byobu
cloud_final_modules:
 - package-update-upgrade-install
 - fan
 - landscape
 - lxd
 - puppet
 - chef
 - mcollective
 - salt-minion
 - rightscale_userdata
 - scripts-vendor
 - scripts-per-once
 - scripts-per-boot
 - scripts-per-instance
 - scripts-user
 - ssh-authkey-fingerprints
 - keys-to-console
 - phone-home
 - final-message
 - power-state-change
__EOF__

# Select Datasources
sed -i -E "s/^(datasource_list:) .*/\\1 [ ${DATASOURCES}, None ]/" "${ROOTFS}/etc/cloud/cloud.cfg.d/90_dpkg.cfg"

################################################################################
# Cleanup
################################################################################

# Out Of Packages
chroot "${ROOTFS}" apt-get -y autoremove --purge

# Package Archive
chroot "${ROOTFS}" apt-get -y clean

# Repository List
find "${ROOTFS}/var/lib/apt/lists" -type f | xargs rm -f
touch "${ROOTFS}/var/lib/apt/lists/lock"
chmod 0640 "${ROOTFS}/var/lib/apt/lists/lock"

################################################################################
# Infomation
################################################################################

# Packages List
chroot "${ROOTFS}" dpkg -l | sed -E '1,5d' | awk '{print $2 "\t" $3}' > "./release/${RELEASE}/${KERNEL}/${PROFILE}/packages.manifest"

################################################################################
# Archive
################################################################################

# Unmount RootFs
awk '{print $2}' /proc/mounts | grep -s "${ROOTFS}/" | sort -r | xargs --no-run-if-empty umount

# Create SquashFS Image
mksquashfs "${ROOTFS}" "./release/${RELEASE}/${KERNEL}/${PROFILE}/rootfs.squashfs" -e 'boot/grub' -comp xz

# Create TarBall Image
tar -I pixz -p --acls --xattrs --one-file-system -cf "./release/${RELEASE}/${KERNEL}/${PROFILE}/rootfs.tar.xz" -C "${ROOTFS}" --exclude './boot/grub' .

# Require Mount
mount -t devtmpfs                   devtmpfs "${ROOTFS}/dev"
mount -t devpts   -o gid=5,mode=620 devpts   "${ROOTFS}/dev/pts"
mount -t proc                       proc     "${ROOTFS}/proc"
mount -t tmpfs    -o mode=755       tmpfs    "${ROOTFS}/run"
mount -t sysfs                      sysfs    "${ROOTFS}/sys"
mount -t tmpfs                      tmpfs    "${ROOTFS}/tmp"
mount -t tmpfs                      tmpfs    "${ROOTFS}/var/tmp"
chmod 1777 "${ROOTFS}/dev/shm"

# Remove Resolv.conf
rm "${ROOTFS}/etc/resolv.conf"

# Copy Host Resolv.conf
cp /etc/resolv.conf "${ROOTFS}/etc/resolv.conf"

################################################################################
# Repository
################################################################################

# Update Repository
chroot "${ROOTFS}" apt-get -y update

################################################################################
# Kernel
################################################################################

# Select Kernel
case "${RELEASE}-${KERNEL}" in
  "trusty-generic"            ) KERNEL_PACKAGE="linux-image-generic" ;;
  "xenial-generic"            ) KERNEL_PACKAGE="linux-image-generic" ;;
  "bionic-generic"            ) KERNEL_PACKAGE="linux-image-generic" ;;
  "trusty-generic-hwe"        ) KERNEL_PACKAGE="linux-image-generic-lts-xenial" ;;
  "xenial-generic-hwe"        ) KERNEL_PACKAGE="linux-image-generic-hwe-16.04" ;;
  "bionic-generic-hwe"        ) KERNEL_PACKAGE="linux-image-generic" ;;
  "trusty-signed-generic"     ) KERNEL_PACKAGE="linux-signed-image-generic" ;;
  "xenial-signed-generic"     ) KERNEL_PACKAGE="linux-signed-image-generic" ;;
  "bionic-signed-generic"     ) KERNEL_PACKAGE="linux-signed-image-generic" ;;
  "trusty-signed-generic-hwe" ) KERNEL_PACKAGE="linux-signed-image-generic-lts-xenial" ;;
  "xenial-signed-generic-hwe" ) KERNEL_PACKAGE="linux-signed-image-generic-hwe-16.04" ;;
  "bionic-signed-generic-hwe" ) KERNEL_PACKAGE="linux-signed-image-generic" ;;
  * )
    echo "Unknown Release Codename & Kernel Type..."
    exit 1
    ;;
esac

# Install Kernel
chroot "${ROOTFS}" apt-get -y --no-install-recommends install "${KERNEL_PACKAGE}"

# Copy Kernel
find "${ROOTFS}/boot" -type f -name "vmlinuz-*-generic" -exec cp {} "./release/${RELEASE}/${KERNEL}/${PROFILE}/kernel.img" \;

################################################################################
# Initramfs
################################################################################

# Get Linux Kernel Version
_CURRENT_LINUX_VERSION="`uname -r`"
_CHROOT_LINUX_VERSION="`chroot \"${ROOTFS}\" dpkg -l | awk '{print $2}' | grep -E 'linux-image-.*-generic' | sed -E 's/linux-image-//'`"

# Check Linux Kernel Version
if [ "${_CURRENT_LINUX_VERSION}" != "${_CHROOT_LINUX_VERSION}" ]; then
  # Remove Current Kernel Version Module
  chroot "${ROOTFS}" update-initramfs -d -k "`uname -r`"
fi

# Update Initramfs
chroot "${ROOTFS}" update-initramfs -u -k all

# Copy Initrd
find "${ROOTFS}/boot" -type f -name "initrd.img-*-generic" -exec cp {} "./release/${RELEASE}/${KERNEL}/${PROFILE}/initrd.img" \;

################################################################################
# Permission
################################################################################

# Permission Files
find "./release" -type f | xargs chmod 0644

################################################################################
# Owner/Group
################################################################################

# Owner/Group Files
if [ -n "${SUDO_UID}" -a -n "${SUDO_GID}" ]; then
  chown -R "${SUDO_UID}:${SUDO_GID}" "./release"
fi
