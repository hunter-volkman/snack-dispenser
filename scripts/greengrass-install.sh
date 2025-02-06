#!/bin/bash
# greengrass-install.sh
# Handles local Greengrass core installation and configuration
# Must be run after aws-setup.sh

set -e
set -o pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
INFO="${GREEN}[INFO]${NC}"
WARN="${YELLOW}[WARN]${NC}"
ERROR="${RED}[ERROR]${NC}"

# Config file and directories
CONFIG_FILE="greengrass-config.json"
GREENGRASS_ROOT="/greengrass/v2"
NUCLEUS_VERSION="2.13.0"  # Specify version for consistency

# Check root privileges
if [ "$EUID" -ne 0 ]; then
    echo -e "${ERROR} Please run as root (sudo -E $0)"
    exit 1
fi

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${ERROR} Configuration file $CONFIG_FILE not found!"
    echo "Please run aws-setup.sh first"
    exit 1
fi

# Load config values
THING_NAME=$(jq -r '.thingName' "$CONFIG_FILE")
REGION=$(jq -r '.region' "$CONFIG_FILE")
CERTS_DIR=$(jq -r '.certsDir' "$CONFIG_FILE")

# Verify certificates exist
verify_certificates() {
    echo -e "${INFO} Verifying certificates..."
    
    local required_files=("device.pem.crt" "private.pem.key" "root.ca.pem")
    for file in "${required_files[@]}"; do
        if [ ! -f "${CERTS_DIR}/${file}" ]; then
            echo -e "${ERROR} Required certificate file ${CERTS_DIR}/${file} not found!"
            echo "Please run aws-setup.sh first"
            exit 1
        fi
    done
}

# Install system dependencies
install_dependencies() {
    echo -e "${INFO} Installing system dependencies..."
    
    # Update package list
    apt-get update
    
    # Install Java (OpenJDK 17 for Debian Bookworm/Raspberry Pi OS)
    if ! command -v java &> /dev/null; then
        echo -e "${INFO} Installing Java..."
        apt-get install -y openjdk-17-jre-headless
    fi
    
    # Install other required packages
    apt-get install -y python3-pip jq unzip
}

# Set up system user and group
setup_system_user() {
    echo -e "${INFO} Setting up system user and group..."
    
    # Create group if it doesn't exist
    if ! getent group ggc_group > /dev/null; then
        groupadd --system ggc_group
    fi
    
    # Create user if it doesn't exist
    if ! id -u ggc_user > /dev/null 2>&1; then
        useradd --system --no-create-home --shell /bin/false ggc_user -G ggc_group
    fi
}

# Set up Greengrass directories
setup_directories() {
    echo -e "${INFO} Setting up Greengrass directories..."
    
    # Create main directories
    mkdir -p "$GREENGRASS_ROOT"
    mkdir -p "$GREENGRASS_ROOT/config"
    mkdir -p "$GREENGRASS_ROOT/device_credentials"
    
    # Copy certificates
    cp "${CERTS_DIR}/device.pem.crt" "$GREENGRASS_ROOT/device_credentials/"
    cp "${CERTS_DIR}/private.pem.key" "$GREENGRASS_ROOT/device_credentials/"
    cp "${CERTS_DIR}/root.ca.pem" "$GREENGRASS_ROOT/device_credentials/"
    
    # Set permissions
    chown -R ggc_user:ggc_group "$GREENGRASS_ROOT"
    chmod 740 "$GREENGRASS_ROOT/device_credentials/"*
}

# Download and install Greengrass
install_greengrass() {
    echo -e "${INFO} Installing Greengrass..."
    
    # Download installer
    echo -e "${INFO} Downloading Greengrass nucleus..."
    curl -s https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip -o greengrass-nucleus.zip
    unzip -q -o greengrass-nucleus.zip -d GreengrassInstaller
    
    # Install Greengrass nucleus
    echo -e "${INFO} Running Greengrass installer..."
    java -Droot="$GREENGRASS_ROOT" \
         -Dlog.store=FILE \
         -jar ./GreengrassInstaller/lib/Greengrass.jar \
         --aws-region "$REGION" \
         --thing-name "$THING_NAME" \
         --component-default-user "ggc_user:ggc_group" \
         --provision true \
         --setup-system-service true \
         --deploy-dev-tools true
    
    # Clean up installer files
    rm -rf GreengrassInstaller
    rm -f greengrass-nucleus.zip
}

# Set up and start system service
setup_service() {
    echo -e "${INFO} Setting up Greengrass service..."
    
    # Enable service
    systemctl enable greengrass.service
    
    # Start service
    systemctl start greengrass.service
    
    # Wait for service to start
    echo -e "${INFO} Waiting for Greengrass service to start..."
    sleep 10
    
    # Check service status
    if systemctl is-active --quiet greengrass.service; then
        echo -e "${INFO} Greengrass service is running"
    else
        echo -e "${ERROR} Greengrass service failed to start!"
        echo "Check logs with: sudo tail -f /greengrass/v2/logs/greengrass.log"
        exit 1
    fi
}

# Verify installation
verify_installation() {
    echo -e "${INFO} Verifying installation..."
    
    # Check if Greengrass is running
    if ! pgrep -f "greengrass" > /dev/null; then
        echo -e "${ERROR} Greengrass process not found!"
        exit 1
    fi
    
    # Check log file
    if [ -f "$GREENGRASS_ROOT/logs/greengrass.log" ]; then
        echo -e "${INFO} Log file created successfully"
    else
        echo -e "${ERROR} Log file not found!"
        exit 1
    fi
}

# Main installation process
main() {
    echo "🚀 Installing AWS Greengrass Core..."
    
    # Run installation steps
    verify_certificates
    install_dependencies
    setup_system_user
    setup_directories
    install_greengrass
    setup_service
    verify_installation
    
    echo -e "\n${GREEN}✅ Greengrass installation completed successfully!${NC}"
    echo -e "${INFO} Next steps:"
    echo "1. Check Greengrass status: sudo systemctl status greengrass"
    echo "2. View logs: sudo tail -f /greengrass/v2/logs/greengrass.log"
    echo "3. Deploy components using component-deploy.sh"
}

# Run main function
main