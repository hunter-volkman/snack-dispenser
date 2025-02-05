#!/bin/bash
set -e
set -o pipefail

# ====================================================================
# setup_aws.sh
#
# This script sets up the AWS configuration and local environment for
# the Edge Snack Dispenser on a Raspberry Pi.
#
# It performs:
# 1. AWS IoT Configuration (IoT Thing, IAM roles, certificates)
# 2. AWS IAM Role Setup (S3 Permissions for Greengrass)
# 3. Local environment setup (Greengrass installation, dependencies)
#
# Usage:
#   ./setup_aws.sh
#
# ====================================================================

export AWS_PAGER=""
REGION="us-east-1"
THING_NAME="EdgeSnackDispenserCoreThing"
THING_GROUP="EdgeSnackDispenserCoreThingGroup"
GREENGRASS_DIR="/greengrass/v2"
S3_BUCKET="edge-snack-dispenser-demo-artifacts"

# -------------------------------
# Part 1: AWS IoT Configuration
# -------------------------------
echo "------------------------------------------"
echo "Configuring AWS IoT for Edge Snack Dispenser"
echo "------------------------------------------"

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $AWS_ACCOUNT_ID"

echo "Creating IoT Thing and Thing Group..."
aws iot create-thing --thing-name "$THING_NAME"
aws iot create-thing-group --thing-group-name "$THING_GROUP"

echo "Creating IAM role for Greengrass..."
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "credentials.iot.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role --role-name GreengrassV2TokenExchangeRole --assume-role-policy-document file://trust-policy.json

echo "Attaching AWS IoT and Greengrass permissions..."
aws iam put-role-policy --role-name GreengrassV2TokenExchangeRole --policy-name GreengrassV2TokenExchangeRoleAccess --policy-document file://<(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "iot:DescribeCertificate", "iot:Connect", "iot:Publish", "iot:Subscribe",
      "iot:Receive", "s3:GetObject", "greengrass:*"
    ],
    "Resource": "*"
  }]
}
EOF
)

# -------------------------------
# Part 2: Attach S3 Access Policy to IAM Role
# -------------------------------
echo "------------------------------------------"
echo "Granting S3 permissions to Greengrass..."
echo "------------------------------------------"

cat > s3-access-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET}",
        "arn:aws:s3:::${S3_BUCKET}/*"
      ]
    }
  ]
}
EOF

aws iam put-role-policy --role-name GreengrassV2TokenExchangeRole --policy-name GreengrassS3Access --policy-document file://s3-access-policy.json

echo "✅ S3 access policy applied successfully!"

echo "Generating device certificates..."
CERT_ARN=$(aws iot create-keys-and-certificate --set-as-active \
    --certificate-pem-outfile "device.pem.crt" \
    --private-key-outfile "private.pem.key" \
    --public-key-outfile "public.pem.key" \
    --query 'certificateArn' --output text)

echo "Downloading root CA..."
curl -o root.ca.pem https://www.amazontrust.com/repository/AmazonRootCA1.pem

echo "Creating and attaching IoT policy..."
aws iot create-policy --policy-name GreengrassV2IoTThingPolicy --policy-document file://<(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["iot:Connect", "iot:Publish", "iot:Subscribe", "iot:Receive", "greengrass:*"],
    "Resource": "*"
  }]
}
EOF
)

aws iot attach-policy --policy-name GreengrassV2IoTThingPolicy --target "$CERT_ARN"
aws iot attach-thing-principal --thing-name "$THING_NAME" --principal "$CERT_ARN"

echo "AWS IoT configuration completed successfully!"

# -------------------------------
# Part 3: Local Environment Setup
# -------------------------------
echo "------------------------------------------"
echo "Setting up local environment for AWS Greengrass"
echo "------------------------------------------"

echo "Updating system and installing required packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3-pip python3-venv awscli libopenjp2-7 libavcodec-dev libavformat-dev libswscale-dev libv4l-dev libgtk-3-0 git cmake build-essential default-jdk unzip

# Force a clean installation of Greengrass
if [ -d "$GREENGRASS_DIR" ]; then
    echo "Removing existing Greengrass installation..."
    sudo rm -rf "$GREENGRASS_DIR"
fi

echo "Installing AWS IoT Greengrass V2..."
INSTALLER_ZIP="greengrass-nucleus-latest.zip"
INSTALLER_URL="https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip"

curl -s "$INSTALLER_URL" -o "$INSTALLER_ZIP"
unzip -q "$INSTALLER_ZIP" -d "GreengrassInstaller"
rm "$INSTALLER_ZIP"

echo "Running Greengrass installer..."
COMPONENT_DEFAULT_USER="$(whoami):$(id -gn)"
sudo -E java -Droot="$GREENGRASS_DIR" -Dlog.store=FILE -jar ./GreengrassInstaller/lib/Greengrass.jar \
    --aws-region "$REGION" --thing-name "$THING_NAME" \
    --thing-group-name "$THING_GROUP" --component-default-user "${COMPONENT_DEFAULT_USER}" \
    --provision true --setup-system-service true --deploy-dev-tools true

rm -rf "GreengrassInstaller"

echo "Setting correct permissions for Greengrass directory..."
sudo chmod -R 755 /greengrass/v2/
sudo chown -R $(whoami):$(id -gn) /greengrass/v2/

echo "Verifying Greengrass CLI installation..."
if [ -f "$GREENGRASS_DIR/bin/greengrass-cli" ]; then
    echo "✅ AWS Greengrass CLI installed successfully."
else
    echo "❌ AWS Greengrass CLI installation failed! Check logs:"
    sudo tail -n 50 "$GREENGRASS_DIR/logs/greengrass.log"
    exit 1
fi

echo "Restarting Greengrass service..."
sudo systemctl restart greengrass.service
sleep 10

if systemctl is-active greengrass.service >/dev/null 2>&1; then
    echo "✅ Greengrass service is running."
else
    echo "❌ Greengrass service failed to start. Check logs:"
    sudo journalctl -u greengrass -n 50
    exit 1
fi

echo "Installing Python dependencies..."
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

echo "------------------------------------------"
echo "AWS IoT Greengrass setup completed."
echo "To check Greengrass status: sudo systemctl status greengrass.service"
echo "To view logs: sudo tail -f $GREENGRASS_DIR/logs/greengrass.log"
