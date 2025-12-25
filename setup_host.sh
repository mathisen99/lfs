#!/bin/bash
source ./config.sh
source ./common.sh

print_header "Phase 1: Host System Setup & Strict Verification"

explain_step "Checking for Required User (Root)" \
    "LFS formatting and mounting requires root privileges. We need to be root to proceed." \
    "if [ \"\$EUID\" -ne 0 ]; then error_exit ...; fi"

if [ "$EUID" -ne 0 ]; then 
    error_exit "Please run as root."
fi

explain_step "Updating System Clock" \
    "Compiling software can fail or have weird errors if the system clock is significantly wrong." \
    "timedatectl set-ntp true"

timedatectl set-ntp true || echo "Warning: timedatectl failed, proceeding if date is correct."
echo -e "${GREEN}Time updated.${NC}"

explain_step "Expanding RAM Filesystem" \
    "The Arch ISO default filesystem size is small. We will dynamically find the backing COW filesystem and resize it using our verified Swap space." \
    "mount -o remount,size=8G <detected_cow_path>\nmkdir -p /mnt/lfs/cache/pacman"

# Smart COW Resize Function
function resize_cow() {
    echo "Attempting to detect COW device..."
    
    # 1. Find the upperdir of the root overlay
    # This is usually something like /run/archiso/cowspace/upper
    UPPERDIR=$(grep "overlay / " /proc/mounts | grep -o 'upperdir=[^,]*' | cut -d= -f2)
    
    if [ -z "$UPPERDIR" ]; then
        echo "Could not detect overlay upperdir from /proc/mounts. Trying standard paths..."
        # Fallback to standard paths if parsing failed
        for path in /run/archiso/cowspace /run/archiso/cow; do
            if mountpoint -q "$path"; then
                echo "Found standard path: $path"
                mount -o remount,size=8G "$path" && return 0
            fi
        done
        return 1
    fi
    
    echo "Found upperdir at: $UPPERDIR"
    
    # 2. Find the mount point for that directory
    # effective mount point for /run/archiso/cowspace/upper is /run/archiso/cowspace
    COW_MOUNT=$(df --output=target "$UPPERDIR" | tail -n1)
    
    if [ -z "$COW_MOUNT" ]; then
        echo "Could not determine mount point for $UPPERDIR"
        return 1
    fi
    
    echo "Detected COW mount point: $COW_MOUNT"
    
    # 3. Resize it
    if mount -o remount,size=8G "$COW_MOUNT"; then
        echo -e "${GREEN}Successfully resized $COW_MOUNT to 8G.${NC}"
        # detailed check
        df -h "$COW_MOUNT"
        return 0
    else
        echo -e "${RED}Failed to resize $COW_MOUNT.${NC}"
        return 1
    fi
}

if ! resize_cow; then
    echo -e "${RED}Warning: COW resize failed. We will try to proceed but might run out of space.${NC}"
    echo "Manual workaround: mount -o remount,size=8G /run/archiso/cowspace (or correct path)"
fi

# 2. Use physical disk for download cache to save RAM
mkdir -p /mnt/lfs/cache/pacman

explain_step "Installing Dependencies" \
    "Installing base-devel and toolchain using the physical disk for cache." \
    "pacman -Sy ... --cachedir /mnt/lfs/cache/pacman"

# Force refresh and install needed tools
pacman -Sy --noconfirm --needed --cachedir /mnt/lfs/cache/pacman base-devel bison gawk texinfo wget sudo || error_exit "Failed to install dependencies via pacman."

explain_step "Strict Host Requirement Check" \
    "Verifying that all tools meet the exact version requirements specified in LFS Chapter 2.2. The script will STOP if any check fails." \
    "# Runs a series of version checks, e.g.:\nbash --version | head -n1\nld --version | head -n1\nbison --version | head -n1\n..."

# Strict Version Check Function
function check_version() {
    local tool=$1
    local current=$2
    local required=$3
    
    # Use sort -V to compare versions. 
    # If the lowest version in the sorted list of (current, required) is the required one, then current >= required.
    if [ "$(printf '%s\n' "$required" "$current" | sort -V | head -n1)" = "$required" ]; then 
        echo -e "${GREEN}[PASS] $tool: $current >= $required${NC}"
    else
        echo -e "${RED}[FAIL] $tool: $current < $required${NC}"
        error_exit "Requirement failed: $tool version $current is too old. Please upgrade manually."
    fi
}

# --- Bash ---
bash_ver=$(bash --version | head -n1 | cut -d" " -f4 | cut -d"(" -f1)
check_version "Bash" "$bash_ver" "3.2"

# --- Binutils ---
binutils_ver=$(ld --version | head -n1 | cut -d" " -f7)
check_version "Binutils" "$binutils_ver" "2.13.1"

# --- Bison ---
bison_ver=$(bison --version | head -n1 | cut -d" " -f4)
check_version "Bison" "$bison_ver" "2.7"

# --- Coreutils (chown as proxy) ---
# some distros output "chown (GNU coreutils) 9.1", others just 9.1
chown_ver=$(chown --version | head -n1 |  awk '{print $NF}')
check_version "Coreutils" "$chown_ver" "6.9"

# --- Diffutils ---
diff_ver=$(diff --version | head -n1 | awk '{print $NF}')
check_version "Diffutils" "$diff_ver" "2.8.1"

# --- Findutils ---
find_ver=$(find --version | head -n1 | awk '{print $NF}')
check_version "Findutils" "$find_ver" "4.2.31"

# --- Gawk ---
gawk_ver=$(gawk --version | head -n1 | cut -d" " -f3 | cut -d"," -f1)
check_version "Gawk" "$gawk_ver" "4.0.1"

# --- GCC ---
gcc_ver=$(gcc --version | head -n1 | cut -d" " -f3)
check_version "GCC" "$gcc_ver" "4.8"

# --- Glibc ---
# ldd output: "ldd (GNU libc) 2.39"
glibc_ver=$(ldd --version | head -n1 | awk '{print $NF}')
check_version "Glibc" "$glibc_ver" "2.11"

# --- Grep ---
grep_ver=$(grep --version | head -n1 | awk '{print $NF}')
check_version "Grep" "$grep_ver" "2.5.1a"

# --- Gzip ---
gzip_ver=$(gzip --version | head -n1 | awk '{print $NF}')
check_version "Gzip" "$gzip_ver" "1.3.12"

# --- Make ---
make_ver=$(make --version | head -n1 | cut -d" " -f3 | cut -d"," -f1)
check_version "Make" "$make_ver" "3.81"

# --- Patch ---
patch_ver=$(patch --version | head -n1 | awk '{print $NF}')
check_version "Patch" "$patch_ver" "2.5.4"

# --- Perl ---
perl_ver=$(perl -V:version | cut -d"'" -f2)
check_version "Perl" "$perl_ver" "5.8.8"

# --- Python ---
python_ver=$(python3 --version | cut -d" " -f2)
check_version "Python" "$python_ver" "3.4"

# --- Sed ---
sed_ver=$(sed --version | head -n1 | awk '{print $NF}')
check_version "Sed" "$sed_ver" "4.1.5"

# --- Tar ---
tar_ver=$(tar --version | head -n1 | awk '{print $NF}')
check_version "Tar" "$tar_ver" "1.22"

# --- Texinfo ---
texinfo_ver=$(makeinfo --version | head -n1 | awk '{print $NF}')
check_version "Texinfo" "$texinfo_ver" "4.7"

# --- Xz ---
xz_ver=$(xz --version | head -n1 | awk '{print $NF}')
check_version "Xz" "$xz_ver" "5.0.0"

echo -e "${GREEN}All Host Requirements Met!${NC}"
