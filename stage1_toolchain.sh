#!/bin/bash

source ./config.sh
source ./common.sh

print_header "Phase 4: Stage 1 Setup (User & Environment)"

explain_step "Creating LFS User" \
    "We create a separate user 'lfs' to ensure that we don't accidentally mess up the host system while building tools." \
    "groupadd lfs\nuseradd -s /bin/bash -g lfs -m -k /dev/null lfs"

groupadd lfs || true  # Ignore if already exists
useradd -s /bin/bash -g lfs -m -k /dev/null lfs || true  # Ignore if already exists

# Prepare directories - these should already exist from prepare_disk.sh
chown -v lfs $LFS/{usr{,/*},lib,var,etc,bin,sbin,tools,sources}
case $(uname -m) in
  x86_64) chown -v lfs $LFS/lib64 ;;
esac

explain_step "Setting up LFS Environment" \
    "We need to create a .bashrc for the 'lfs' user to set up critical environment variables like LFS, LFS_TGT, and PATH." \
    "cat > /home/lfs/.bash_profile << EOF ...\ncat > /home/lfs/.bashrc << EOF ..."

# Create .bash_profile
cat > /home/lfs/.bash_profile << "EOF"
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
EOF

# Create .bashrc
cat > /home/lfs/.bashrc << EOF
set +h
umask 022
LFS=$LFS
LC_ALL=POSIX
LFS_TGT=$LFS_TGT
LFS_DISK=$LFS_DISK
LFS_DISK_PART=$LFS_DISK_PART
PATH=/usr/bin
if [ ! -L /bin ]; then PATH=/bin:\$PATH; fi
PATH=\$LFS/tools/bin:\$PATH
CONFIG_SITE=\$LFS/usr/share/config.site
export LFS LC_ALL LFS_TGT LFS_DISK LFS_DISK_PART PATH CONFIG_SITE
EOF

# Copy our helper scripts to lfs user home so they can run them
cp -v config.sh common.sh stage1_build.sh /home/lfs/
chown lfs:lfs /home/lfs/{config.sh,common.sh,stage1_build.sh}

explain_step "Starting Build as LFS User" \
    "Swapping to user 'lfs' to start compiling the cross-toolchain." \
    "su - lfs -c \"bash /home/lfs/stage1_build.sh\""

# Run the build script as lfs user
su - lfs -c "bash /home/lfs/stage1_build.sh"

echo -e "${GREEN}Stage 1 Complete.${NC}"
