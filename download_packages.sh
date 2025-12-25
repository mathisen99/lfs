#!/bin/bash

source ./config.sh
source ./common.sh

print_header "Phase 3: Downloading Packages"

explain_step "Fetching wget-list" \
    "We download the list of packages and patches from the LFS book (stable). This ensures we have the correct versions." \
    "wget .../wget-list\nwget .../md5sums"

mkdir -p $LFS/sources
cd $LFS/sources

# Download wget-list and md5sums
wget --no-check-certificate https://www.linuxfromscratch.org/lfs/view/${LFS_VERSION}/wget-list
wget --no-check-certificate https://www.linuxfromscratch.org/lfs/view/${LFS_VERSION}/md5sums

explain_step "Downloading Sources" \
    "Now we download all the tarballs listed in wget-list. This might take a while depending on internet speed." \
    "wget --input-file=wget-list --continue --directory-prefix=$LFS/sources"

wget --input-file=wget-list --continue --directory-prefix=$LFS/sources
echo -e "${GREEN}Downloads complete.${NC}"

explain_step "Verifying Checksums" \
    "We check the MD5 sums to make sure no corrupt files were downloaded." \
    "md5sum -c md5sums || error_exit ..."

pushd $LFS/sources
md5sum -c md5sums || error_exit "Checksum verification failed! Some files are corrupt."
popd

echo -e "${GREEN}Verification complete.${NC}"
