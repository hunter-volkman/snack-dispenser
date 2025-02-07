#!/bin/bash
# uninstall-greengrass.sh
# Removes AWS Greengrass core installation and cleans up associated resources
# Reverses the setup performed by greengrass-install.sh

set -e
set -o pipefail

# Color output (matching install script style)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
INFO="${GREEN}[INFO]${NC}"
WARN="${YELLOW}[WARN]${NC}"
ERROR="${RED}[ERROR]${NC}"

# Constants
GREENGRASS_ROOT="/greengrass/v2"
CONFIG_FILE="greengrass-config.json"

# Check root privileges
if [ "$EUID" -ne 0 ]; then
    echo -e "${ERROR} Please run as root (sudo -E $0)"
    exit 1
fi

# Stop and remove Greengrass service
remove_service() {
    echo -e "${INFO} Stopping and removing Greengrass service..."
    
    if systemctl is-active --quiet greengrass.service; then
        echo -e "${INFO} Stopping Greengrass service..."
        systemctl stop greengrass.service
    fi
    
    if systemctl is-enabled --quiet greengrass.service; then
        echo -e "${INFO} Disabling Greengrass service..."
        systemctl disable greengrass.service
    fi
    
    # Remove service file
    if [ -f "/etc/systemd/system/greengrass.service" ]; then
        rm -f "/etc/systemd/system/greengrass.service"
        systemctl daemon-reload
    fi
}

# Remove Greengrass directories and files
remove_greengrass_files() {
    echo -e "${INFO} Removing Greengrass directories and files..."
    
    # Stop any running Greengrass processes
    if pgrep -f "greengrass" > /dev/null; then
        echo -e "${INFO} Stopping Greengrass processes..."
        pkill -f "greengrass"
        sleep 5
    fi
    
    # Remove Greengrass root directory
    if [ -d "$GREENGRASS_ROOT" ]; then
        echo -e "${INFO} Removing Greengrass root directory..."
        rm -rf "$GREENGRASS_ROOT"
    fi
}

# Remove system user and group
remove_system_user() {
    echo -e "${INFO} Removing system user and group..."
    
    # Remove user if exists
    if id -u ggc_user > /dev/null 2>&1; then
        userdel ggc_user
    fi
    
    # Remove group if exists
    if getent group ggc_group > /dev/null; then
        groupdel ggc_group
    fi
}

# Clean up dependencies (optional)
cleanup_dependencies() {
    echo -e "${WARN} Do you want to remove installed dependencies (Java, Python3-pip, jq, unzip)? [y/N]"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "${INFO} Removing dependencies..."
        apt-get remove -y openjdk-17-jre-headless python3-pip jq unzip
        apt-get autoremove -y
    else
        echo -e "${INFO} Skipping dependency removal"
    fi
}

# Verify uninstallation
verify_uninstallation() {
    echo -e "${INFO} Verifying uninstallation..."
    local errors=0
    
    # Check if service exists
    if systemctl list-unit-files | grep -q "greengrass.service"; then
        echo -e "${ERROR} Greengrass service still exists"
        errors=$((errors + 1))
    fi
    
    # Check if processes are running
    if pgrep -f "greengrass" > /dev/null; then
        echo -e "${ERROR} Greengrass processes still running"
        errors=$((errors + 1))
    fi
    
    # Check if directories exist
    if [ -d "$GREENGRASS_ROOT" ]; then
        echo -e "${ERROR} Greengrass directory still exists"
        errors=$((errors + 1))
    fi
    
    # Return status
    return $errors
}

# Main uninstallation process
main() {
    echo "🧹 Uninstalling AWS Greengrass Core..."
    
    # Confirm uninstallation
    echo -e "${WARN} This will completely remove Greengrass and its configuration. Continue? [y/N]"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo -e "${INFO} Uninstallation cancelled"
        exit 0
    fi
    
    # Run uninstallation steps
    remove_service
    remove_greengrass_files
    remove_system_user
    cleanup_dependencies
    
    # Verify uninstallation
    if verify_uninstallation; then
        echo -e "\n${GREEN}✅ Greengrass uninstallation completed successfully!${NC}"
    else
        echo -e "\n${WARN} Uninstallation completed with warnings. Please check the messages above."
    fi
    
    echo -e "${INFO} You can now run greengrass-install.sh again if desired."
}

# Run main function
main