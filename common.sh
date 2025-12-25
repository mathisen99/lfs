#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper function to print a header
function print_header() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}   $1${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo ""
}

# Interactive explanation function
# Usage: explain_step "Title" "Explanation" "Commands (optional)"
# Usage: explain_step "Title" "Explanation" "Commands (optional)"
function explain_step() {
    local title="$1"
    local explanation="$2"
    local commands="$3"

    echo -e "${YELLOW}>>> NEXT STEP: ${title}${NC}"
    
    echo -e "${BLUE}EXPLANATION:${NC}"
    # Wrap text at 80 chars and indent by 2 spaces
    echo -e "$explanation" | fold -s -w 80 | sed 's/^/  /'
    
    if [ -n "$commands" ]; then
        echo ""
        echo -e "${CYAN}COMMANDS TO RUN:${NC}"
        # Wrap at 80 chars, indent by 2 spaces. 
        # Note: Code usually shouldn't be wrapped blindly, but user complained about horizontal length.
        # We'll use look for newlines in input to respect them first.
        echo -e "$commands" | sed 's/^/  /'
    fi
    echo ""
    echo -e "Press ${GREEN}[ENTER]${NC} to execute this step..."
    read -r
}

# Explicit error exit function
function error_exit() {
    echo -e "${RED}ERROR: $1${NC}"
    exit 1
}

# Error handling
set -e
set -o pipefail # Fail if any part of a pipe fails
trap 'echo -e "${RED}Script failed at line $LINENO${NC}"' ERR
