#!/bin/bash
source ./config.sh
source ./common.sh

print_header "Phase 6: Entering Chroot (Stage 3)"

explain_step "Bind Mounting Virtual Kernel File Systems" \
    "We need /dev, /proc, and /sys from the host to be available inside the new system." \
    "mkdir -pv \$LFS/{dev,proc,sys,run}\nmount --bind /dev \$LFS/dev\nmount -vt proc proc \$LFS/proc\n..."

mkdir -pv $LFS/{dev,proc,sys,run}
mount -v --bind /dev $LFS/dev
mount -v --bind /dev/pts $LFS/dev/pts
mount -vt proc proc $LFS/proc
mount -vt sysfs sysfs $LFS/sys
mount -vt tmpfs tmpfs $LFS/run

if [ -h $LFS/dev/shm ]; then
  mkdir -pv $LFS/$(readlink $LFS/dev/shm)
fi

explain_step "Copying Scripts to Chroot" \
    "We need our inner installation script available inside the chroot." \
    "cp -v config.sh common.sh install_system_inner.sh $LFS/"

cp -v config.sh common.sh install_system_inner.sh $LFS/

explain_step "Entering Chroot" \
    "We are now entering the new system. The prompt will change. The script 'install_system_inner.sh' will run automatically." \
    "chroot \"$LFS\" ... /bin/bash --login ... -c \"bash /install_system_inner.sh\""

chroot "$LFS" /usr/bin/env -i   \
    HOME=/root                  \
    TERM="$TERM"                \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin     \
    /bin/bash --login +h -c "bash /install_system_inner.sh"

echo -e "${GREEN}Left Chroot. Build process finished successfully?${NC}"

explain_step "Unmounting Filesystems" \
    "Cleaning up mounts before reboot." \
    "umount -v $LFS/dev...\numount -v $LFS"

umount -v $LFS/dev/pts
umount -v $LFS/dev
umount -v $LFS/run
umount -v $LFS/proc
umount -v $LFS/sys
umount -v $LFS

echo -e "${GREEN}All done. You can now reboot into your LFS system!${NC}"
