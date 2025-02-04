#!/bin/bash
# ============================================================================
# Edge Snack Dispenser - Basic Raspberry Pi Setup
# Sets up base system requirements for the Edge Snack Dispenser project.
# ============================================================================

set -e  # Exit on error

# Check if running on Raspberry Pi
if ! grep -q "Raspberry Pi" /proc/cpuinfo; then
    echo "This script must be run on a Raspberry Pi"
    exit 1
fi

echo "Setting up Edge Snack Dispenser base system..."

# Update system and install required packages
echo "Installing system dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
    python3-pip \
    python3-venv \
    git \
    libopenjp2-7 \
    libavcodec-dev \
    libavformat-dev \
    libswscale-dev \
    libv4l-dev \
    libgtk-3-0 \
    fswebcam \
    i2c-tools \
    python3-smbus

# Enable I2C and Camera interfaces
echo "Configuring hardware interfaces..."
if ! grep -q "^dtparam=i2c_arm=on" /boot/config.txt; then
    sudo sh -c 'echo "dtparam=i2c_arm=on" >> /boot/config.txt'
fi

if ! grep -q "^start_x=1" /boot/config.txt; then
    sudo sh -c 'echo "start_x=1" >> /boot/config.txt'
    sudo sh -c 'echo "gpu_mem=128" >> /boot/config.txt'
fi

# Add required modules
if ! grep -q "i2c-dev" /etc/modules; then
    sudo sh -c 'echo "i2c-dev" >> /etc/modules'
fi

# Setup user permissions
sudo usermod -a -G gpio,i2c,video "$USER"

# Create Python virtual environment
if [ ! -d "venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment and install requirements
echo "Installing Python dependencies..."
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

echo "Base setup complete!"
echo "Next steps:"
echo "1. Run hardware tests: python3 tests/test_hardware.py"
echo "2. Choose your cloud platform and run its specific setup script:"
echo "   - AWS:   ./scripts/setup_aws.sh"
echo "   - Azure: ./scripts/setup_azure.sh"
echo "   - Viam:  ./scripts/setup_viam.sh"
echo ""
echo "Note: A system reboot may be needed for hardware changes to take effect."