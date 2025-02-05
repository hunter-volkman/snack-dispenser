#!/bin/bash
set -e
set -o pipefail

# ====================================================================
# setup_aws.sh - AWS IoT & Greengrass Setup Script
#
# This script sets up the AWS IoT Thing, IAM roles, and Greengrass V2
# on a Raspberry Pi for the Edge Snack Dispenser project.
#
# Usage:
#   ./setup_aws.sh
# ====================================================================

export AWS_PAGER=""
REGION="us-east-1"
THING_NAME="EdgeSnackDispenserCoreThing"
THING_GROUP="EdgeSnackDispenserCoreThingGroup"
GREENGRASS_DIR="/greengrass/v2"
S3_BUCKET="edge-snack-dispenser-demo-artifacts"
IAM_ROLE="GreengrassV2TokenExchangeRole"

# -------------------------------
# AWS IoT Configuration
# -------------------------------
echo "🚀 Configuring AWS IoT..."

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $AWS_ACCOUNT_ID"

aws iot create-thing --thing-name "$THING_NAME" || echo "Thing already exists."
aws iot create-thing-group --thing-group-name "$THING_GROUP" || echo "Thing Group already exists."

echo "🔑 Setting up IAM Role for Greengrass..."
aws iam create-role --role-name "$IAM_ROLE" --assume-role-policy-document file://<(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "credentials.iot.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF
) || echo "Role already exists."

echo "🔗 Attaching IAM policies..."
aws iam put-role-policy --role-name "$IAM_ROLE" --policy-name "GreengrassPermissions" --policy-document file://<(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["iot:*", "s3:GetObject", "greengrass:*"],
    "Resource": "*"
  }]
}
EOF
)

aws greengrassv2 associate-service-role-to-account --role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/$IAM_ROLE || echo "Role already associated."

# -------------------------------
# S3 Access Policy
# -------------------------------
echo "🛠 Granting S3 permissions..."
aws iam put-role-policy --role-name "$IAM_ROLE" --policy-name "GreengrassS3Access" --policy-document file://<(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": ["arn:aws:s3:::$S3_BUCKET", "arn:aws:s3:::$S3_BUCKET/*"]
  }]
}
EOF
)

# -------------------------------
# IoT Certificates & Policies
# -------------------------------
echo "🔑 Generating IoT Certificates..."
CERT_ARN=$(aws iot create-keys-and-certificate --set-as-active \
    --certificate-pem-outfile "device.pem.crt" \
    --private-key-outfile "private.pem.key" \
    --public-key-outfile "public.pem.key" \
    --query 'certificateArn' --output text)

curl -o root.ca.pem https://www.amazontrust.com/repository/AmazonRootCA1.pem

echo "📜 Creating & Attaching IoT Policy..."
aws iot create-policy --policy-name "GreengrassV2IoTThingPolicy" --policy-document file://<(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["iot:Connect", "iot:Publish", "iot:Subscribe", "iot:Receive", "greengrass:*"],
    "Resource": "*"
  }]
}
EOF
) || echo "Policy already exists."

aws iot attach-policy --policy-name "GreengrassV2IoTThingPolicy" --target "$CERT_ARN"
aws iot attach-thing-principal --thing-name "$THING_NAME" --principal "$CERT_ARN"

echo "✅ AWS IoT Configuration Completed!"

# -------------------------------
# Local Environment Setup
# -------------------------------
echo "🔧 Installing required packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3-pip python3-venv awscli libopenjp2-7 libavcodec-dev libavformat-dev libswscale-dev libv4l-dev libgtk-3-0 git cmake build-essential default-jdk unzip

echo "👤 Ensuring ggc_user and ggc_group exist..."
sudo id -u ggc_user &>/dev/null || sudo useradd --system ggc_user
sudo getent group ggc_group &>/dev/null || sudo groupadd --system ggc_group
sudo usermod -aG ggc_group ggc_user

echo "📦 Installing AWS IoT Greengrass V2..."
sudo rm -rf "$GREENGRASS_DIR"
curl -s "https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip" -o "greengrass-nucleus.zip"
unzip -o -q "greengrass-nucleus.zip" -d "GreengrassInstaller"
rm "greengrass-nucleus.zip"

echo "🚀 Running Greengrass Installer..."
sudo -E java -Droot="$GREENGRASS_DIR" -Dlog.store=FILE -jar ./GreengrassInstaller/lib/Greengrass.jar \
    --aws-region "$REGION" --thing-name "$THING_NAME" \
    --thing-group-name "$THING_GROUP" --component-default-user "ggc_user:ggc_group" \
    --provision true --setup-system-service true --deploy-dev-tools true

rm -rf "GreengrassInstaller"

echo "🔒 Setting permissions for Greengrass..."
sudo chown -R ggc_user:ggc_group /greengrass/v2/
sudo chmod -R 755 /greengrass/v2/

echo "🔎 Verifying Greengrass CLI installation..."
if [ -f "$GREENGRASS_DIR/bin/greengrass-cli" ]; then
    echo "✅ AWS Greengrass CLI installed successfully."
else
    echo "❌ AWS Greengrass CLI installation failed!"
    sudo tail -n 50 "$GREENGRASS_DIR/logs/greengrass.log"
    exit 1
fi

echo "🔄 Restarting Greengrass service..."
sudo systemctl restart greengrass.service
sleep 10

if systemctl is-active greengrass.service >/dev/null 2>&1; then
    echo "✅ Greengrass service is running."
else
    echo "❌ Greengrass service failed to start. Check logs:"
    sudo journalctl -u greengrass -n 50
    exit 1
fi

echo "🐍 Installing Python dependencies..."
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

echo "🎉 AWS IoT Greengrass setup completed!"
echo "To check Greengrass status: sudo systemctl status greengrass.service"
echo "To view logs: sudo tail -f $GREENGRASS_DIR/logs/greengrass.log"
