#!/bin/bash
# One-liner bootstrap script for LFS Auto-Installer (Arch Host)

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear
echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}   LFS Auto-Installer Bootstrap${NC}"
echo -e "${CYAN}================================================================${NC}"

# Check for root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${YELLOW}Please run as root (or ready to use sudo).${NC}"
    exit 1
fi

echo -e "1. Updating pacman and installing git..."
pacman -Sy --noconfirm git > /dev/null 2>&1

echo -e "2. Cloning repository..."
cd /root
rm -rf lfs_install # Clean up old runs
git clone https://github.com/mathisen99/lfs.git lfs_install > /dev/null 2>&1

echo -e "3. Setting permissions..."
cd lfs_install
chmod +x *.sh

echo -e "${GREEN}Success! Environment ready.${NC}"
echo ""
echo -e "${CYAN}To start the installation, run:${NC}"
echo -e "${YELLOW}  cd /root/lfs_install${NC}"
echo -e "${YELLOW}  ./install.sh${NC}"
echo ""
