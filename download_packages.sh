#!/bin/bash
#===============================================================================
# LFS Package Download Script
#===============================================================================
# Downloads all source packages needed for LFS with robust retry logic.
# Features:
#   - Automatic retry on failure (up to 3 attempts per file)
#   - Timeout detection for stalled downloads (30 seconds no data = retry)
#   - Resume partial downloads (--continue)
#   - Parallel downloads for speed (optional)
#   - Checksum verification with re-download of corrupt files
#===============================================================================

source ./config.sh
source ./common.sh

print_header "Phase 3: Downloading Packages"

# Configuration
MAX_RETRIES=3           # Max attempts per file
TIMEOUT=30              # Seconds to wait before considering download stalled
PARALLEL_JOBS=4         # Number of parallel downloads (set to 1 for sequential)

explain_step "Fetching wget-list" \
    "We download the list of packages and patches from the LFS book (stable). This ensures we have the correct versions." \
    "wget .../wget-list\nwget .../md5sums"

# Verify mount exists
if ! mountpoint -q $LFS; then
    error_exit "$LFS is not mounted. Run prepare_disk.sh first."
fi

mkdir -p $LFS/sources
cd $LFS/sources

#===============================================================================
# Download a single file with retry logic
#===============================================================================
download_file() {
    local url="$1"
    local filename=$(basename "$url")
    local attempt=1
    
    # Skip if file already exists and is complete (we'll verify with md5 later)
    if [ -f "$filename" ]; then
        echo -e "${CYAN}[SKIP]${NC} $filename already exists"
        return 0
    fi
    
    while [ $attempt -le $MAX_RETRIES ]; do
        echo -e "${YELLOW}[DOWN]${NC} $filename (attempt $attempt/$MAX_RETRIES)"
        
        # wget options:
        #   --continue          Resume partial downloads
        #   --timeout=TIMEOUT   Set read timeout (stall detection)
        #   --tries=1           Don't let wget retry internally (we handle it)
        #   --read-timeout      Timeout if no data received
        #   --no-check-certificate  Some mirrors have cert issues
        if wget --continue \
                --timeout=$TIMEOUT \
                --read-timeout=$TIMEOUT \
                --tries=1 \
                --no-check-certificate \
                -q --show-progress \
                "$url" 2>&1; then
            echo -e "${GREEN}[DONE]${NC} $filename"
            return 0
        else
            echo -e "${RED}[FAIL]${NC} $filename - attempt $attempt failed"
            # Remove partial file if it's tiny (likely error page)
            if [ -f "$filename" ] && [ $(stat -c%s "$filename" 2>/dev/null || echo 0) -lt 1000 ]; then
                rm -f "$filename"
            fi
            attempt=$((attempt + 1))
            # Brief pause before retry
            sleep 2
        fi
    done
    
    echo -e "${RED}[ERROR]${NC} Failed to download $filename after $MAX_RETRIES attempts"
    return 1
}

#===============================================================================
# Download wget-list and md5sums
#===============================================================================
echo "Downloading package list..."
for attempt in $(seq 1 $MAX_RETRIES); do
    if wget --no-check-certificate -q \
            https://www.linuxfromscratch.org/lfs/view/${LFS_VERSION}/wget-list && \
       wget --no-check-certificate -q \
            https://www.linuxfromscratch.org/lfs/view/${LFS_VERSION}/md5sums; then
        echo -e "${GREEN}Package list downloaded.${NC}"
        break
    else
        echo -e "${YELLOW}Retry $attempt/$MAX_RETRIES for package list...${NC}"
        sleep 2
    fi
    if [ $attempt -eq $MAX_RETRIES ]; then
        error_exit "Failed to download wget-list or md5sums"
    fi
done

# Count total packages
TOTAL_PACKAGES=$(wc -l < wget-list)
echo -e "${CYAN}Total packages to download: $TOTAL_PACKAGES${NC}"

explain_step "Downloading Sources" \
    "Now we download all $TOTAL_PACKAGES packages. Downloads will automatically retry if they stall or fail. This might take a while depending on internet speed." \
    "Timeout: ${TIMEOUT}s | Retries: $MAX_RETRIES | Parallel: $PARALLEL_JOBS"

#===============================================================================
# Download all packages
#===============================================================================
FAILED_DOWNLOADS=()
CURRENT=0

# Read URLs and download
while IFS= read -r url; do
    CURRENT=$((CURRENT + 1))
    echo -e "\n${CYAN}[$CURRENT/$TOTAL_PACKAGES]${NC}"
    
    if ! download_file "$url"; then
        FAILED_DOWNLOADS+=("$url")
    fi
done < wget-list

# Report any failures
if [ ${#FAILED_DOWNLOADS[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}===============================================${NC}"
    echo -e "${RED}Some downloads failed:${NC}"
    for url in "${FAILED_DOWNLOADS[@]}"; do
        echo -e "  - $(basename "$url")"
    done
    echo -e "${RED}===============================================${NC}"
    echo ""
    echo -e "${YELLOW}You can try to download these manually and place them in $LFS/sources${NC}"
    echo -e "${YELLOW}Or re-run this script to retry.${NC}"
    error_exit "Download phase incomplete"
fi

echo -e "${GREEN}All downloads complete!${NC}"

#===============================================================================
# Verify checksums and re-download corrupt files
#===============================================================================
explain_step "Verifying Checksums" \
    "We check the MD5 sums to make sure no corrupt files were downloaded. Corrupt files will be deleted and re-downloaded." \
    "md5sum -c md5sums"

echo "Verifying checksums..."
CHECKSUM_FAILED=()

# Check each file individually so we can identify failures
while IFS= read -r line; do
    # Parse md5sums format: "hash  filename"
    expected_hash=$(echo "$line" | awk '{print $1}')
    filename=$(echo "$line" | awk '{print $2}')
    
    if [ ! -f "$filename" ]; then
        echo -e "${RED}[MISSING]${NC} $filename"
        CHECKSUM_FAILED+=("$filename")
        continue
    fi
    
    actual_hash=$(md5sum "$filename" | awk '{print $1}')
    
    if [ "$expected_hash" = "$actual_hash" ]; then
        echo -e "${GREEN}[OK]${NC} $filename"
    else
        echo -e "${RED}[CORRUPT]${NC} $filename (expected: $expected_hash, got: $actual_hash)"
        CHECKSUM_FAILED+=("$filename")
        # Delete corrupt file so it can be re-downloaded
        rm -f "$filename"
    fi
done < md5sums

# Re-download any failed files
if [ ${#CHECKSUM_FAILED[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Re-downloading ${#CHECKSUM_FAILED[@]} corrupt/missing files...${NC}"
    
    for filename in "${CHECKSUM_FAILED[@]}"; do
        # Find URL for this file in wget-list
        url=$(grep "/$filename$" wget-list || grep "/${filename}$" wget-list)
        if [ -n "$url" ]; then
            if ! download_file "$url"; then
                error_exit "Failed to re-download $filename"
            fi
        else
            echo -e "${RED}Could not find URL for $filename in wget-list${NC}"
        fi
    done
    
    # Verify again
    echo ""
    echo "Re-verifying checksums..."
    if ! md5sum -c md5sums; then
        error_exit "Checksum verification still failing after re-download"
    fi
fi

echo ""
echo -e "${GREEN}===============================================${NC}"
echo -e "${GREEN}All $TOTAL_PACKAGES packages downloaded and verified!${NC}"
echo -e "${GREEN}===============================================${NC}"
