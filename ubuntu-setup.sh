#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root (use sudo)."
    exit 1
fi

# Function to display messages
show_message() {
    echo ">>> $1"
}

# Function to check command success
check_status() {
    if [ $? -eq 0 ]; then
        show_message "$1 succeeded"
    else
        show_message "$1 failed" >&2
        exit 1
    fi
}

# Simple progress bar function
progress_bar() {
    local duration=$1
    local message=$2
    local width=20
    local i=0
    show_message "$message..."
    while [ $i -le $width ]; do
        local percent=$(( (i * 100) / width ))
        local filled=$(( (i * width) / width ))
        local empty=$(( width - filled ))
        printf "\r["
        printf "%${filled}s" | tr ' ' '#'
        printf "%${empty}s" | tr ' ' '-'
        printf "] %d%%" $percent
        sleep $(( duration / width ))
        i=$(( i + 1 ))
    done
    echo ""
}

# Function to check if package is installed
is_package_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

# Detect the original user's home directory
if [ "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME="$HOME"
fi
show_message "Using home directory: $USER_HOME"

# Get Ubuntu version
show_message "Detecting Ubuntu version..."
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_CODENAME=$(lsb_release -cs)
show_message "Found Ubuntu $UBUNTU_VERSION ($UBUNTU_CODENAME)"

# Update package lists
show_message "Updating package lists..."
progress_bar 5 "Updating package lists"
apt update -y > /dev/null 2>&1
check_status "Package list update"

# Set PATH for user's private bin
BIN_PATH="$USER_HOME/bin"
if [ -d "$BIN_PATH" ]; then
    PATH="$BIN_PATH:$PATH"
    show_message "Added $BIN_PATH to PATH"
else
    mkdir -p "$BIN_PATH"
    PATH="$BIN_PATH:$PATH"
    show_message "Created and added $BIN_PATH to PATH"
fi

# Set up Android SDK platform-tools
PLATFORM_TOOLS_PATH="$USER_HOME/platform-tools"
if [ ! -d "$PLATFORM_TOOLS_PATH" ]; then
    show_message "Downloading Android SDK platform-tools..."
    apt install -y wget unzip > /dev/null 2>&1
    progress_bar 10 "Downloading and extracting platform-tools"
    wget -q https://dl.google.com/android/repository/platform-tools-latest-linux.zip -O /tmp/platform-tools.zip
    unzip -q /tmp/platform-tools.zip -d "$USER_HOME"
    rm -f /tmp/platform-tools.zip
    check_status "Android SDK platform-tools setup"
else
    show_message "$PLATFORM_TOOLS_PATH already exists, skipping download"
fi
PATH="$PLATFORM_TOOLS_PATH:$PATH"
show_message "Added $PLATFORM_TOOLS_PATH to PATH"

# Base packages (including all requested dependencies)
BASE_PACKAGES="bc bash git-core gnupg build-essential zip curl make automake autogen autoconf autotools-dev libtool shtool python m4 gcc zlib1g-dev flex bison libssl-dev"

# Android ROM/Kernel building packages (added git-lfs explicitly)
ANDROID_PACKAGES="git-core git-lfs gnupg flex bison gperf build-essential zip curl zlib1g-dev gcc-multilib g++-multilib libc6-dev libncurses5-dev x11proto-core-dev libx11-dev lib32z1-dev ccache libgl1-mesa-dev libxml2-utils xsltproc unzip python3 python3-pip lib32ncurses5-dev lib32z1 libssl-dev bc lzop liblz4-tool rsync schedtool squashfs-tools pngcrush repo openjdk-11-jdk"

# Version-specific packages
case $UBUNTU_VERSION in
    16.*)
        ANDROID_PACKAGES="$ANDROID_PACKAGES python-dev python libncurses5-dev"
        ;;
    18.*)
        ANDROID_PACKAGES="$ANDROID_PACKAGES python-dev python libncurses5"
        ;;
    20.*)
        ANDROID_PACKAGES="$ANDROID_PACKAGES python3-dev python-is-python3 libncurses5"
        ;;
    22.*|24.*)
        ANDROID_PACKAGES="$ANDROID_PACKAGES python3-dev python-is-python3 libncurses5"
        ;;
    *)
        ANDROID_PACKAGES="$ANDROID_PACKAGES python3-dev python-is-python3 libncurses5"
        show_message "Warning: Untested Ubuntu version, using default modern package set"
        ;;
esac

# Install base packages
show_message "Installing base packages..."
progress_bar 15 "Installing base packages"
apt install -y $BASE_PACKAGES > /dev/null 2>&1
check_status "Base package installation"

# Install Android ROM/Kernel packages
show_message "Installing Android ROM/Kernel build dependencies..."
progress_bar 20 "Installing Android build packages"
apt install -y $ANDROID_PACKAGES > /dev/null 2>&1
check_status "Android package installation"

# Handle Python for older GCC versions
if [ "$(printf '%s\n' "18.04" "$UBUNTU_VERSION" | sort -V | head -n1)" = "$UBUNTU_VERSION" ]; then
    show_message "Installing Python 2 for older GCC compatibility..."
    progress_bar 5 "Installing Python 2"
    apt install -y python python-dev > /dev/null 2>&1
    check_status "Python 2 installation"
fi

# Configure Git as the original user
show_message "Configuring Git with user details..."
if [ "$SUDO_USER" ]; then
    sudo -u "$SUDO_USER" git config --global user.name "moonwaystar"
    sudo -u "$SUDO_USER" git config --global user.email "197520808+moonwaystar@users.noreply.github.com"
else
    git config --global user.name "moonwaystar"
    git config --global user.email "197520808+moonwaystar@users.noreply.github.com"
fi
check_status "Git configuration"

# Configure Git LFS with additional error handling
show_message "Configuring Git LFS..."
progress_bar 3 "Setting up Git LFS"

# Verify git-lfs is installed
if ! command -v git-lfs >/dev/null 2>&1; then
    show_message "Git LFS not found, attempting manual installation..."
    apt install -y git-lfs > /dev/null 2>&1 || {
        show_message "Installing git-lfs from source..."
        wget -q https://github.com/git-lfs/git-lfs/releases/download/v3.5.1/git-lfs-linux-amd64-v3.5.1.tar.gz -O /tmp/git-lfs.tar.gz
        tar -xzf /tmp/git-lfs.tar.gz -C /tmp
        /tmp/git-lfs-3.5.1/install.sh > /dev/null 2>&1
        rm -rf /tmp/git-lfs.tar.gz /tmp/git-lfs-3.5.1
    }
fi

# Attempt Git LFS initialization
if [ "$SUDO_USER" ]; then
    sudo -u "$SUDO_USER" git lfs install > /dev/null 2>&1
    LFS_STATUS=$?
else
    git lfs install > /dev/null 2>&1
    LFS_STATUS=$?
fi

if [ $LFS_STATUS -eq 0 ]; then
    show_message "Git LFS configuration succeeded"
else
    show_message "Git LFS configuration failed. Trying alternative method..." >&2
    # Alternative method: manual initialization
    if [ "$SUDO_USER" ]; then
        sudo -u "$SUDO_USER" bash -c "git lfs install --force" > /tmp/git-lfs-error.log 2>&1
    else
        bash -c "git lfs install --force" > /tmp/git-lfs-error.log 2>&1
    fi
    
    if [ $? -eq 0 ]; then
        show_message "Git LFS force configuration succeeded"
    else
        show_message "Git LFS configuration failed completely. Error log available at /tmp/git-lfs-error.log" >&2
        exit 1
    fi
fi

# Clean up
show_message "Cleaning up unused packages..."
progress_bar 5 "Cleaning up"
apt autoremove -y > /dev/null 2>&1 && apt autoclean -y > /dev/null 2>&1
check_status "Cleanup"

show_message "Setup complete!"
show_message "Note: To make PATH changes permanent, add these lines to $USER_HOME/.bashrc:"
echo "export PATH=\"$BIN_PATH:\$PATH\""
echo "export PATH=\"$PLATFORM_TOOLS_PATH:\$PATH\""
