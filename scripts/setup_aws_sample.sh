#!/bin/bash
# setup_aws_sample.sh
# Sets up and installs Greengrass on the device

set -e
set -o pipefail

# Configuration (must match deploy_aws_sample.sh)
THING_NAME="HelloWorldCore"
REGION="us-east-1"

echo "🚀 Setting up Greengrass on device..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

# Check for required files
if [ ! -f "device.pem.crt" ] || [ ! -f "private.pem.key" ]; then
    echo "❌ Certificate files not found! Please run deploy_aws_sample.sh first."
    exit 1
fi

# Install Java (required for Greengrass)
echo "📦 Installing Java..."
apt-get update
apt-get install -y openjdk-11-jre-headless

# Create Greengrass user and group
echo "👤 Creating Greengrass user and group..."
groupadd --system ggc_group || true
useradd --system --no-create-home --shell /bin/false ggc_user -G ggc_group || true

# Set up Greengrass directories
echo "📁 Setting up Greengrass directories..."
mkdir -p /greengrass/v2
mkdir -p /greengrass/v2/device_credentials

# Copy credentials
echo "🔑 Installing device certificates..."
cp device.pem.crt /greengrass/v2/device_credentials/
cp private.pem.key /greengrass/v2/device_credentials/
curl -s https://www.amazontrust.com/repository/AmazonRootCA1.pem -o /greengrass/v2/device_credentials/root.ca.pem

# Set proper permissions
chown -R ggc_user:ggc_group /greengrass
chmod 740 /greengrass/v2/device_credentials/*

# Download and install Greengrass
echo "📥 Downloading Greengrass installer..."
curl -s https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip -o greengrass-nucleus.zip
unzip -q -o greengrass-nucleus.zip -d GreengrassInstaller

echo "⚙️ Installing Greengrass..."
java -Droot="/greengrass/v2" -Dlog.store=FILE \
    -jar ./GreengrassInstaller/lib/Greengrass.jar \
    --aws-region "$REGION" \
    --thing-name "$THING_NAME" \
    --thing-group-name "HelloWorldGroup" \
    --component-default-user "ggc_user:ggc_group" \
    --provision true \
    --setup-system-service true \
    --deploy-dev-tools true

# Clean up installer files
rm -rf GreengrassInstaller
rm -f greengrass-nucleus.zip

# Start Greengrass service
echo "🟢 Starting Greengrass service..."
systemctl enable greengrass
systemctl start greengrass

echo "✅ Greengrass setup complete!"
echo ""
echo "To monitor Greengrass:"
echo "1. Check service status:   sudo systemctl status greengrass"
echo "2. View logs:             sudo tail -f /greengrass/v2/logs/greengrass.log"