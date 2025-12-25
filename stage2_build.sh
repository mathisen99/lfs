#!/bin/bash
source /home/lfs/config.sh
source /home/lfs/common.sh

print_header "Phase 5: Building Temporary Tools (Stage 2)"

cd $LFS/sources

# Helper to clean up after build
function cleanup_source() {
    local dir=$1
    cd ..
    rm -rf $dir
}

# --- M4 ---
explain_step "Building M4" "A macro processor required by Autoconf." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf m4-*.tar.xz
cd m4-*/
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cleanup_source "m4-*"
echo -e "${GREEN}M4 Complete.${NC}"

# --- Ncurses ---
explain_step "Building Ncurses" "Libraries for text-based user interfaces (needed by Bash, etc.)." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf ncurses-*.tar.gz
cd ncurses-*/
sed -i s/mawk// configure
mkdir build
pushd build
  ../configure
  make -C include
  make -C progs tic
popd
./configure --prefix=/usr                \
            --host=$LFS_TGT              \
            --build=$(./config.guess)    \
            --mandir=/usr/share/man      \
            --with-manpage-format=normal \
            --with-shared                \
            --without-normal             \
            --with-cxx-shared            \
            --without-debug              \
            --without-ada                \
            --disable-stripping          \
            --enable-widec
make
make DESTDIR=$LFS TIC_PATH=$(pwd)/build/progs/tic install
ln -sv libncursesw.so $LFS/usr/lib/libncurses.so
cleanup_source "ncurses-*"
echo -e "${GREEN}Ncurses Complete.${NC}"

# --- Bash ---
explain_step "Building Bash" "The Shell. We are building the shell for the temporary system." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install\nln -sv bash \$LFS/bin/sh"
tar -xf bash-*.tar.gz
cd bash-*/
./configure --prefix=/usr                   \
            --build=$(support/config.guess) \
            --host=$LFS_TGT                 \
            --without-bash-malloc
make
make DESTDIR=$LFS install
ln -sv bash $LFS/bin/sh
cleanup_source "bash-*"
echo -e "${GREEN}Bash Complete.${NC}"

# --- Coreutils ---
explain_step "Building Coreutils" "Basic file, shell and text manipulation utilities (ls, cp, mv, etc.)." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf coreutils-*.tar.xz
cd coreutils-*/
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess) \
            --enable-install-program=hostname \
            --enable-no-install-program=kill,uptime
make
make DESTDIR=$LFS install
mv -v $LFS/usr/bin/chroot $LFS/usr/sbin
mkdir -pv $LFS/usr/share/man/man8
mv -v $LFS/usr/share/man/man1/chroot.1 $LFS/usr/share/man/man8/chroot.8
sed -i 's/"1"/"8"/' $LFS/usr/share/man/man8/chroot.8
cleanup_source "coreutils-*"
echo -e "${GREEN}Coreutils Complete.${NC}"

# --- Diffutils ---
explain_step "Building Diffutils" "Tools for comparing files." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf diffutils-*.tar.xz
cd diffutils-*/
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install
cleanup_source "diffutils-*"
echo -e "${GREEN}Diffutils Complete.${NC}"

# --- File ---
explain_step "Building File" "Utility to determine file types." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf file-*.tar.gz
cd file-*/
mkdir build
pushd build
  ../configure --disable-bzlib      \
               --disable-libseccomp \
               --disable-xzlib      \
               --disable-zlib
  make
popd
./configure --prefix=/usr --host=$LFS_TGT --build=$(./config.guess)
make FILE_COMPILE=$(pwd)/build/src/file
make DESTDIR=$LFS install
cleanup_source "file-*"
echo -e "${GREEN}File Complete.${NC}"

# --- Findutils ---
explain_step "Building Findutils" "Tools for searching files." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf findutils-*.tar.xz
cd findutils-*/
./configure --prefix=/usr   \
            --localstatedir=/var/lib/locate \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cleanup_source "findutils-*"
echo -e "${GREEN}Findutils Complete.${NC}"

# --- Gawk ---
explain_step "Building Gawk" "GNU Awk, pattern scanning and processing language." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf gawk-*.tar.xz
cd gawk-*/
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cleanup_source "gawk-*"
echo -e "${GREEN}Gawk Complete.${NC}"

# --- Grep ---
explain_step "Building Grep" "Pattern matching utility." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf grep-*.tar.xz
cd grep-*/
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install
cleanup_source "grep-*"
echo -e "${GREEN}Grep Complete.${NC}"

# --- Gzip ---
explain_step "Building Gzip" "Compression utility." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf gzip-*.tar.xz
cd gzip-*/
./configure --prefix=/usr --host=$LFS_TGT
make
make DESTDIR=$LFS install
cleanup_source "gzip-*"
echo -e "${GREEN}Gzip Complete.${NC}"

# --- Make ---
explain_step "Building Make" "Utility to direct compilations." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf make-*.tar.gz
cd make-*/
./configure --prefix=/usr   \
            --without-guile \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cleanup_source "make-*"
echo -e "${GREEN}Make Complete.${NC}"

# --- Patch ---
explain_step "Building Patch" "Utility to apply diff files." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf patch-*.tar.xz
cd patch-*/
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cleanup_source "patch-*"
echo -e "${GREEN}Patch Complete.${NC}"

# --- Sed ---
explain_step "Building Sed" "Stream editor." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf sed-*.tar.xz
cd sed-*/
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cleanup_source "sed-*"
echo -e "${GREEN}Sed Complete.${NC}"

# --- Tar ---
explain_step "Building Tar" "The archiving utility." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf tar-*.tar.xz
cd tar-*/
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cleanup_source "tar-*"
echo -e "${GREEN}Tar Complete.${NC}"

# --- Xz ---
explain_step "Building Xz" "Compression utilities." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf xz-*.tar.xz
cd xz-*/
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess) \
            --disable-static                  \
            --docdir=/usr/share/doc/xz-5.6.2
make
make DESTDIR=$LFS install
cleanup_source "xz-*"
echo -e "${GREEN}Xz Complete.${NC}"

# --- Binutils Pass 2 ---
explain_step "Building Binutils (Pass 2)" "Rebuilding Binutils to link against the new glibc and headers." \
    "../configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf binutils-*.tar.xz
cd binutils-*/
mkdir -v build
cd build
../configure                   \
    --prefix=/usr              \
    --build=$(../config.guess) \
    --host=$LFS_TGT            \
    --disable-nls              \
    --enable-shared            \
    --enable-gprofng=no        \
    --disable-werror           \
    --enable-64-bit-bfd        \
    --enable-default-hash-style=gnu
make
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
cleanup_source "binutils-*"
echo -e "${GREEN}Binutils Pass 2 Complete.${NC}"

# --- GCC Pass 2 ---
explain_step "Building GCC (Pass 2)" "Building the final cross-compiler with C++ support." \
    "../configure --prefix=/usr --host=\$LFS_TGT --target=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf gcc-*.tar.xz
cd gcc-*/
tar -xf ../mpfr-*.tar.xz
mv -v mpfr-* mpfr
tar -xf ../gmp-*.tar.xz
mv -v gmp-* gmp
tar -xf ../mpc-*.tar.gz
mv -v mpc-* mpc

case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
  ;;
esac

mkdir -v build
cd build
../configure                                       \
    --build=$(../config.guess)                     \
    --host=$LFS_TGT                                \
    --target=$LFS_TGT                              \
    LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc      \
    --prefix=/usr                                  \
    --with-build-sysroot=$LFS                      \
    --enable-default-pie                           \
    --enable-default-ssp                           \
    --disable-nls                                  \
    --disable-multilib                             \
    --disable-libatomic                            \
    --disable-libgomp                              \
    --disable-libquadmath                          \
    --disable-libssp                               \
    --disable-libvtv                               \
    --enable-languages=c,c++
make
make DESTDIR=$LFS install
ln -sv gcc $LFS/usr/bin/cc
cleanup_source "gcc-*"
echo -e "${GREEN}GCC Pass 2 Complete.${NC}"


echo -e "${GREEN}Stage 2 (Temporary Tools) Complete.${NC}"
