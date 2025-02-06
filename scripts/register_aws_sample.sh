#!/bin/bash
# register_core_aws_sample.sh
# Sets up AWS IoT Thing and installs Greengrass core software

set -e
set -o pipefail

# Configuration
THING_NAME="HelloWorldCore"
THING_GROUP="HelloWorldGroup"
REGION="us-east-1"
IOT_POLICY_NAME="HelloWorldPolicy"

echo "🚀 Setting up AWS IoT Thing and Greengrass core..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo -E ./scripts/register_core_aws_sample.sh)"
    exit 1
fi

# Get the actual user (non-root) home directory
SUDO_USER_HOME=$(getent passwd ${SUDO_USER} | cut -d: -f6)

# Use the actual user's AWS credentials
export AWS_SHARED_CREDENTIALS_FILE="${SUDO_USER_HOME}/.aws/credentials"
export AWS_CONFIG_FILE="${SUDO_USER_HOME}/.aws/config"

# Verify AWS credentials work
if ! aws sts get-caller-identity &>/dev/null; then
    echo "❌ AWS CLI not configured correctly. Please run 'aws configure' as your normal user first."
    exit 1
fi

echo "AWS credentials verified. Proceeding with setup..."

# Set up IAM role for Greengrass Token Exchange
echo "🔑 Setting up Token Exchange Role..."
ROLE_NAME="GreengrassV2TokenExchangeRole"
ROLE_ALIAS_NAME="GreengrassV2TokenExchangeRoleAlias"

# Create IAM role
aws iam create-role \
    --role-name $ROLE_NAME \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {
                "Service": "credentials.iot.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }]
    }' || echo "Role already exists"

# Attach required policy
aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn "arn:aws:iam::aws:policy/service-role/GreengrassV2TokenExchangeRoleAccess" || echo "Policy already attached"

# Create role alias
aws iot create-role-alias \
    --role-alias $ROLE_ALIAS_NAME \
    --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}" \
    --credential-duration-seconds 3600 || echo "Role alias already exists"

# Add permissions to IoT policy for role alias
aws iot create-policy --policy-name "GreengrassV2IoTThingPolicy" --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": [
            "iot:DescribeCertificate",
            "iot:Connect",
            "iot:Publish",
            "iot:Subscribe",
            "iot:Receive",
            "greengrass:*"
        ],
        "Resource": "*"
    }, {
        "Effect": "Allow",
        "Action": "iot:AssumeRoleWithCertificate",
        "Resource": "arn:aws:iot:'"${REGION}"':'"${AWS_ACCOUNT_ID}"':rolealias/'"${ROLE_ALIAS_NAME}"'"
    }]
}' || echo "IoT policy already exists"

# Create IoT Thing
echo "🔧 Creating AWS IoT Thing..."
aws iot create-thing --thing-name "$THING_NAME" || echo "Thing already exists"

# Create Thing Group
aws iot create-thing-group --thing-group-name "$THING_GROUP" || echo "Thing Group already exists"

# Create and attach IoT policy
echo "📜 Creating IoT Policy..."
aws iot create-policy --policy-name "$IOT_POLICY_NAME" --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": ["iot:*", "greengrass:*"],
        "Resource": "*"
    }]
}' || echo "Policy already exists"

# Generate certificates
echo "🔑 Generating certificates..."
CERT_ARN=$(aws iot create-keys-and-certificate --set-as-active \
    --certificate-pem-outfile "device.pem.crt" \
    --private-key-outfile "private.pem.key" \
    --public-key-outfile "public.pem.key" \
    --query 'certificateArn' --output text)

# Attach policy to certificate
aws iot attach-policy --policy-name "$IOT_POLICY_NAME" --target "$CERT_ARN"

# Attach certificate to thing
aws iot attach-thing-principal --thing-name "$THING_NAME" --principal "$CERT_ARN"

# Install required packages
echo "📦 Installing required packages..."
apt-get update
JAVA_PACKAGE="openjdk-17-jre-headless"
if ! apt-get install -y $JAVA_PACKAGE; then
    echo "❌ Failed to install Java. Trying to find available versions..."
    apt-cache search openjdk | grep "headless"
    exit 1
fi

# Create Greengrass user and group
echo "👤 Creating Greengrass user and group..."
groupadd --system ggc_group || true
useradd --system --no-create-home --shell /bin/false ggc_user -G ggc_group || true

# Set up Greengrass directories
echo "📁 Setting up Greengrass directories..."
mkdir -p /greengrass/v2
mkdir -p /greengrass/v2/device_credentials

# Install certificates
echo "🔐 Installing device certificates..."
cp device.pem.crt /greengrass/v2/device_credentials/
cp private.pem.key /greengrass/v2/device_credentials/
curl -s https://www.amazontrust.com/repository/AmazonRootCA1.pem -o /greengrass/v2/device_credentials/root.ca.pem

# Set permissions
chown -R ggc_user:ggc_group /greengrass
chmod 740 /greengrass/v2/device_credentials/*

# Download and install Greengrass
echo "📥 Downloading Greengrass installer..."
curl -s https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip -o greengrass-nucleus.zip
unzip -q -o greengrass-nucleus.zip -d GreengrassInstaller

# Install Greengrass
echo "⚙️ Installing Greengrass..."
java -Droot="/greengrass/v2" -Dlog.store=FILE \
    -jar ./GreengrassInstaller/lib/Greengrass.jar \
    --aws-region "$REGION" \
    --thing-name "$THING_NAME" \
    --thing-group-name "$THING_GROUP" \
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

# Fix ownership of generated files
chown ${SUDO_USER}:${SUDO_USER} device.pem.crt private.pem.key public.pem.key || true

echo "✅ Greengrass core device registration complete!"
echo ""
echo "Next steps:"
echo "1. Verify Greengrass is running:      sudo systemctl status greengrass"
echo "2. Check the logs:                    sudo tail -f /greengrass/v2/logs/greengrass.log"
echo "3. Deploy components using:           ./deploy_hello_aws_sample.sh"
echo ""
echo "To start over, run:                   sudo ./cleanup_aws_sample.sh"