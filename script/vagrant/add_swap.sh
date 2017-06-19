#!/bin/bash


# Exit on error
set -e
set -u
set -o errexit

SWAP_DISK="/dev/`lsblk -nr | grep 8G | awk '{ print $1 }'`" # 8 GB partition created in Vagrantfile
if [ ! -e "$SWAP_DISK" ]; then
    echo "Swap disk at $SWAP_DISK does not exist."
    exit 1
fi

SWAP_PARTITION="/dev/disk/by-partlabel/swap"

echo "Adding swap partition to $SWAP_DISK..."
parted -s "$SWAP_DISK" mklabel gpt
parted -s "$SWAP_DISK" mkpart primary linux-swap 1MiB 100%
parted -s "$SWAP_DISK" name 1 swap
sleep 1 # wait for /dev to update

if [ ! -e "$SWAP_PARTITION" ]; then
    echo "Swap partition at $SWAP_PARTITION does not exist."
    exit 1
fi

echo "Configuring $SWAP_PARTITION as swap partition..."
mkswap "$SWAP_PARTITION"
echo "$SWAP_PARTITION swap swap defaults 0 0" >> /etc/fstab

echo "Enabling swap..."
swapon -a

echo "Done."
