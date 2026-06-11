#!/bin/bash

##########################################################
#  ______         ___           _        _ _
# |__  (_) __ _  |_ _|_ __  ___| |_ __ _| | | ___ _ __
#   / /| |/ _` |  | || '_ \/ __| __/ _` | | |/ _ \ '__|
#  / /_| | (_| |  | || | | \__ \ || (_| | | |  __/ |
# /____|_|\__, | |___|_| |_|___/\__\__,_|_|_|\___|_|
#         |___/
##########################################################
# All credit goes to Drewgrif a.k.a. JustAGuyLinux
# Youtube Channel: https://www.youtube.com/@JustAGuyLinux
# Github Link: https://github.com/drewgrif/myghostty
##########################################################
# This should work on most Debian-based systems
##########################################################

# Create a temporary directory for the build
cleanup() {
    echo "Cleaning up temporary directory: $TMP_DIR"
    rm -rf "$TMP_DIR"
}

TMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TMP_DIR"

# Register cleanup function to run on exit
trap cleanup EXIT

# Default to dev version unless --stable is passed
INSTALL_STABLE=false
for arg in "$@"; do
    if [ "$arg" = "--stable" ]; then
        INSTALL_STABLE=true
    fi
done

# Fetch the latest version from index.json
if [ "$INSTALL_STABLE" = true ]; then
    ZIG_REQUIRED_VERSION=$(curl -sL https://ziglang.org/download/index.json | grep -oP '"version": "\K[^"]+' | grep -v '\-dev' | sort -V | tail -n 1)
else
    ZIG_REQUIRED_VERSION=$(curl -sL https://ziglang.org/download/index.json | grep -oP '"version": "\K[^"]+' | grep '\-dev' | sort -V | tail -n 1)
fi

if [ -z "$ZIG_REQUIRED_VERSION" ]; then
    echo "ERROR: Failed to fetch Zig version from index.json."
    exit 1
fi

echo "Installing Zig version: $ZIG_REQUIRED_VERSION"

# Function to compare two version strings (e.g., "0.15.0", "0.15.1")
# Returns: -1 if v1 < v2, 0 if v1 = v2, 1 if v1 > v2
version_compare() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo "ERROR: version_compare requires two arguments." >&2
        exit 1
    fi
    local v1=$1
    local v2=$2

    # Check if either version is a dev version
    local is_v1_dev=false
    local is_v2_dev=false

    if [ "$(echo "$v1" | grep -c '\-dev')" -gt 0 ]; then
        is_v1_dev=true
    fi

    if [ "$(echo "$v2" | grep -c '\-dev')" -gt 0 ]; then
        is_v2_dev=true
    fi

    # If one version is dev and the other is not, dev is always newer
    if [ "$is_v1_dev" != "$is_v2_dev" ]; then
        if [ "$is_v1_dev" = true ]; then
            echo 1  # v1 is dev, so it's newer
        else
            echo -1 # v2 is dev, so it's newer
        fi
        return
    fi

    # If both are dev or both are stable, compare numerically
    if printf '%s\n' "$v1" "$v2" | sort -V | head -n1 | grep -q "$v1"; then
        [ "$v1" = "$v2" ] && echo 0 || echo -1
    else
        echo 1
    fi
}

# Function to check zig version
check_zig_version() {
    installed_version=$(zig version 2>/dev/null || echo "0.0.0")
    echo "INSTALLED VERSION: $installed_version"
    # Use the version_compare function to determine if an upgrade is needed.
    case $(version_compare "$installed_version" "$ZIG_REQUIRED_VERSION") in
        -1) return 1 ;; # Installed version is less than required, so an upgrade/install is needed.
        *) return 0 ;;   # Installed version is sufficient (equal or greater).
    esac
}

# Main Function
if command -v zig &> /dev/null && check_zig_version; then
    echo "Zig $ZIG_REQUIRED_VERSION or higher is already installed."
    exit 0
else
    echo "Downloading and installing Zig $ZIG_REQUIRED_VERSION..."
    cd "$TMP_DIR" || exit 1

    # Determine which download tool is available (wget or curl)
    DOWNLOADER=""
    if command -v wget &> /dev/null; then
        DOWNLOADER="wget"
    elif command -v curl &> /dev/null; then
        DOWNLOADER="curl"
    else
        echo "ERROR: Neither 'wget' nor 'curl' is installed. Please install one of them manually or ensure it's in your PATH."
        exit 1
    fi

    # Detect system architecture
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) ARCH="x86_64" ;;
        aarch64) ARCH="aarch64" ;;
        *) echo "ERROR: Unsupported architecture: $ARCH"; exit 1 ;;
    esac

    # grab the zig binary package from the official url
    DIR_PREFIX = "builds"
    if [ "$INSTALL_STABLE" = true ]; then
        DIR_PREFIX="download/${ZIG_REQUIRED_VERSION}"
    fi
        
    ZIG_ARCHIVE_NAME="zig-${ARCH}-linux-${ZIG_REQUIRED_VERSION}.tar.xz"
    ZIG_URL="https://ziglang.org/${DIR_PREFIX}/${ZIG_ARCHIVE_NAME}"
    echo "Attempting to download Zig from: $ZIG_URL using $DOWNLOADER..."
    if [ "$DOWNLOADER" = "wget" ]; then
        wget "$ZIG_URL" -O "$ZIG_ARCHIVE_NAME" || { echo "ERROR: Wget download failed! Check URL or network connection or if the version ($ZIG_REQUIRED_VERSION) is correct."; exit 1; }
    elif [ "$DOWNLOADER" = "curl" ]; then
        curl -L -o "$ZIG_ARCHIVE_NAME" "$ZIG_URL" || { echo "ERROR: Curl download failed! Check URL or network connection or if the version ($ZIG_REQUIRED_VERSION) is correct."; exit 1; }
    fi

    # unpack the archive
    tar -xf "$ZIG_ARCHIVE_NAME" || { echo "ERROR: Failed to extract archive '$ZIG_ARCHIVE_NAME'!"; exit 1; }

    # Find the extracted directory dynamically
    EXTRACTED_DIR=$(find "$TMP_DIR" -maxdepth 1 -type d -name "zig-*-linux-*" -print -quit)
    if [ -z "$EXTRACTED_DIR" ]; then
        echo "ERROR: Could not find extracted Zig directory matching 'zig-*-linux-*' in $TMP_DIR after extraction."
        exit 1
    fi

    # Extract just the name of the directory
    EXTRACTED_DIR_NAME=$(basename "$EXTRACTED_DIR")

    # Remove existing /usr/local/zig if it exists to ensure a clean install
    if [ -d "/usr/local/zig" ]; then
        echo "Removing existing Zig installation at /usr/local/zig..."
        sudo rm -rf /usr/local/zig || { echo "ERROR: Failed to remove old Zig installation!"; exit 1; }
    fi

    # Move it to system PATH
    echo "Moving '$EXTRACTED_DIR_NAME' to /usr/local/zig..."
    sudo mv "$EXTRACTED_DIR_NAME" /usr/local/zig || { echo "ERROR: Failed to move Zig directory to /usr/local/zig! Check permissions."; exit 1; }
    sudo ln -sf /usr/local/zig/zig /usr/local/bin/zig || { echo "ERROR: Failed to create symlink /usr/local/bin/zig -> /usr/local/zig/zig! Check permissions."; exit 1; }

    echo "Zig $ZIG_REQUIRED_VERSION installed successfully."
fi

# Verify Zig installation
zig version || { echo "ERROR: Zig installation failed!"; exit 1; }
echo "Zig is successfully installed and accessible."
