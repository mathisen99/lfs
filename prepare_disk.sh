#!/bin/bash

source ./config.sh
source ./common.sh

print_header "Phase 2: Disk Preparation & File System"

explain_step "Wiping Disk $LFS_DISK" \
    "We are about to ERASE ALL DATA on $LFS_DISK to ensure a clean install. This prepares the drive for new partitions." \
    "dd if=/dev/zero of=$LFS_DISK bs=1M count=10 status=progress"

# Wipe partition table
dd if=/dev/zero of=$LFS_DISK bs=1M count=10 status=progress
echo -e "${GREEN}Disk wiped.${NC}"

explain_step "Creating Partitions" \
    "We will create a 4GB Swap partition and use the rest for the Root (/) partition using fdisk." \
    "fdisk $LFS_DISK << EOF
n   # New partition
p   # Primary
1   # Partition number
    # Default start
+4G # Swap size
n   # New partition
p   # Primary
2   # Partition number
    # Default start
    # Default end
t   # Change type
1   # Select partition 1
82  # Swap type
w   # Write changes
EOF"

# Use fdisk to create partitions (non-interactive via HEREDOC)
# n: new partition, p: primary, 1: partition 1, default, +4G (swap)
# n: new partition, p: primary, 2: partition 2, default, default (root)
# t: change type, 1: 82 (Linux swap)
# w: write changes
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk $LFS_DISK
  n # new partition
  p # primary
  1 # partition number
    # default - start at beginning
  +4G # 4 GB swap
  n # new partition
  p # primary
  2 # partition number
    # default - start after swap
    # default - end at end of disk
  t # change type
  1 # select partition 1
  82 # Hex code for Linux Swap
  p # print partition table
  w # write changes
EOF

echo -e "${GREEN}Partitions created.${NC}"

explain_step "Formatting Partitions" \
    "We need to create file systems on these partitions. ext4 for root (${LFS_DISK_PART}2) and mkswap for swap (${LFS_DISK_PART}1)." \
    "mkswap ${LFS_DISK_PART}1\nswapon ${LFS_DISK_PART}1\nmkfs.ext4 ${LFS_DISK_PART}2"

mkswap ${LFS_DISK_PART}1
swapon ${LFS_DISK_PART}1
mkfs.ext4 ${LFS_DISK_PART}2
echo -e "${GREEN}Formatting complete.${NC}"

explain_step "Mounting LFS Partition" \
    "We mount the new partition to $LFS so we can start installing files there." \
    "mkdir -pv $LFS\nmount -v -t ext4 ${LFS_DISK_PART}2 $LFS"

mkdir -pv $LFS
mount -v -t ext4 ${LFS_DISK_PART}2 $LFS
echo -e "${GREEN}Mounted $LFS.${NC}"

explain_step "Creating Sources Directory" \
    "We need a place to store all the source code tarballs. $LFS/sources is the standard location." \
    "mkdir -pv $LFS/sources\nchmod -v a+wt $LFS/sources"

mkdir -pv $LFS/sources
chmod -v a+wt $LFS/sources
echo -e "${GREEN}Sources directory created.${NC}"

explain_step "Creating LFS Directory Structure" \
    "Creating the basic directory structure needed for the toolchain build." \
    "mkdir -pv \$LFS/{etc,var,tools} \$LFS/usr/{bin,lib,sbin}\n..."

mkdir -pv $LFS/{etc,var,tools}
mkdir -pv $LFS/usr/{bin,lib,sbin}
for i in bin lib sbin; do
  ln -sfv usr/$i $LFS/$i
done
case $(uname -m) in
  x86_64) mkdir -pv $LFS/lib64 ;;
esac
echo -e "${GREEN}LFS directory structure created.${NC}"
