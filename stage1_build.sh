#!/bin/bash

# This script is meant to be run as the 'lfs' user
source /home/lfs/config.sh
source /home/lfs/common.sh

print_header "Phase 4: Building Cross Toolchain (Stage 1)"

cd $LFS/sources

# --- Binutils Pass 1 ---
explain_step "Building Binutils (Pass 1)" \
    "The Binutils package contains a linker, an assembler, and other tools for handling object files. We build this first to create the cross-linker." \
    "../configure --prefix=\$LFS/tools --with-sysroot=\$LFS --target=\$LFS_TGT ...\nmake\nmake install"

tar -xf binutils-*.tar.xz
cd binutils-*/
mkdir -v build
cd build
../configure --prefix=$LFS/tools \
             --with-sysroot=$LFS \
             --target=$LFS_TGT   \
             --disable-nls       \
             --enable-gprofng=no \
             --disable-werror
make
make install
cd ../..
rm -rf binutils-*
echo -e "${GREEN}Binutils Pass 1 Complete.${NC}"


# --- GCC Pass 1 ---
explain_step "Building GCC (Pass 1)" \
    "The GNU Compiler Collection. We build a basic compiler to compile the rest of the tools. This is a cross-compiler linked against the new Binutils." \
    "../configure --target=\$LFS_TGT --prefix=\$LFS/tools --with-sysroot=\$LFS ...\nmake\nmake install"

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
../configure                  \
    --target=$LFS_TGT         \
    --prefix=$LFS/tools       \
    --with-glibc-version=2.40 \
    --with-sysroot=$LFS       \
    --with-newlib             \
    --without-headers         \
    --enable-default-pie      \
    --enable-default-ssp      \
    --disable-nls             \
    --disable-shared          \
    --disable-multilib        \
    --disable-threads         \
    --disable-libatomic       \
    --disable-libgomp         \
    --disable-libquadmath     \
    --disable-libssp          \
    --disable-libvtv          \
    --disable-libstdcxx       \
    --enable-languages=c,c++
make
make install
cd ../..
rm -rf gcc-*
echo -e "${GREEN}GCC Pass 1 Complete.${NC}"


# --- Linux Headers ---
explain_step "Installing Linux API Headers" \
    "The Linux kernel API headers are needed for Glibc to compile. They define how the OS and applications interact." \
    "make headers\ncp -rv usr/include \$LFS/usr"

tar -xf linux-*.tar.xz
cd linux-*/
make mrproper
make headers
find usr/include -type f ! -name '*.h' -delete
cp -rv usr/include $LFS/usr
cd ..
rm -rf linux-*
echo -e "${GREEN}Linux Headers Installed.${NC}"


# --- Glibc ---
explain_step "Building Glibc" \
    "The GNU C Library. The main C library that every other program on the system will link against." \
    "../configure --prefix=/usr --host=\$LFS_TGT ...\nmake\nmake DESTDIR=\$LFS install"

tar -xf glibc-*.tar.xz
cd glibc-*/
case $(uname -m) in
    i?86)   ln -sfv ld-linux.so.2 $LFS/lib/ld-linux.so.2 ;;
    x86_64) ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64
            ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3 ;;
esac

# Apply fhs patch if present
GLIBC_PATCH=$(ls ../glibc-*.patch 2>/dev/null | head -n1)
if [ -n "$GLIBC_PATCH" ]; then
    patch -Np1 -i "$GLIBC_PATCH"
fi

mkdir -v build
cd build
echo "rootsbindir=/usr/sbin" > configparms

../configure                             \
      --prefix=/usr                      \
      --host=$LFS_TGT                    \
      --build=$(../scripts/config.guess) \
      --enable-kernel=4.19               \
      --with-headers=$LFS/usr/include    \
      --disable-nscd                     \
      libc_cv_slibdir=/usr/lib

make
make DESTDIR=$LFS install
sed '/RTLDLIST=/s@/usr@@g' -i $LFS/usr/bin/ldd
echo 'int main(){}' | $LFS_TGT-gcc -xc -
readelf -l a.out | grep ld-linux
rm -v a.out
cd ../..
rm -rf glibc-*
echo -e "${GREEN}Glibc Complete.${NC}"


# --- Libstdc++ ---
explain_step "Building Libstdc++ (Pass 1)" \
    "The standard C++ library. needed for the final GCC build." \
    "../libstdc++-v3/configure --host=\$LFS_TGT --prefix=/usr ...\nmake\nmake DESTDIR=\$LFS install"

tar -xf gcc-*.tar.xz
cd gcc-*/
GCC_VERSION=$(cat gcc/BASE-VER)
mkdir -v build
cd build
../libstdc++-v3/configure           \
    --host=$LFS_TGT                 \
    --build=$(../config.guess)      \
    --prefix=/usr                   \
    --disable-multilib              \
    --disable-nls                   \
    --disable-libstdcxx-pch         \
    --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/$GCC_VERSION

make
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/lib{stdc++,stdc++fs,supc++}.la
cd ../..
rm -rf gcc-*
echo -e "${GREEN}Libstdc++ Pass 1 Complete.${NC}"
