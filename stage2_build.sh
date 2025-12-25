#!/bin/bash
source /home/lfs/config.sh
source /home/lfs/common.sh

print_header "Phase 5: Building Temporary Tools (Stage 2)"

cd $LFS/sources

# Helper to clean up after build - call with actual directory name, not glob
function cleanup_source() {
    local dir="$1"
    cd $LFS/sources
    rm -rf "$dir"
}

# --- M4 ---
explain_step "Building M4" "A macro processor required by Autoconf." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf m4-*.tar.xz
cd m4-*/
M4_DIR=$(basename $(pwd))
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cleanup_source "$M4_DIR"
echo -e "${GREEN}M4 Complete.${NC}"

# --- Ncurses ---
explain_step "Building Ncurses" "Libraries for text-based user interfaces (needed by Bash, etc.)." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf ncurses-*.tar.gz
cd ncurses-*/
NCURSES_DIR=$(basename $(pwd))
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
cleanup_source "$NCURSES_DIR"
echo -e "${GREEN}Ncurses Complete.${NC}"

# --- Bash ---
explain_step "Building Bash" "The Shell. We are building the shell for the temporary system." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install\nln -sv bash \$LFS/bin/sh"
tar -xf bash-*.tar.gz
cd bash-*/
BASH_DIR=$(basename $(pwd))
./configure --prefix=/usr                   \
            --build=$(support/config.guess) \
            --host=$LFS_TGT                 \
            --without-bash-malloc
make
make DESTDIR=$LFS install
ln -sv bash $LFS/bin/sh
cleanup_source "$BASH_DIR"
echo -e "${GREEN}Bash Complete.${NC}"

# --- Coreutils ---
explain_step "Building Coreutils" "Basic file, shell and text manipulation utilities (ls, cp, mv, etc.)." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf coreutils-*.tar.xz
cd coreutils-*/
COREUTILS_DIR=$(basename $(pwd))
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
cleanup_source "$COREUTILS_DIR"
echo -e "${GREEN}Coreutils Complete.${NC}"

# --- Diffutils ---
explain_step "Building Diffutils" "Tools for comparing files." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf diffutils-*.tar.xz
cd diffutils-*/
DIFFUTILS_DIR=$(basename $(pwd))
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install
cleanup_source "$DIFFUTILS_DIR"
echo -e "${GREEN}Diffutils Complete.${NC}"

# --- File ---
explain_step "Building File" "Utility to determine file types." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf file-*.tar.gz
cd file-*/
FILE_DIR=$(basename $(pwd))
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
cleanup_source "$FILE_DIR"
echo -e "${GREEN}File Complete.${NC}"

# --- Findutils ---
explain_step "Building Findutils" "Tools for searching files." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf findutils-*.tar.xz
cd findutils-*/
FINDUTILS_DIR=$(basename $(pwd))
./configure --prefix=/usr   \
            --localstatedir=/var/lib/locate \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cleanup_source "$FINDUTILS_DIR"
echo -e "${GREEN}Findutils Complete.${NC}"

# --- Gawk ---
explain_step "Building Gawk" "GNU Awk, pattern scanning and processing language." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf gawk-*.tar.xz
cd gawk-*/
GAWK_DIR=$(basename $(pwd))
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cleanup_source "$GAWK_DIR"
echo -e "${GREEN}Gawk Complete.${NC}"

# --- Grep ---
explain_step "Building Grep" "Pattern matching utility." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf grep-*.tar.xz
cd grep-*/
GREP_DIR=$(basename $(pwd))
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install
cleanup_source "$GREP_DIR"
echo -e "${GREEN}Grep Complete.${NC}"

# --- Gzip ---
explain_step "Building Gzip" "Compression utility." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf gzip-*.tar.xz
cd gzip-*/
GZIP_DIR=$(basename $(pwd))
./configure --prefix=/usr --host=$LFS_TGT
make
make DESTDIR=$LFS install
cleanup_source "$GZIP_DIR"
echo -e "${GREEN}Gzip Complete.${NC}"

# --- Make ---
explain_step "Building Make" "Utility to direct compilations." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf make-*.tar.gz
cd make-*/
MAKE_DIR=$(basename $(pwd))
./configure --prefix=/usr   \
            --without-guile \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cleanup_source "$MAKE_DIR"
echo -e "${GREEN}Make Complete.${NC}"

# --- Patch ---
explain_step "Building Patch" "Utility to apply diff files." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf patch-*.tar.xz
cd patch-*/
PATCH_DIR=$(basename $(pwd))
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cleanup_source "$PATCH_DIR"
echo -e "${GREEN}Patch Complete.${NC}"

# --- Sed ---
explain_step "Building Sed" "Stream editor." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf sed-*.tar.xz
cd sed-*/
SED_DIR=$(basename $(pwd))
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cleanup_source "$SED_DIR"
echo -e "${GREEN}Sed Complete.${NC}"

# --- Tar ---
explain_step "Building Tar" "The archiving utility." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf tar-*.tar.xz
cd tar-*/
TAR_DIR=$(basename $(pwd))
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cleanup_source "$TAR_DIR"
echo -e "${GREEN}Tar Complete.${NC}"

# --- Xz ---
explain_step "Building Xz" "Compression utilities." \
    "./configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf xz-*.tar.xz
cd xz-*/
XZ_DIR=$(basename $(pwd))
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess) \
            --disable-static                  \
            --docdir=/usr/share/doc/xz-5.6.2
make
make DESTDIR=$LFS install
cleanup_source "$XZ_DIR"
echo -e "${GREEN}Xz Complete.${NC}"

# --- Binutils Pass 2 ---
explain_step "Building Binutils (Pass 2)" "Rebuilding Binutils to link against the new glibc and headers." \
    "../configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf binutils-*.tar.xz
cd binutils-*/
BINUTILS_DIR=$(basename $(pwd))
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
cleanup_source "$BINUTILS_DIR"
echo -e "${GREEN}Binutils Pass 2 Complete.${NC}"

# --- GCC Pass 2 ---
explain_step "Building GCC (Pass 2)" "Building the final cross-compiler with C++ support." \
    "../configure --prefix=/usr --host=\$LFS_TGT --target=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"
tar -xf gcc-*.tar.xz
cd gcc-*/
GCC_DIR=$(basename $(pwd))
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
cleanup_source "$GCC_DIR"
echo -e "${GREEN}GCC Pass 2 Complete.${NC}"


echo -e "${GREEN}Stage 2 (Temporary Tools) Complete.${NC}"
