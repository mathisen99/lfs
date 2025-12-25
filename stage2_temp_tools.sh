#!/bin/bash

# Run as root
source ./config.sh
source ./common.sh

print_header "Phase 5: Stage 2 Setup (Temp Tools)"

explain_step "Preparing for Stage 2" \
    "Copying the Stage 2 build script to the lfs user's home directory."

cp -v stage2_build.sh /home/lfs/
chown lfs:lfs /home/lfs/stage2_build.sh

explain_step "Starting Stage 2 Builds" \
    "Swapping to 'lfs' user to build the temporary tools (Bash, Coreutils, etc.)."

su - lfs -c "bash /home/lfs/stage2_build.sh"

echo -e "${GREEN}Stage 2 Complete.${NC}"
