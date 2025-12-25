#!/bin/bash

# LFS Mount Point
export LFS=/mnt/lfs

# LFS Target Architecture
export LFS_TGT=x86_64-lfs-linux-gnu

# Disk Configuration
export LFS_DISK=/dev/vda

# Parallel Make Jobs
# Use all available cores
export MAKEFLAGS="-j$(nproc)"

# LFS Version (for wget-list download if needed, though we usually get latest)
export LFS_VERSION="stable"

if [ -z "$LFS_DISK" ]; then
    echo "Error: LFS_DISK variable is empty in config.sh"
    exit 1
fi
