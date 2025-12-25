#!/bin/bash
# Master Installer Script for LFS
source ./config.sh
source ./common.sh

print_header "Linux From Scratch - Automated Installer"

echo -e "${CYAN}Welcome to the LFS Auto-Installer!${NC}"
echo -e "This script will guide you through building LFS on ${YELLOW}$LFS_DISK${NC}."
echo -e "${RED}WARNING: ALL DATA ON $LFS_DISK WILL BE DESTROYED.${NC}"
echo ""
read -p "Type 'YES' to continue, or anything else to abort: " confirmation
if [ "$confirmation" != "YES" ]; then
    echo "Aborting."
    exit 1
fi

# 1. Disk Preparation (moved first to enable swap and prevent RAM exhaustion)
./prepare_disk.sh

# 2. Host Setup
./setup_host.sh

# 3. Download Packages
./download_packages.sh

# 4. Stage 1 Toolchain
./stage1_toolchain.sh

# 5. Stage 2 Temp Tools
./stage2_temp_tools.sh

# 6. Stage 3 Chroot & Final Build
./stage3_chroot.sh

print_header "Installation Complete!"
echo -e "You can now reboot the VM."
