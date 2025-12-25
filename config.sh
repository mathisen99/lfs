#!/bin/bash

# LFS Mount Point
export LFS=/mnt/lfs

# LFS Target Architecture
export LFS_TGT=x86_64-lfs-linux-gnu

# Disk Configuration
export LFS_DISK=/dev/vda

# Partition naming helper (handles NVMe vs standard disks)
# NVMe: /dev/nvme0n1 -> /dev/nvme0n1p1
# Standard: /dev/vda -> /dev/vda1
if [[ "$LFS_DISK" == *"nvme"* ]] || [[ "$LFS_DISK" == *"mmcblk"* ]]; then
    export LFS_DISK_PART="${LFS_DISK}p"
else
    export LFS_DISK_PART="${LFS_DISK}"
fi

# Parallel Make Jobs
# Use all available cores
export MAKEFLAGS="-j$(nproc)"

# LFS Version (for wget-list download if needed, though we usually get latest)
export LFS_VERSION="stable"

if [ -z "$LFS_DISK" ]; then
    echo "Error: LFS_DISK variable is empty in config.sh"
    exit 1
fi
