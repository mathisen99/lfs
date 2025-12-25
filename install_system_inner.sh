#!/bin/bash
#===============================================================================
# LFS Final System Build Script (Inside Chroot)
#===============================================================================
# This script builds the complete LFS system from within the chroot environment.
# It follows the LFS book Chapter 8 sequence, building all packages needed for
# a fully functional Linux system.
#
# The build order matters! Dependencies must be built before packages that need them.
# For example: Zlib before Binutils, GMP/MPFR/MPC before GCC, etc.
#===============================================================================

source /config.sh
source /common.sh

print_header "Phase 6: Final System Build (Inside Chroot)"

# Setup environment for root
# LFS_DISK and LFS_DISK_PART are passed from chroot environment
export HOME=/root
export TERM="$TERM"
export PS1='(lfs chroot) \u:\w\$ '
export PATH=/usr/bin:/usr/sbin
export LFS_DISK="${LFS_DISK:-/dev/vda}"
export LFS_DISK_PART="${LFS_DISK_PART:-/dev/vda}"

#===============================================================================
# Helper Functions
#===============================================================================

# Clean up source directory after build
cleanup() {
    cd /sources
    rm -rf "$1"
}

# Extract and enter source directory, returns the directory name
extract_and_cd() {
    local tarball="$1"
    tar -xf "$tarball"
    local dir=$(tar -tf "$tarball" | head -1 | cut -d'/' -f1)
    cd "$dir"
    echo "$dir"
}

#===============================================================================
# SECTION 1: Directory Structure & Essential Files
#===============================================================================
# Before building packages, we need the standard Linux directory hierarchy
# and essential system files like /etc/passwd and /etc/group.
#===============================================================================

explain_step "Creating Directory Structure" \
    "Setting up the standard Linux Filesystem Hierarchy (FHS). Each directory has a specific purpose - /bin for essential binaries, /etc for configuration, /var for variable data, etc." \
    "mkdir -pv /{boot,home,mnt,opt,srv}\nmkdir -pv /etc/{opt,sysconfig}\n..."

mkdir -pv /{boot,home,mnt,opt,srv}
mkdir -pv /etc/{opt,sysconfig}
mkdir -pv /lib/firmware
mkdir -pv /media/{floppy,cdrom}
mkdir -pv /usr/{,local/}{bin,include,lib,sbin,src}
mkdir -pv /usr/{,local/}share/{color,dict,doc,info,locale,man}
mkdir -pv /usr/{,local/}share/{misc,terminfo,zoneinfo}
mkdir -pv /usr/{,local/}share/man/man{1..8}
mkdir -pv /var/{cache,local,log,mail,opt,spool}
mkdir -pv /var/lib/{color,misc,locate}

ln -sfv /run /var/run
ln -sfv /run/lock /var/lock
install -dv -m 0750 /root
install -dv -m 1777 /tmp /var/tmp

echo -e "${GREEN}Directories created.${NC}"

explain_step "Creating Essential Files" \
    "Linux needs /etc/passwd for user accounts and /etc/group for groups. These define who can log in and what permissions they have. We create minimal entries for system operation." \
    "cat > /etc/passwd << EOF\nroot:x:0:0:root:/root:/bin/bash\n..."

ln -sfv /proc/self/mounts /etc/mtab

cat > /etc/passwd << "EOF"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
EOF

cat > /etc/group << "EOF"
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
input:x:24:
mail:x:34:
kvm:x:61:
uuidd:x:80:
wheel:x:97:
users:x:999:
nogroup:x:65534:
EOF

# Create log files with proper permissions
touch /var/log/{btmp,lastlog,faillog,wtmp}
chgrp -v utmp /var/log/lastlog
chmod -v 664  /var/log/lastlog
chmod -v 600  /var/log/btmp

echo -e "${GREEN}Essential files created.${NC}"

#===============================================================================
# SECTION 2: Core System Libraries
#===============================================================================
# These are the foundational libraries that almost everything else depends on.
# Glibc is THE C library - every program uses it.
# Zlib, Bzip2, Xz provide compression used by many tools.
#===============================================================================

cd /sources

# --- Glibc (GNU C Library) ---
explain_step "Building Glibc" \
    "The GNU C Library is the most important piece of the system. It provides the core C library functions (printf, malloc, file I/O, etc.) that virtually every program uses. This is a LONG build." \
    "../configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd glibc-*.tar.xz)
GLIBC_PATCH=$(ls ../glibc-*.patch 2>/dev/null | head -n1)
[ -n "$GLIBC_PATCH" ] && patch -Np1 -i "$GLIBC_PATCH"

# Fix a security issue identified upstream
sed '/width -=/s/googol/abs (&)/' -i stdio-common/vfprintf-internal.c

mkdir -v build && cd build
echo "rootsbindir=/usr/sbin" > configparms

../configure --prefix=/usr                   \
             --disable-werror                \
             --enable-kernel=4.19            \
             --enable-stack-protector=strong \
             --disable-nscd                  \
             libc_cv_slibdir=/usr/lib
make
# Skip tests for speed: make check
make install

# Fix hardcoded path in ldd script
sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd

# Install locale data (for internationalization)
make localedata/install-locales

# Configure the dynamic linker
cat > /etc/ld.so.conf << "EOF"
/usr/local/lib
/opt/lib
EOF

cleanup "$DIR"
echo -e "${GREEN}Glibc installed.${NC}"

# --- Zlib (Compression Library) ---
explain_step "Building Zlib" \
    "Zlib provides compression/decompression functions used by many programs including the kernel, SSH, and package managers. It implements the DEFLATE algorithm (same as gzip)." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd zlib-*.tar.xz)
./configure --prefix=/usr
make
make install
rm -fv /usr/lib/libz.a  # Remove static library
cleanup "$DIR"
echo -e "${GREEN}Zlib installed.${NC}"

# --- Bzip2 (Compression) ---
explain_step "Building Bzip2" \
    "Bzip2 provides better compression than gzip (but slower). Many source tarballs use .tar.bz2 format. We patch it to install shared libraries." \
    "make -f Makefile-libbz2_so\nmake\nmake install"

DIR=$(extract_and_cd bzip2-*.tar.gz)

# Patch to use relative symlinks and install docs properly
sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile

# Build shared library first
make -f Makefile-libbz2_so
make clean
make

make PREFIX=/usr install
cp -av libbz2.so.* /usr/lib
ln -sv libbz2.so.1.0.8 /usr/lib/libbz2.so
cp -v bzip2-shared /usr/bin/bzip2
for i in bunzip2 bzcat; do
  ln -sfv bzip2 /usr/bin/$i
done
rm -fv /usr/lib/libbz2.a

cleanup "$DIR"
echo -e "${GREEN}Bzip2 installed.${NC}"

# --- Xz (Compression) ---
explain_step "Building Xz" \
    "Xz provides LZMA compression - even better ratios than bzip2. The Linux kernel and many modern tarballs use .tar.xz format." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd xz-*.tar.xz)
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/xz
make
make install
cleanup "$DIR"
echo -e "${GREEN}Xz installed.${NC}"

# --- Lz4 (Fast Compression) ---
explain_step "Building Lz4" \
    "Lz4 is extremely fast compression, used by the kernel for initramfs and by systemd. Speed over compression ratio." \
    "make\nmake PREFIX=/usr install"

DIR=$(extract_and_cd lz4-*.tar.gz)
make BUILD_STATIC=no PREFIX=/usr
make BUILD_STATIC=no PREFIX=/usr install
cleanup "$DIR"
echo -e "${GREEN}Lz4 installed.${NC}"

# --- Zstd (Modern Compression) ---
explain_step "Building Zstd" \
    "Zstd (Zstandard) is Facebook's modern compression algorithm - fast like lz4 but with ratios approaching xz. Used by newer kernels and package managers." \
    "make prefix=/usr\nmake prefix=/usr install"

DIR=$(extract_and_cd zstd-*.tar.gz)
make prefix=/usr
make prefix=/usr install
rm -v /usr/lib/libzstd.a
cleanup "$DIR"
echo -e "${GREEN}Zstd installed.${NC}"


#===============================================================================
# SECTION 3: File & Text Utilities
#===============================================================================
# These tools handle files, text processing, and are needed by build systems.
#===============================================================================

# --- File (Magic Number Detection) ---
explain_step "Building File" \
    "The 'file' command identifies file types by examining their contents (magic numbers), not just extensions. Essential for scripts and build systems." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd file-*.tar.gz)
./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}File installed.${NC}"

# --- Readline (Line Editing Library) ---
explain_step "Building Readline" \
    "Readline provides command-line editing, history, and tab completion. Used by Bash, Python, and many interactive programs. Makes your terminal much nicer to use!" \
    "./configure --prefix=/usr ...\nmake SHLIB_LIBS=\"-lncursesw\"\nmake install"

DIR=$(extract_and_cd readline-*.tar.gz)

# Reinstalling Readline will cause old libraries to be moved to <name>.old
sed -i '/MV.*telerik/d' Makefile.in
sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf

./configure --prefix=/usr    \
            --disable-static \
            --with-curses    \
            --docdir=/usr/share/doc/readline
make SHLIB_LIBS="-lncursesw"
make SHLIB_LIBS="-lncursesw" install

cleanup "$DIR"
echo -e "${GREEN}Readline installed.${NC}"

# --- M4 (Macro Processor) ---
explain_step "Building M4" \
    "M4 is a macro processor used by Autoconf and Bison. It reads input, expands macros, and produces output. Fundamental to the GNU build system." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd m4-*.tar.xz)
./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}M4 installed.${NC}"

# --- Bc (Calculator) ---
explain_step "Building Bc" \
    "Bc is an arbitrary precision calculator language. The Linux kernel build system uses it for calculations. Also useful for shell script math." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd bc-*.tar.xz)
CC=gcc ./configure --prefix=/usr -G -O3 -r
make
make install
cleanup "$DIR"
echo -e "${GREEN}Bc installed.${NC}"

# --- Flex (Lexical Analyzer) ---
explain_step "Building Flex" \
    "Flex generates lexical analyzers (scanners) - programs that recognize patterns in text. Used to build parsers for programming languages and config files." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd flex-*.tar.gz)
./configure --prefix=/usr \
            --docdir=/usr/share/doc/flex \
            --disable-static
make
make install

# Some programs look for 'lex' not 'flex'
ln -sv flex   /usr/bin/lex
ln -sv flex.1 /usr/share/man/man1/lex.1

cleanup "$DIR"
echo -e "${GREEN}Flex installed.${NC}"

# --- Tcl (Tool Command Language) ---
explain_step "Building Tcl" \
    "Tcl is a scripting language. We need it primarily to run test suites for other packages (like Expect and DejaGNU). Many packages use Tcl-based tests." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd tcl*-src.tar.gz)
SRCDIR=$(pwd)
cd unix
./configure --prefix=/usr \
            --mandir=/usr/share/man
make

# Install and create compatibility symlinks
make install
chmod -v u+w /usr/lib/libtcl*.so
make install-private-headers
ln -sfv tclsh8.6 /usr/bin/tclsh

cleanup "$DIR"
echo -e "${GREEN}Tcl installed.${NC}"

# --- Expect (Automation Tool) ---
explain_step "Building Expect" \
    "Expect automates interactive programs - it can 'expect' certain output and 'send' responses. Used heavily in test suites to automate testing of interactive programs." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd expect*.tar.gz)
./configure --prefix=/usr           \
            --with-tcl=/usr/lib     \
            --enable-shared         \
            --mandir=/usr/share/man \
            --with-tclinclude=/usr/include
make
make install
ln -svf expect5.45.4/libexpect5.45.4.so /usr/lib
cleanup "$DIR"
echo -e "${GREEN}Expect installed.${NC}"

# --- DejaGNU (Testing Framework) ---
explain_step "Building DejaGNU" \
    "DejaGNU is a framework for testing programs. GCC, Binutils, and other GNU tools use it for their test suites. Ensures software works correctly." \
    "./configure --prefix=/usr\nmake install"

DIR=$(extract_and_cd dejagnu-*.tar.gz)
mkdir -v build && cd build
../configure --prefix=/usr
makeinfo --html --no-split -o doc/dejagnu.html ../doc/dejagnu.texi
makeinfo --plaintext       -o doc/dejagnu.txt  ../doc/dejagnu.texi
make install
cleanup "$DIR"
echo -e "${GREEN}DejaGNU installed.${NC}"

# --- Pkgconf (Package Config) ---
explain_step "Building Pkgconf" \
    "Pkgconf helps build systems find installed libraries. When you compile a program that needs, say, zlib, pkgconf tells the compiler where to find it and what flags to use." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd pkgconf-*.tar.xz)
./configure --prefix=/usr              \
            --disable-static           \
            --docdir=/usr/share/doc/pkgconf
make
make install

# Create pkg-config symlink (many programs expect this name)
ln -sv pkgconf   /usr/bin/pkg-config
ln -sv pkgconf.1 /usr/share/man/man1/pkg-config.1

cleanup "$DIR"
echo -e "${GREEN}Pkgconf installed.${NC}"


#===============================================================================
# SECTION 4: Core Build Tools (Binutils, GMP, MPFR, MPC, GCC)
#===============================================================================
# These are the compiler toolchain - the tools that build everything else.
# GCC needs GMP, MPFR, and MPC for arbitrary precision math.
# Binutils provides the assembler and linker.
#===============================================================================

# --- Binutils (Assembler & Linker) ---
explain_step "Building Binutils" \
    "Binutils contains the GNU assembler (as), linker (ld), and tools for manipulating object files. Every compiled program goes through these tools." \
    "../configure --prefix=/usr ...\nmake tooldir=/usr\nmake tooldir=/usr install"

DIR=$(extract_and_cd binutils-*.tar.xz)
mkdir -v build && cd build

../configure --prefix=/usr       \
             --sysconfdir=/etc   \
             --enable-gold       \
             --enable-ld=default \
             --enable-plugins    \
             --enable-shared     \
             --disable-werror    \
             --enable-64-bit-bfd \
             --enable-new-dtags  \
             --with-system-zlib  \
             --enable-default-hash-style=gnu
make tooldir=/usr
make tooldir=/usr install

# Remove useless static libraries
rm -fv /usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a

cleanup "$DIR"
echo -e "${GREEN}Binutils installed.${NC}"

# --- GMP (GNU Multiple Precision Arithmetic) ---
explain_step "Building GMP" \
    "GMP provides arbitrary precision arithmetic - math with numbers of unlimited size. GCC uses it internally for constant folding and other optimizations." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd gmp-*.tar.xz)

./configure --prefix=/usr    \
            --enable-cxx     \
            --disable-static \
            --docdir=/usr/share/doc/gmp
make
make html
make install
make install-html

cleanup "$DIR"
echo -e "${GREEN}GMP installed.${NC}"

# --- MPFR (Multiple Precision Floating-Point) ---
explain_step "Building MPFR" \
    "MPFR provides arbitrary precision floating-point math with correct rounding. Built on top of GMP, used by GCC for floating-point constant evaluation." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd mpfr-*.tar.xz)

./configure --prefix=/usr        \
            --disable-static     \
            --enable-thread-safe \
            --docdir=/usr/share/doc/mpfr
make
make html
make install
make install-html

cleanup "$DIR"
echo -e "${GREEN}MPFR installed.${NC}"

# --- MPC (Multiple Precision Complex) ---
explain_step "Building MPC" \
    "MPC provides arbitrary precision complex number arithmetic. Built on MPFR and GMP, used by GCC for complex number constant evaluation." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd mpc-*.tar.gz)

./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/mpc
make
make html
make install
make install-html

cleanup "$DIR"
echo -e "${GREEN}MPC installed.${NC}"

# --- Attr (Extended Attributes) ---
explain_step "Building Attr" \
    "Attr provides tools and libraries for managing extended file attributes - metadata beyond the standard permissions. Used by ACLs and security systems." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd attr-*.tar.gz)

./configure --prefix=/usr     \
            --disable-static  \
            --sysconfdir=/etc \
            --docdir=/usr/share/doc/attr
make
make install

cleanup "$DIR"
echo -e "${GREEN}Attr installed.${NC}"

# --- Acl (Access Control Lists) ---
explain_step "Building Acl" \
    "ACLs provide fine-grained file permissions beyond the traditional user/group/other model. You can give specific users specific permissions on specific files." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd acl-*.tar.xz)

./configure --prefix=/usr         \
            --disable-static      \
            --docdir=/usr/share/doc/acl
make
make install

cleanup "$DIR"
echo -e "${GREEN}Acl installed.${NC}"

# --- Libcap (POSIX Capabilities) ---
explain_step "Building Libcap" \
    "Libcap implements POSIX capabilities - a way to give programs specific root privileges without full root access. More secure than setuid." \
    "make prefix=/usr lib=lib\nmake prefix=/usr lib=lib install"

DIR=$(extract_and_cd libcap-*.tar.xz)

sed -i '/install -m.*STA/d' libcap/Makefile
make prefix=/usr lib=lib
make prefix=/usr lib=lib install

cleanup "$DIR"
echo -e "${GREEN}Libcap installed.${NC}"

# --- Libxcrypt (Password Hashing) ---
explain_step "Building Libxcrypt" \
    "Libxcrypt provides modern password hashing functions (SHA-512, yescrypt, etc.). Replaces the old crypt() from glibc with more secure algorithms." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd libxcrypt-*.tar.xz)

./configure --prefix=/usr                 \
            --enable-hashes=strong,glibc  \
            --enable-obsolete-api=no      \
            --disable-static              \
            --disable-failure-tokens
make
make install

cleanup "$DIR"
echo -e "${GREEN}Libxcrypt installed.${NC}"

# --- Shadow (Password Management) ---
explain_step "Building Shadow" \
    "Shadow provides secure password management - /etc/shadow stores hashed passwords separately from /etc/passwd. Also provides useradd, passwd, login, etc." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd shadow-*.tar.xz)

# Disable installation of 'groups' program (coreutils provides it)
sed -i 's/groups$(EXEEXT) //' src/Makefile.in
find man -name Makefile.in -exec sed -i 's/groups\.1 / /'   {} \;
find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
find man -name Makefile.in -exec sed -i 's/passwd\.5 / /'   {} \;

# Use SHA-512 for password hashing (more secure than MD5)
sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' \
    -e 's:/var/spool/mail:/var/mail:'                   \
    -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                  \
    -i etc/login.defs

./configure --sysconfdir=/etc   \
            --disable-static    \
            --with-{b,yes}crypt \
            --without-libbsd    \
            --with-group-name-max-length=32
make
make exec_prefix=/usr install
make -C man install-man

# Enable shadow passwords
pwconv
grpconv

# Set default useradd config
mkdir -p /etc/default
useradd -D --gid 999

cleanup "$DIR"
echo -e "${GREEN}Shadow installed.${NC}"


# --- GCC (GNU Compiler Collection) ---
explain_step "Building GCC" \
    "GCC is THE compiler - it compiles C, C++, and other languages into machine code. This is the LONGEST build in LFS (can take hours). It's the heart of the system." \
    "../configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd gcc-*.tar.xz)

# GCC requires GMP, MPFR, and MPC - we built them, so use system copies
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
  ;;
esac

mkdir -v build && cd build

../configure --prefix=/usr            \
             LD=ld                     \
             --enable-languages=c,c++ \
             --enable-default-pie     \
             --enable-default-ssp     \
             --enable-host-pie        \
             --disable-multilib       \
             --disable-bootstrap      \
             --disable-fixincludes    \
             --with-system-zlib
make
make install

# Many programs expect 'cc' to be the C compiler
ln -svr /usr/bin/gcc /usr/bin/cc

# Create the LTO plugin symlink for binutils
ln -sfv ../../libexec/gcc/$(gcc -dumpmachine)/$(gcc -dumpversion)/liblto_plugin.so \
        /usr/lib/bfd-plugins/

# Sanity check - make sure the compiler works!
echo 'int main(){}' > dummy.c
cc dummy.c -v -Wl,--verbose &> dummy.log
readelf -l a.out | grep ': /lib'

# Verify it's using the correct dynamic linker
grep -E -o '/usr/lib.*/S?crt[1telerik].*succeeded' dummy.log
grep -B4 '^ /usr/include' dummy.log
grep 'SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g'
rm -v dummy.c a.out dummy.log

# Move a misplaced file
mkdir -pv /usr/share/gdb/auto-load/usr/lib
mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib

cleanup "$DIR"
echo -e "${GREEN}GCC installed - the compiler is ready!${NC}"

#===============================================================================
# SECTION 5: Ncurses & Core Text Tools
#===============================================================================
# Ncurses provides terminal handling for text-based UIs.
# Sed, Grep, Bash, etc. are the core text processing tools.
#===============================================================================

# --- Ncurses (Terminal Library) ---
explain_step "Building Ncurses" \
    "Ncurses provides terminal-independent screen handling. Programs like vim, htop, and dialog use it for text-based user interfaces." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd ncurses-*.tar.gz)

./configure --prefix=/usr           \
            --mandir=/usr/share/man \
            --with-shared           \
            --without-debug         \
            --without-normal        \
            --with-cxx-shared       \
            --enable-pc-files       \
            --with-pkg-config-libdir=/usr/lib/pkgconfig
make
make DESTDIR=$PWD/dest install
install -vm755 dest/usr/lib/libncursesw.so.6.5 /usr/lib
rm -v  dest/usr/lib/libncursesw.so.6.5
sed -e 's/^#if.*XOPEN.*$/#if 1/' \
    -i dest/usr/include/curses.h
cp -av dest/* /

# Many programs expect non-wide ncurses
for lib in ncurses form panel menu ; do
    ln -sfv lib${lib}w.so /usr/lib/lib${lib}.so
    ln -sfv ${lib}w.pc    /usr/lib/pkgconfig/${lib}.pc
done

# Compatibility with old programs expecting -lcurses
ln -sfv libncursesw.so /usr/lib/libcurses.so

cleanup "$DIR"
echo -e "${GREEN}Ncurses installed.${NC}"

# --- Sed (Stream Editor) ---
explain_step "Building Sed" \
    "Sed is a stream editor - it transforms text as it flows through. Essential for shell scripts and build systems. The 's/old/new/' syntax is iconic." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd sed-*.tar.xz)
./configure --prefix=/usr
make
make html
make install
cleanup "$DIR"
echo -e "${GREEN}Sed installed.${NC}"

# --- Psmisc (Process Utilities) ---
explain_step "Building Psmisc" \
    "Psmisc provides process management tools: fuser (who's using a file), killall (kill by name), pstree (process tree view)." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd psmisc-*.tar.xz)
./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}Psmisc installed.${NC}"

# --- Gettext (Internationalization) ---
explain_step "Building Gettext" \
    "Gettext provides internationalization (i18n) - translating programs into different languages. The _() function you see in code marks translatable strings." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd gettext-*.tar.xz)
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/gettext
make
make install
chmod -v 0755 /usr/lib/preloadable_libintl.so
cleanup "$DIR"
echo -e "${GREEN}Gettext installed.${NC}"

# --- Bison (Parser Generator) ---
explain_step "Building Bison" \
    "Bison generates parsers - programs that understand structured input like programming languages or config files. Many compilers use Bison-generated parsers." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd bison-*.tar.xz)
./configure --prefix=/usr --docdir=/usr/share/doc/bison
make
make install
cleanup "$DIR"
echo -e "${GREEN}Bison installed.${NC}"

# --- Grep (Pattern Matching) ---
explain_step "Building Grep" \
    "Grep searches for patterns in text - one of the most-used Unix tools. 'grep error logfile' finds all lines containing 'error'. Supports regular expressions." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd grep-*.tar.xz)
sed -i "s/echo/#echo/" src/egrep.sh
./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}Grep installed.${NC}"

# --- Bash (Bourne Again Shell) ---
explain_step "Building Bash" \
    "Bash is THE shell - the command interpreter you interact with. It runs your commands, scripts, and provides the terminal experience. This is your interface to the system." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd bash-*.tar.gz)

# Apply upstream patches if available
shopt -s nullglob
for patch in ../bash-*-patches/*.patch; do
    patch -Np0 -i "$patch"
done
shopt -u nullglob

./configure --prefix=/usr             \
            --without-bash-malloc     \
            --with-installed-readline \
            bash_cv_strtold_broken=no \
            --docdir=/usr/share/doc/bash
make
make install

cleanup "$DIR"
echo -e "${GREEN}Bash installed.${NC}"

# --- Libtool (Library Tool) ---
explain_step "Building Libtool" \
    "Libtool simplifies building shared libraries across different platforms. It hides the complexity of different linker flags and library formats." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd libtool-*.tar.xz)
./configure --prefix=/usr
make
make install
rm -fv /usr/lib/libltdl.a
cleanup "$DIR"
echo -e "${GREEN}Libtool installed.${NC}"

# --- GDBM (Database Library) ---
explain_step "Building GDBM" \
    "GDBM is a simple key-value database library. Many programs use it to store configuration or cache data in a fast, indexed format." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd gdbm-*.tar.gz)
./configure --prefix=/usr    \
            --disable-static \
            --enable-libgdbm-compat
make
make install
cleanup "$DIR"
echo -e "${GREEN}GDBM installed.${NC}"

# --- Gperf (Perfect Hash Generator) ---
explain_step "Building Gperf" \
    "Gperf generates perfect hash functions - lookup tables with O(1) access time. Used to optimize keyword recognition in compilers and interpreters." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd gperf-*.tar.gz)
./configure --prefix=/usr --docdir=/usr/share/doc/gperf
make
make install
cleanup "$DIR"
echo -e "${GREEN}Gperf installed.${NC}"

# --- Expat (XML Parser) ---
explain_step "Building Expat" \
    "Expat is a fast, stream-oriented XML parser. Many programs use it to read XML configuration files or data formats." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd expat-*.tar.xz)
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/expat
make
make install
cleanup "$DIR"
echo -e "${GREEN}Expat installed.${NC}"

# --- Inetutils (Network Utilities) ---
explain_step "Building Inetutils" \
    "Inetutils provides basic network tools: hostname, ping, telnet, ftp, etc. These are the classic Unix networking commands." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd inetutils-*.tar.xz)
./configure --prefix=/usr        \
            --bindir=/usr/bin    \
            --localstatedir=/var \
            --disable-logger     \
            --disable-whois      \
            --disable-rcp        \
            --disable-rexec      \
            --disable-rlogin     \
            --disable-rsh        \
            --disable-servers
make
make install
mv -v /usr/{,s}bin/ifconfig
cleanup "$DIR"
echo -e "${GREEN}Inetutils installed.${NC}"

# --- Less (Pager) ---
explain_step "Building Less" \
    "Less is a pager - it lets you scroll through text files. 'less' is more than 'more' (the older pager). Used by man pages and git." \
    "./configure --prefix=/usr --sysconfdir=/etc\nmake\nmake install"

DIR=$(extract_and_cd less-*.tar.gz)
./configure --prefix=/usr --sysconfdir=/etc
make
make install
cleanup "$DIR"
echo -e "${GREEN}Less installed.${NC}"


#===============================================================================
# SECTION 6: Perl, Python, and Build Infrastructure
#===============================================================================
# Perl and Python are scripting languages used by many build systems.
# Autoconf/Automake generate portable build scripts.
#===============================================================================

# --- Perl ---
explain_step "Building Perl" \
    "Perl is a powerful scripting language. Many system tools and build scripts are written in Perl. It's famous for text processing and 'one-liners'." \
    "sh Configure -des -Dprefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd perl-*.tar.xz)

export BUILD_ZLIB=False
export BUILD_BZIP2=0

sh Configure -des                                          \
             -D prefix=/usr                                \
             -D vendorprefix=/usr                          \
             -D privlib=/usr/lib/perl5/5.40/core_perl      \
             -D archlib=/usr/lib/perl5/5.40/core_perl      \
             -D sitelib=/usr/lib/perl5/5.40/site_perl      \
             -D sitearch=/usr/lib/perl5/5.40/site_perl     \
             -D vendorlib=/usr/lib/perl5/5.40/vendor_perl  \
             -D vendorarch=/usr/lib/perl5/5.40/vendor_perl \
             -D man1dir=/usr/share/man/man1                \
             -D man3dir=/usr/share/man/man3                \
             -D pager="/usr/bin/less -isR"                 \
             -D useshrplib                                 \
             -D usethreads
make
make install
unset BUILD_ZLIB BUILD_BZIP2

cleanup "$DIR"
echo -e "${GREEN}Perl installed.${NC}"

# --- XML::Parser (Perl Module) ---
explain_step "Building XML::Parser" \
    "XML::Parser is a Perl module for parsing XML. Required by Intltool and other build tools that process XML files." \
    "perl Makefile.PL\nmake\nmake install"

DIR=$(extract_and_cd XML-Parser-*.tar.gz)
perl Makefile.PL
make
make install
cleanup "$DIR"
echo -e "${GREEN}XML::Parser installed.${NC}"

# --- Intltool (Internationalization Tool) ---
explain_step "Building Intltool" \
    "Intltool extracts translatable strings from various file formats (XML, desktop files, etc.) for internationalization." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd intltool-*.tar.gz)
sed -i 's:\\\${:\$\\{:' intltool-update.in
./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}Intltool installed.${NC}"

# --- Autoconf (Configure Script Generator) ---
explain_step "Building Autoconf" \
    "Autoconf generates ./configure scripts that detect system features. When you run './configure', you're running an Autoconf-generated script." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd autoconf-*.tar.xz)
./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}Autoconf installed.${NC}"

# --- Automake (Makefile Generator) ---
explain_step "Building Automake" \
    "Automake generates Makefile.in files from simple Makefile.am templates. Works with Autoconf to create portable build systems." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd automake-*.tar.xz)
./configure --prefix=/usr --docdir=/usr/share/doc/automake
make
make install
cleanup "$DIR"
echo -e "${GREEN}Automake installed.${NC}"

# --- OpenSSL (Cryptography Library) ---
explain_step "Building OpenSSL" \
    "OpenSSL provides cryptographic functions: encryption, hashing, SSL/TLS. Essential for secure communications (HTTPS, SSH, etc.)." \
    "./config --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd openssl-*.tar.gz)
./config --prefix=/usr         \
         --openssldir=/etc/ssl \
         --libdir=lib          \
         shared                \
         zlib-dynamic
make
sed -i '/INSTALL_LIBS/s/libcrypto.a libssl.a//' Makefile
make MANSUFFIX=ssl install
cleanup "$DIR"
echo -e "${GREEN}OpenSSL installed.${NC}"

# --- Kmod (Kernel Module Tools) ---
explain_step "Building Kmod" \
    "Kmod provides tools to manage kernel modules: insmod, rmmod, lsmod, modprobe. These load and unload drivers and kernel features." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd kmod-*.tar.xz)
./configure --prefix=/usr     \
            --sysconfdir=/etc \
            --with-openssl    \
            --with-xz         \
            --with-zstd       \
            --with-zlib
make
make install

# Create symlinks for traditional module tool names
for target in depmod insmod modinfo modprobe rmmod; do
  ln -sfv ../bin/kmod /usr/sbin/$target
done
ln -sfv kmod /usr/bin/lsmod

cleanup "$DIR"
echo -e "${GREEN}Kmod installed.${NC}"

# --- Libelf (ELF Library) ---
explain_step "Building Libelf from Elfutils" \
    "Libelf provides tools to read and write ELF files (executables, libraries, object files). Used by debuggers and build tools." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd elfutils-*.tar.bz2)
./configure --prefix=/usr                \
            --disable-debuginfod         \
            --enable-libdebuginfod=dummy
make
make -C libelf install
install -vm644 config/libelf.pc /usr/lib/pkgconfig
rm /usr/lib/libelf.a
cleanup "$DIR"
echo -e "${GREEN}Libelf installed.${NC}"

# --- Libffi (Foreign Function Interface) ---
explain_step "Building Libffi" \
    "Libffi allows code to call functions whose signatures are not known at compile time. Used by Python's ctypes and many language runtimes." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd libffi-*.tar.gz)
./configure --prefix=/usr          \
            --disable-static       \
            --with-gcc-arch=native
make
make install
cleanup "$DIR"
echo -e "${GREEN}Libffi installed.${NC}"

# --- Python ---
explain_step "Building Python" \
    "Python is a popular programming language. Many system tools, build scripts, and applications use Python. This build includes pip for package management." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd Python-*.tar.xz)
./configure --prefix=/usr        \
            --enable-shared      \
            --with-system-expat  \
            --enable-optimizations
make
make install

# Create pip config to prevent accidental system-wide installs
cat > /etc/pip.conf << EOF
[global]
root-user-action = ignore
disable-pip-version-check = true
EOF

cleanup "$DIR"
echo -e "${GREEN}Python installed.${NC}"

# --- Flit-core (Python Build Backend) ---
explain_step "Building Flit-core" \
    "Flit-core is a Python build backend used by many Python packages. It's needed to build other Python modules." \
    "pip3 wheel ...\npip3 install ..."

DIR=$(extract_and_cd flit_core-*.tar.gz)
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --no-user --find-links dist flit_core
cleanup "$DIR"
echo -e "${GREEN}Flit-core installed.${NC}"

# --- Wheel (Python Packaging) ---
explain_step "Building Wheel" \
    "Wheel is the standard Python package format (.whl files). This tool builds and installs wheel packages." \
    "pip3 wheel ...\npip3 install ..."

DIR=$(extract_and_cd wheel-*.tar.gz)
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links=dist wheel
cleanup "$DIR"
echo -e "${GREEN}Wheel installed.${NC}"

# --- Setuptools (Python Build Tool) ---
explain_step "Building Setuptools" \
    "Setuptools is the classic Python build/install tool. Many packages still use setup.py which requires setuptools." \
    "pip3 wheel ...\npip3 install ..."

DIR=$(extract_and_cd setuptools-*.tar.gz)
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist setuptools
cleanup "$DIR"
echo -e "${GREEN}Setuptools installed.${NC}"

# --- Ninja (Build System) ---
explain_step "Building Ninja" \
    "Ninja is a fast build system focused on speed. Many modern projects (LLVM, Chrome, Meson-based) use Ninja instead of Make." \
    "python3 configure.py --bootstrap\ninstall -vm755 ninja /usr/bin/"

DIR=$(extract_and_cd ninja-*.tar.gz)
python3 configure.py --bootstrap
install -vm755 ninja /usr/bin/
cleanup "$DIR"
echo -e "${GREEN}Ninja installed.${NC}"

# --- Meson (Build System) ---
explain_step "Building Meson" \
    "Meson is a modern build system that generates Ninja files. It's faster and easier to use than Autotools. Many new projects use Meson." \
    "pip3 wheel ...\npip3 install ..."

DIR=$(extract_and_cd meson-*.tar.gz)
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist meson
cleanup "$DIR"
echo -e "${GREEN}Meson installed.${NC}"


#===============================================================================
# SECTION 7: System Utilities
#===============================================================================
# Core system utilities for file systems, processes, and system management.
#===============================================================================

# --- Coreutils (Core Utilities) ---
explain_step "Building Coreutils" \
    "Coreutils provides the basic file, shell, and text utilities: ls, cp, mv, cat, chmod, chown, etc. These are the commands you use every day." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd coreutils-*.tar.xz)

# Patch for internationalization
patch -Np1 -i ../coreutils-*.patch || true

autoreconf -fiv
FORCE_UNSAFE_CONFIGURE=1 ./configure \
            --prefix=/usr            \
            --enable-no-install-program=kill,uptime
make
make install

# Move programs to FHS-compliant locations
mv -v /usr/bin/chroot /usr/sbin
mv -v /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8
sed -i 's/"1"/"8"/' /usr/share/man/man8/chroot.8

cleanup "$DIR"
echo -e "${GREEN}Coreutils installed.${NC}"

# --- Check (Unit Test Framework) ---
explain_step "Building Check" \
    "Check is a unit testing framework for C. Many packages use it to run their test suites." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd check-*.tar.gz)
./configure --prefix=/usr --disable-static
make
make docdir=/usr/share/doc/check install
cleanup "$DIR"
echo -e "${GREEN}Check installed.${NC}"

# --- Diffutils (File Comparison) ---
explain_step "Building Diffutils" \
    "Diffutils provides diff, cmp, sdiff, and diff3 for comparing files. Essential for patches, version control, and seeing what changed." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd diffutils-*.tar.xz)
./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}Diffutils installed.${NC}"

# --- Gawk (GNU Awk) ---
explain_step "Building Gawk" \
    "Gawk is a pattern scanning and processing language. It's incredibly powerful for text processing and data extraction from structured text." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd gawk-*.tar.xz)
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr
make
rm -f /usr/bin/gawk-*
make install
cleanup "$DIR"
echo -e "${GREEN}Gawk installed.${NC}"

# --- Findutils (File Finding) ---
explain_step "Building Findutils" \
    "Findutils provides find, locate, and xargs. 'find' searches for files by various criteria. 'xargs' builds command lines from input." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd findutils-*.tar.xz)
./configure --prefix=/usr --localstatedir=/var/lib/locate
make
make install
cleanup "$DIR"
echo -e "${GREEN}Findutils installed.${NC}"

# --- Groff (Document Formatting) ---
explain_step "Building Groff" \
    "Groff formats text documents, especially man pages. When you run 'man ls', groff renders the man page for your terminal." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd groff-*.tar.gz)
PAGE=letter ./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}Groff installed.${NC}"

# --- Gzip (Compression) ---
explain_step "Building Gzip" \
    "Gzip provides .gz compression - the most common compression format on Unix. Used by tar, HTTP compression, and countless files." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd gzip-*.tar.xz)
./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}Gzip installed.${NC}"

# --- IPRoute2 (Network Configuration) ---
explain_step "Building IPRoute2" \
    "IPRoute2 provides the 'ip' command for network configuration. It's the modern replacement for ifconfig, route, and other legacy tools." \
    "make NETNS_RUN_DIR=/run/netns\nmake SBINDIR=/usr/sbin install"

DIR=$(extract_and_cd iproute2-*.tar.xz)
sed -i /ARPD/d Makefile
rm -fv man/man8/arpd.8
make NETNS_RUN_DIR=/run/netns
make SBINDIR=/usr/sbin install
cleanup "$DIR"
echo -e "${GREEN}IPRoute2 installed.${NC}"

# --- Kbd (Keyboard Utilities) ---
explain_step "Building Kbd" \
    "Kbd provides keyboard and console utilities: loadkeys, setfont, etc. These configure your keyboard layout and console fonts." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd kbd-*.tar.xz)

# Remove redundant resizecons program
sed -i '/RESIZECONS_PROGS=/s/telerik//' configure
sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in

./configure --prefix=/usr --disable-vlock
make
make install
cleanup "$DIR"
echo -e "${GREEN}Kbd installed.${NC}"

# --- Libpipeline (Pipeline Library) ---
explain_step "Building Libpipeline" \
    "Libpipeline provides a C library for manipulating pipelines of subprocesses. Used by man-db for processing man pages." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd libpipeline-*.tar.gz)
./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}Libpipeline installed.${NC}"

# --- Make (Build Automation) ---
explain_step "Building Make" \
    "Make is the classic build automation tool. It reads Makefiles and builds software by running commands when files change. Fundamental to software development." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd make-*.tar.gz)
./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}Make installed.${NC}"

# --- Patch (Apply Diffs) ---
explain_step "Building Patch" \
    "Patch applies diff files to source code. When you download a .patch file, this tool applies those changes to your files." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd patch-*.tar.xz)
./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}Patch installed.${NC}"

# --- Tar (Archiver) ---
explain_step "Building Tar" \
    "Tar creates and extracts archives (.tar files). Combined with compression (tar.gz, tar.xz), it's the standard way to distribute source code." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd tar-*.tar.xz)
FORCE_UNSAFE_CONFIGURE=1 \
./configure --prefix=/usr
make
make install
make -C doc install-html docdir=/usr/share/doc/tar
cleanup "$DIR"
echo -e "${GREEN}Tar installed.${NC}"

# --- Texinfo (Documentation System) ---
explain_step "Building Texinfo" \
    "Texinfo is GNU's documentation system. It produces info pages, HTML, and PDF from a single source. The 'info' command reads these docs." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd texinfo-*.tar.xz)
./configure --prefix=/usr
make
make install
make TEXMF=/usr/share/texmf install-tex
cleanup "$DIR"
echo -e "${GREEN}Texinfo installed.${NC}"

# --- Vim (Text Editor) ---
explain_step "Building Vim" \
    "Vim is a powerful text editor - the improved version of vi. It's the editor of choice for many developers. Learning vim is a valuable skill!" \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd vim-*.tar.gz)
echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h
./configure --prefix=/usr
make
make install

# Create vi symlink
ln -sv vim /usr/bin/vi
for L in  /usr/share/man/{,*/}man1/vim.1; do
    ln -sv vim.1 $(dirname $L)/vi.1
done

# Create default vimrc
cat > /etc/vimrc << "EOF"
" Begin /etc/vimrc

" Ensure defaults are set before customizing
source $VIMRUNTIME/defaults.vim
let skip_defaults_vim=1

set nocompatible
set backspace=2
set mouse=
syntax on
if (&term == "xterm") || (&term == "putty")
  set background=dark
endif

" End /etc/vimrc
EOF

cleanup "$DIR"
echo -e "${GREEN}Vim installed.${NC}"

# --- MarkupSafe (Python Module) ---
explain_step "Building MarkupSafe" \
    "MarkupSafe is a Python library for safe string handling in HTML/XML. Required by Jinja2 which is used by many tools." \
    "pip3 wheel ...\npip3 install ..."

DIR=$(extract_and_cd MarkupSafe-*.tar.gz)
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --no-user --find-links dist Markupsafe
cleanup "$DIR"
echo -e "${GREEN}MarkupSafe installed.${NC}"

# --- Jinja2 (Template Engine) ---
explain_step "Building Jinja2" \
    "Jinja2 is a Python template engine. Used by many tools to generate configuration files, documentation, and code." \
    "pip3 wheel ...\npip3 install ..."

DIR=$(extract_and_cd jinja2-*.tar.gz)
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --no-user --find-links dist Jinja2
cleanup "$DIR"
echo -e "${GREEN}Jinja2 installed.${NC}"


#===============================================================================
# SECTION 7: System Utilities
#===============================================================================
# Core system utilities for process management, filesystem, and administration.
#===============================================================================

# --- Coreutils (Core Utilities) ---
explain_step "Building Coreutils" \
    "Coreutils provides the basic file, shell, and text utilities: ls, cp, mv, cat, chmod, chown, etc. These are the commands you use every day." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd coreutils-*.tar.xz)

patch -Np1 -i ../coreutils-*.patch 2>/dev/null || true

autoreconf -fiv
FORCE_UNSAFE_CONFIGURE=1 ./configure \
            --prefix=/usr            \
            --enable-no-install-program=kill,uptime
make
make install

# Move programs to FHS-compliant locations
mv -v /usr/bin/chroot /usr/sbin
mv -v /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8
sed -i 's/"1"/"8"/' /usr/share/man/man8/chroot.8

cleanup "$DIR"
echo -e "${GREEN}Coreutils installed.${NC}"

# --- Check (Unit Test Framework) ---
explain_step "Building Check" \
    "Check is a unit testing framework for C. Used by test suites of various packages to verify correct behavior." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd check-*.tar.gz)
./configure --prefix=/usr --disable-static
make
make docdir=/usr/share/doc/check install
cleanup "$DIR"
echo -e "${GREEN}Check installed.${NC}"

# --- Diffutils (File Comparison) ---
explain_step "Building Diffutils" \
    "Diffutils compares files and shows differences: diff, cmp, sdiff, diff3. Essential for patches and version control." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd diffutils-*.tar.xz)
./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}Diffutils installed.${NC}"

# --- Gawk (GNU Awk) ---
explain_step "Building Gawk" \
    "Gawk is a pattern scanning and processing language. Powerful for text processing and data extraction. The 'awk' command." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd gawk-*.tar.xz)
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}Gawk installed.${NC}"

# --- Findutils (File Finding) ---
explain_step "Building Findutils" \
    "Findutils provides find, locate, and xargs - tools for searching files. 'find' is incredibly powerful for file operations." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd findutils-*.tar.xz)
./configure --prefix=/usr --localstatedir=/var/lib/locate
make
make install
cleanup "$DIR"
echo -e "${GREEN}Findutils installed.${NC}"

# --- Groff (Document Formatting) ---
explain_step "Building Groff" \
    "Groff formats text for output devices. It's used to format man pages. Without groff, 'man' commands won't display properly." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd groff-*.tar.gz)
PAGE=letter ./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}Groff installed.${NC}"

# --- Gzip (Compression) ---
explain_step "Building Gzip" \
    "Gzip provides .gz compression - the most common compression format on Unix. Used by tarballs, logs, and many other files." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd gzip-*.tar.xz)
./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}Gzip installed.${NC}"

# --- IPRoute2 (Network Configuration) ---
explain_step "Building IPRoute2" \
    "IPRoute2 provides modern network configuration tools: ip, ss, bridge, tc. These replace the older ifconfig and netstat." \
    "make NETNS_RUN_DIR=/run/netns\nmake SBINDIR=/usr/sbin install"

DIR=$(extract_and_cd iproute2-*.tar.xz)
sed -i /ARPD/d Makefile
rm -fv man/man8/arpd.8
make NETNS_RUN_DIR=/run/netns
make SBINDIR=/usr/sbin install
cleanup "$DIR"
echo -e "${GREEN}IPRoute2 installed.${NC}"

# --- Kbd (Keyboard Utilities) ---
explain_step "Building Kbd" \
    "Kbd provides keyboard and console font utilities: loadkeys, setfont, etc. Needed to configure keyboard layouts and console fonts." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd kbd-*.tar.xz)

patch -Np1 -i ../kbd-*.patch 2>/dev/null || true
sed -i '/RESIZECONS_PROGS=/s/444444yes/no/' configure
sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in

./configure --prefix=/usr --disable-vlock
make
make install
cleanup "$DIR"
echo -e "${GREEN}Kbd installed.${NC}"

# --- Libpipeline (Pipeline Library) ---
explain_step "Building Libpipeline" \
    "Libpipeline provides a C library for manipulating pipelines of subprocesses. Used by man-db for processing man pages." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd libpipeline-*.tar.gz)
./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}Libpipeline installed.${NC}"

# --- Make (Build Automation) ---
explain_step "Building Make" \
    "Make automates building programs from source. It reads Makefiles and runs the necessary commands. The heart of most build systems." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd make-*.tar.gz)
./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}Make installed.${NC}"

# --- Patch (Apply Diffs) ---
explain_step "Building Patch" \
    "Patch applies diff files to source code. Essential for applying bug fixes and modifications distributed as patches." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd patch-*.tar.xz)
./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}Patch installed.${NC}"

# --- Tar (Archiver) ---
explain_step "Building Tar" \
    "Tar creates and extracts archives (.tar files). Combined with compression (tar.gz, tar.xz), it's the standard Unix archive format." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd tar-*.tar.xz)
FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}Tar installed.${NC}"

# --- Texinfo (Documentation) ---
explain_step "Building Texinfo" \
    "Texinfo produces documentation in multiple formats from a single source. GNU projects use it for their manuals (info pages)." \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd texinfo-*.tar.xz)
./configure --prefix=/usr
make
make install
cleanup "$DIR"
echo -e "${GREEN}Texinfo installed.${NC}"

# --- Vim (Text Editor) ---
explain_step "Building Vim" \
    "Vim is a powerful text editor - the improved version of vi. It's the default editor on many systems. Learning vim is a valuable skill!" \
    "./configure --prefix=/usr\nmake\nmake install"

DIR=$(extract_and_cd vim-*.tar.gz)

echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h

./configure --prefix=/usr
make
make install

# Create vi symlink
ln -sv vim /usr/bin/vi

# Create default vimrc
cat > /etc/vimrc << "EOF"
" Basic vim configuration for LFS
source $VIMRUNTIME/defaults.vim
let skip_defaults_vim=1

set nocompatible
set backspace=2
set mouse=
syntax on
if (&term == "xterm") || (&term == "putty")
  set background=dark
endif
EOF

cleanup "$DIR"
echo -e "${GREEN}Vim installed.${NC}"

# --- MarkupSafe (Python Module) ---
explain_step "Building MarkupSafe" \
    "MarkupSafe is a Python library for safe string handling in HTML/XML. Required by Jinja2 which is used by many tools." \
    "pip3 wheel ...\npip3 install ..."

DIR=$(extract_and_cd MarkupSafe-*.tar.gz)
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --no-user --find-links dist Markupsafe
cleanup "$DIR"
echo -e "${GREEN}MarkupSafe installed.${NC}"

# --- Jinja2 (Template Engine) ---
explain_step "Building Jinja2" \
    "Jinja2 is a Python template engine. Used by many tools including systemd's build system for generating files from templates." \
    "pip3 wheel ...\npip3 install ..."

DIR=$(extract_and_cd jinja2-*.tar.gz)
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --no-user --find-links dist Jinja2
cleanup "$DIR"
echo -e "${GREEN}Jinja2 installed.${NC}"

# --- Systemd (System and Service Manager) ---
explain_step "Building Systemd" \
    "Systemd is the init system and service manager. It starts your system, manages services, handles logging (journald), and much more. This is a BIG build." \
    "meson setup ...\nninja\nninja install"

DIR=$(extract_and_cd systemd-*.tar.gz)

# Apply patches if available
shopt -s nullglob
for patch in ../systemd-*.patch; do
    patch -Np1 -i "$patch"
done
shopt -u nullglob

# Disable building of unneeded components
sed -i -e 's/want_tests != .false./false/' \
       -e 's/want_tests == .true./false/'  \
       meson.build

mkdir -p build && cd build

meson setup ..                  \
      --prefix=/usr             \
      --buildtype=release       \
      -D default-dnssec=no      \
      -D firstboot=false        \
      -D install-tests=false    \
      -D ldconfig=false         \
      -D sysusers=false         \
      -D rpmmacrosdir=no        \
      -D homed=disabled         \
      -D userdb=false           \
      -D man=disabled           \
      -D mode=release           \
      -D pamconfdir=no          \
      -D dev-kvm-mode=0660      \
      -D nobody-group=nogroup   \
      -D sysupdate=disabled     \
      -D ukify=disabled         \
      -D docdir=/usr/share/doc/systemd

ninja
ninja install

# Enable useful systemd features
systemd-machine-id-setup
systemctl preset-all

cleanup "$DIR"
echo -e "${GREEN}Systemd installed.${NC}"

# --- D-Bus (Message Bus) ---
explain_step "Building D-Bus" \
    "D-Bus is a message bus system for inter-process communication. Applications use it to talk to each other and to system services." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd dbus-*.tar.xz)

./configure --prefix=/usr                        \
            --sysconfdir=/etc                    \
            --localstatedir=/var                 \
            --runstatedir=/run                   \
            --enable-user-session                \
            --disable-static                     \
            --disable-doxygen-docs               \
            --disable-xml-docs                   \
            --with-systemduserunitdir=no         \
            --with-systemdsystemunitdir=/usr/lib/systemd/system \
            --docdir=/usr/share/doc/dbus
make
make install

ln -sfv /etc/machine-id /var/lib/dbus

cleanup "$DIR"
echo -e "${GREEN}D-Bus installed.${NC}"

# --- Man-DB (Manual Page Database) ---
explain_step "Building Man-DB" \
    "Man-DB provides the 'man' command for reading manual pages. It indexes and searches man pages efficiently." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd man-db-*.tar.xz)

./configure --prefix=/usr                         \
            --docdir=/usr/share/doc/man-db        \
            --sysconfdir=/etc                     \
            --disable-setuid                      \
            --enable-cache-owner=bin              \
            --with-browser=/usr/bin/lynx          \
            --with-vgrind=/usr/bin/vgrind         \
            --with-grap=/usr/bin/grap
make
make install

cleanup "$DIR"
echo -e "${GREEN}Man-DB installed.${NC}"

# --- Procps-ng (Process Utilities) ---
explain_step "Building Procps-ng" \
    "Procps-ng provides process monitoring tools: ps, top, free, vmstat, pgrep, pkill. Essential for system administration." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd procps-ng-*.tar.xz)

./configure --prefix=/usr                           \
            --docdir=/usr/share/doc/procps-ng       \
            --disable-static                        \
            --disable-kill                          \
            --with-systemd
make
make install

cleanup "$DIR"
echo -e "${GREEN}Procps-ng installed.${NC}"

# --- Util-linux (System Utilities) ---
explain_step "Building Util-linux" \
    "Util-linux provides essential system utilities: mount, fdisk, mkfs, dmesg, lsblk, and many more. Critical for system operation." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd util-linux-*.tar.xz)

./configure --bindir=/usr/bin     \
            --libdir=/usr/lib     \
            --runstatedir=/run    \
            --sbindir=/usr/sbin   \
            --disable-chfn-chsh   \
            --disable-login       \
            --disable-nologin     \
            --disable-su          \
            --disable-setpriv     \
            --disable-runuser     \
            --disable-pylibmount  \
            --disable-liblastlog2 \
            --disable-static      \
            --without-python      \
            ADJTIME_PATH=/var/lib/hwclock/adjtime \
            --docdir=/usr/share/doc/util-linux
make
make install

cleanup "$DIR"
echo -e "${GREEN}Util-linux installed.${NC}"

# --- E2fsprogs (Ext Filesystem Tools) ---
explain_step "Building E2fsprogs" \
    "E2fsprogs provides tools for ext2/ext3/ext4 filesystems: mkfs.ext4, fsck, tune2fs, etc. Essential for managing Linux filesystems." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd e2fsprogs-*.tar.gz)

mkdir -v build && cd build

../configure --prefix=/usr           \
             --sysconfdir=/etc       \
             --enable-elf-shlibs     \
             --disable-libblkid      \
             --disable-libuuid       \
             --disable-uuidd         \
             --disable-fsck
make
make install

# Remove useless static libraries
rm -fv /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a

cleanup "$DIR"
echo -e "${GREEN}E2fsprogs installed.${NC}"


#===============================================================================
# SECTION 8: Linux Kernel
#===============================================================================
# The kernel is the core of the operating system - it manages hardware,
# processes, memory, and provides the interface between software and hardware.
#===============================================================================

explain_step "Building Linux Kernel" \
    "The Linux kernel is the heart of the system. It manages all hardware, processes, memory, and filesystems. This build uses a default config suitable for most systems." \
    "make defconfig\nmake\nmake modules_install"

DIR=$(extract_and_cd linux-*.tar.xz)

make mrproper

# Use default config - good for most x86_64 systems
# For custom hardware, you might want 'make menuconfig' instead
make defconfig

# Build the kernel
make

# Install modules
make modules_install

# Install the kernel
cp -iv arch/x86/boot/bzImage /boot/vmlinuz-lfs
cp -iv System.map /boot/System.map-lfs
cp -iv .config /boot/config-lfs

# Install kernel documentation (optional but educational)
install -d /usr/share/doc/linux
cp -r Documentation/* /usr/share/doc/linux

cleanup "$DIR"
echo -e "${GREEN}Linux kernel installed.${NC}"

#===============================================================================
# SECTION 9: GRUB Bootloader
#===============================================================================
# GRUB loads the kernel at boot time. Without a bootloader, the system
# cannot start - the BIOS/UEFI needs something to hand off control to.
#===============================================================================

explain_step "Building GRUB" \
    "GRUB (GRand Unified Bootloader) loads the Linux kernel at boot. It's the first software that runs after BIOS/UEFI and is responsible for starting your OS." \
    "./configure --prefix=/usr ...\nmake\nmake install"

DIR=$(extract_and_cd grub-*.tar.xz)

# Unset environment variables that can interfere with the build
unset {C,CPP,CXX,LD}FLAGS

./configure --prefix=/usr          \
            --sysconfdir=/etc      \
            --disable-efiemu       \
            --disable-werror
make
make install
mv -v /etc/bash_completion.d/grub /usr/share/bash-completion/completions

cleanup "$DIR"
echo -e "${GREEN}GRUB installed.${NC}"

#===============================================================================
# SECTION 10: System Configuration
#===============================================================================
# Final configuration to make the system bootable and usable.
#===============================================================================

explain_step "Configuring the System" \
    "Now we configure the system: set hostname, create fstab, configure the bootloader, and set the root password." \
    "Various configuration commands..."

# --- Create /etc/fstab ---
# fstab tells the system what filesystems to mount at boot
cat > /etc/fstab << EOF
# /etc/fstab - Static filesystem information
#
# <device>         <mount point>  <type>  <options>         <dump>  <fsck>
${LFS_DISK_PART}2  /              ext4    defaults          1       1
${LFS_DISK_PART}1  swap           swap    pri=1             0       0
proc               /proc          proc    nosuid,noexec,nodev 0     0
sysfs              /sys           sysfs   nosuid,noexec,nodev 0     0
devpts             /dev/pts       devpts  gid=5,mode=620    0       0
tmpfs              /run           tmpfs   defaults          0       0
devtmpfs           /dev           devtmpfs mode=0755,nosuid 0       0
tmpfs              /dev/shm       tmpfs   nosuid,nodev      0       0
cgroup2            /sys/fs/cgroup cgroup2 nosuid,noexec,nodev 0     0
EOF

echo -e "${GREEN}/etc/fstab created.${NC}"

# --- Set hostname ---
echo "lfs" > /etc/hostname

cat > /etc/hosts << "EOF"
127.0.0.1  localhost
127.0.1.1  lfs
::1        localhost ip6-localhost ip6-loopback
ff02::1    ip6-allnodes
ff02::2    ip6-allrouters
EOF

echo -e "${GREEN}Hostname configured.${NC}"

# --- Configure systemd ---
# Set up basic systemd configuration
mkdir -pv /etc/systemd/system/getty@tty1.service.d

cat > /etc/systemd/system/getty@tty1.service.d/noclear.conf << "EOF"
[Service]
TTYVTDisallocate=no
EOF

# --- Configure locale ---
cat > /etc/locale.conf << "EOF"
LANG=en_US.UTF-8
EOF

# Generate locales
localedef -i en_US -f UTF-8 en_US.UTF-8

echo -e "${GREEN}Locale configured.${NC}"

# --- Configure inputrc for readline ---
cat > /etc/inputrc << "EOF"
# /etc/inputrc - Global readline initialization

# Allow 8-bit input
set input-meta on
set output-meta on

# Don't ring bell on completion
set bell-style none

# Show all completions at once
set show-all-if-ambiguous on

# Color completion by file type
set colored-stats on

# Append slash to directory names
set mark-directories on
set mark-symlinked-directories on

# Case-insensitive completion
set completion-ignore-case on
EOF

echo -e "${GREEN}Readline configured.${NC}"

# --- Configure shells ---
cat > /etc/shells << "EOF"
/bin/sh
/bin/bash
EOF

# --- Create os-release ---
cat > /etc/os-release << "EOF"
NAME="Linux From Scratch"
VERSION="12.2"
ID=lfs
PRETTY_NAME="Linux From Scratch 12.2"
VERSION_CODENAME="stable"
HOME_URL="https://www.linuxfromscratch.org/"
EOF

echo -e "${GREEN}OS release info created.${NC}"

# --- Configure GRUB ---
mkdir -pv /boot/grub

cat > /boot/grub/grub.cfg << EOF
# /boot/grub/grub.cfg - GRUB configuration
#
# This file tells GRUB how to boot your system.

set default=0
set timeout=5

# Uncomment for GRUB graphical terminal
#insmod all_video
#terminal_output gfxterm

menuentry "Linux From Scratch" {
    linux /boot/vmlinuz-lfs root=${LFS_DISK_PART}2 ro
}

menuentry "Linux From Scratch (recovery mode)" {
    linux /boot/vmlinuz-lfs root=${LFS_DISK_PART}2 ro single
}
EOF

echo -e "${GREEN}GRUB configuration created.${NC}"

# --- Install GRUB to disk ---
explain_step "Installing GRUB to MBR" \
    "Writing GRUB to the Master Boot Record of ${LFS_DISK}. This makes the disk bootable." \
    "grub-install ${LFS_DISK}"

grub-install ${LFS_DISK}

echo -e "${GREEN}GRUB installed to ${LFS_DISK}.${NC}"

# --- Set root password ---
explain_step "Setting Root Password" \
    "Setting the root password. The default is 'root' - CHANGE THIS after first boot for security!" \
    "echo 'root:root' | chpasswd"

echo "root:root" | chpasswd

echo -e "${GREEN}Root password set to 'root'.${NC}"
echo -e "${YELLOW}WARNING: Change this password after first boot!${NC}"

#===============================================================================
# SECTION 11: Final Cleanup
#===============================================================================

explain_step "Final Cleanup" \
    "Cleaning up temporary files and preparing the system for first boot." \
    "rm -rf /tmp/*"

# Clean up
rm -rf /tmp/*

# Remove static libraries that aren't needed
find /usr/lib /usr/libexec -name \*.la -delete

# Remove temporary toolchain documentation
rm -rf /usr/share/info/dir

#===============================================================================
# BUILD COMPLETE!
#===============================================================================

print_header "LFS Build Complete!"

echo -e "${GREEN}Congratulations! Your Linux From Scratch system is built!${NC}"
echo ""
echo -e "${CYAN}Summary:${NC}"
echo -e "  - Root partition: ${LFS_DISK_PART}2"
echo -e "  - Swap partition: ${LFS_DISK_PART}1"
echo -e "  - Kernel: /boot/vmlinuz-lfs"
echo -e "  - Root password: root (CHANGE THIS!)"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Exit this chroot: type 'exit'"
echo -e "  2. Unmount filesystems (the script will do this)"
echo -e "  3. Reboot: 'reboot'"
echo -e "  4. Remove the installation media"
echo -e "  5. Boot into your new LFS system!"
echo ""
echo -e "${CYAN}After booting:${NC}"
echo -e "  - Change root password: passwd"
echo -e "  - Create a regular user: useradd -m username"
echo -e "  - Set user password: passwd username"
echo -e "  - Configure networking"
echo ""
echo -e "${GREEN}Enjoy your Linux From Scratch system!${NC}"
