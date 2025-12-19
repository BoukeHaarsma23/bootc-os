#!/bin/bash

set -ouex pipefail

PACKAGES="\
    base \
    bootc \
    bouhaa/gamescope-session-steam-git \
    bouhaa/lib32-mesa-tkg-git \
    bouhaa/mesa-tkg-git \
    btrfs-progs \
    dbus \
    dbus-glib \
    dosfstools \
    dracut \
    e2fsprogs \
    gamescope \
    glib2 \
    linux \
    linux-firmware \
    mangohud \
    nano \
    ostree \
    pipewire \
    plymouth \
    shadow \
    skopeo \
    steam \
    sudo \
    xfsprogs \
"


# -------------------------------
# Move /var paths into sysimage
# -------------------------------

grep "= */var" /etc/pacman.conf | sed "/= *\/var/s/.*=// ; s/ //" | xargs -n1 sh -c 'mkdir -p "/usr/lib/sysimage/$(dirname $(echo $1 | sed "s@/var/@@"))" && mv -v "$1" "/usr/lib/sysimage/$(echo "$1" | sed "s@/var/@@")"' '' && \
    sed -i -e "/= *\/var/ s/^#//" -e "s@= */var@= /usr/lib/sysimage@g" -e "/DownloadUser/d" /etc/pacman.conf

# Comment out ParallelDownloads
sed -i '/ParallelDownloads/s/^/#/' /etc/pacman.conf

# -------------------------------
# Add custom repos and install packages
# -------------------------------
cp /etc/pacman.conf /etc/pacman.conf.bak

# Prepend custom repositories
sed -i '/^\[extra\]/s|^|[multilib]\nInclude = /etc/pacman.d/mirrorlist\n\n[bouhaa]\nSigLevel = Optional TrustAll\nServer = file:///repo\n\n|' /etc/pacman.conf

# Sync and install packages
pacman -Syyuu --noconfirm --needed --overwrite '*' --disable-download-timeout ${PACKAGES}

# Clean up temporary repo
rm -rf /tmp/repo

# Restore original pacman.conf
mv /etc/pacman.conf.bak /etc/pacman.conf

# Clean pacman cache
pacman -S --clean --noconfirm

# -------------------------------
# Configure dracut for reproducible initramfs
# -------------------------------
printf "systemdsystemconfdir=/etc/systemd/system\nsystemdsystemunitdir=/usr/lib/systemd/system\n" \
    | tee /usr/lib/dracut/dracut.conf.d/30-bootcrew-fix-bootc-module.conf

printf 'reproducible=yes\nhostonly=no\ncompress=zstd\nadd_dracutmodules+=" plymouth ostree bootc "' \
    | tee /usr/lib/dracut/dracut.conf.d/30-bootcrew-bootc-container-build.conf

# Generate initramfs
LATEST_MODULE_DIR=$(find /usr/lib/modules -maxdepth 1 -type d ! -name "*.img" | tail -n 1)
dracut --force "$LATEST_MODULE_DIR/initramfs.img"

# -------------------------------
# Prepare directories for image-based system
# -------------------------------
# Set default home
sed -i 's|^HOME=.*|HOME=/var/home|' /etc/default/useradd

# Remove unnecessary directories
rm -rf /boot /home /root /usr/local /srv /var /usr/lib/sysimage/log /usr/lib/sysimage/cache/pacman/pkg

# Create essential directories
mkdir -p /sysroot /boot /usr/lib/ostree /var

# Create symbolic links
ln -s sysroot/ostree /ostree
ln -s var/roothome /root
ln -s var/srv /srv
ln -s var/opt /opt
ln -s var/mnt /mnt
ln -s var/home /home

# Configure tmpfiles for base directories
for dir in opt home srv mnt usrlocal; do
    echo "d /var/$dir 0755 root root -" | tee -a /usr/lib/tmpfiles.d/bootc-base-dirs.conf
done

# Additional tmpfiles
printf "d /var/roothome 0700 root root -\nd /run/media 0755 root root -" \
    | tee -a /usr/lib/tmpfiles.d/bootc-base-dirs.conf

# Configure ostree prepare-root
printf '[composefs]\nenabled = yes\n[sysroot]\nreadonly = true\n' \
    | tee /usr/lib/ostree/prepare-root.conf
