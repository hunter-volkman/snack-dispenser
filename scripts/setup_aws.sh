#!/bin/bash
set -e

# ====================================================================
# setup_aws.sh
#
# This script sets up the AWS configuration and local environment for
# the Edge Snack Dispenser on a Raspberry Pi.
#
# It has two main responsibilities:
#
# 1. AWS IoT Configuration:
#    - Creates the IoT Thing and Thing Group.
#    - Creates an IAM role and attaches the necessary policies.
#    - Generates device certificates and attaches them to the Thing.
#    - Moves the certificates into the Greengrass device_credentials directory.
#
# 2. Local Environment Setup for AWS Greengrass:
#    - Updates the system and installs required packages.
#    - Installs Greengrass and ensures the CLI is available.
#    - Sets up a Python virtual environment and installs dependencies.
#
# Usage:
#   ./setup_aws.sh [--configure-aws] [--setup-local]
#
# If no arguments are provided, both sections run.
#
# ====================================================================

export AWS_PAGER=""

# Default: run both parts
RUN_CONFIGURE_AWS=true
RUN_SETUP_LOCAL=true

# Process command-line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
      --configure-aws)
      RUN_SETUP_LOCAL=false
      shift
      ;;
      --setup-local)
      RUN_CONFIGURE_AWS=false
      shift
      ;;
      *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# -------------------------------
# Part 1: AWS IoT Configuration
# -------------------------------
if [ "$RUN_CONFIGURE_AWS" = true ]; then
  echo "------------------------------------------"
  echo "Configuring AWS IoT for Edge Snack Dispenser"
  echo "------------------------------------------"

  THING_NAME="EdgeSnackDispenserCoreThing"
  THING_GROUP="EdgeSnackDispenserCoreThingGroup"
  REGION="us-east-1"

  echo "Getting AWS account ID..."
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

  echo "Creating IAM role for TokenExchangeService..."
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

  echo "Attaching policy to IAM role..."
  cat > role-policy.json << EOF
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

  aws iam put-role-policy --role-name GreengrassV2TokenExchangeRole --policy-name GreengrassV2TokenExchangeRoleAccess --policy-document file://role-policy.json

  echo "Creating IoT Thing and Thing Group..."
  aws iot create-thing --thing-name "$THING_NAME"
  aws iot create-thing-group --thing-group-name "$THING_GROUP"

  echo "Creating device certificates..."
  CERT_ARN=$(aws iot create-keys-and-certificate --set-as-active --certificate-pem-outfile "device.pem.crt" --private-key-outfile "private.pem.key" --public-key-outfile "public.pem.key" --query 'certificateArn' --output text)

  echo "Downloading root CA..."
  curl -o root.ca.pem https://www.amazontrust.com/repository/AmazonRootCA1.pem

  echo "Creating and attaching IoT policy..."
  cat > iot-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["iot:Connect", "iot:Publish", "iot:Subscribe", "iot:Receive", "greengrass:*"],
    "Resource": "*"
  }]
}
EOF

  aws iot create-policy --policy-name GreengrassV2IoTThingPolicy --policy-document file://iot-policy.json
  aws iot attach-policy --policy-name GreengrassV2IoTThingPolicy --target "$CERT_ARN"
  aws iot attach-thing-principal --thing-name "$THING_NAME" --principal "$CERT_ARN"

  echo "AWS IoT configuration completed successfully!"
fi

# -------------------------------
# Part 2: Local Environment Setup
# -------------------------------
if [ "$RUN_SETUP_LOCAL" = true ]; then
  echo "------------------------------------------"
  echo "Setting up local environment for AWS Greengrass"
  echo "------------------------------------------"

  echo "Updating system and installing required packages..."
  sudo apt update && sudo apt upgrade -y
  sudo apt install -y python3-pip python3-venv awscli libopenjp2-7 libavcodec-dev libavformat-dev libswscale-dev libv4l-dev libgtk-3-0 git cmake build-essential default-jdk

  echo "Installing AWS IoT Greengrass V2..."
  GREEGRASS_DIR="/greengrass/v2"
  INSTALLER_DIR="GreengrassInstaller"
  INSTALLER_ZIP="greengrass-nucleus-latest.zip"
  INSTALLER_URL="https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip"

  sudo mkdir -p "$GREEGRASS_DIR"
  sudo chmod 755 "$GREEGRASS_DIR"

  curl -s "$INSTALLER_URL" -o "$INSTALLER_ZIP"
  unzip -q "$INSTALLER_ZIP" -d "$INSTALLER_DIR"
  rm "$INSTALLER_ZIP"

  echo "Running Greengrass installer..."
  sudo -E java -Droot="$GREEGRASS_DIR" -Dlog.store=FILE -jar ./"$INSTALLER_DIR"/lib/Greengrass.jar \
    --aws-region "$REGION" --thing-name "$THING_NAME" \
    --thing-group-name "$THING_GROUP" --component-default-user pi:pi \
    --provision true --setup-system-service true --deploy-dev-tools true

  rm -rf "$INSTALLER_DIR"

  echo "Deploying AWS Greengrass Development Tools..."
  sudo /greengrass/v2/bin/greengrass-cli deployment create \
      --recipe-dir /greengrass/v2/recipes \
      --artifact-dir /greengrass/v2/artifacts \
      --merge \
      --components aws.greengrass.Cli=latest

  sleep 10

  if [ -f "$GREEGRASS_DIR/bin/greengrass-cli" ]; then
      echo "✅ AWS Greengrass CLI installed successfully."
  else
      echo "❌ AWS Greengrass CLI installation failed! Check logs."
      sudo tail -n 20 /greengrass/v2/logs/greengrass.log
      exit 1
  fi

  echo "Setting permissions for Greengrass CLI..."
  sudo chmod +x /greengrass/v2/bin/greengrass-cli
  sudo chown -R pi:pi /greengrass

  echo "Restarting Greengrass service..."
  sudo systemctl restart greengrass.service
  sleep 5

  if systemctl is-active greengrass.service >/dev/null 2>&1; then
      echo "✅ Greengrass service is running."
  else
      echo "❌ Greengrass service is not running. Check logs."
      sudo journalctl -u greengrass -n 20
      exit 1
  fi

  echo "Installing Python dependencies..."
  python3 -m venv venv
  source venv/bin/activate
  pip install --upgrade pip
  pip install -r requirements.txt

  echo "Local environment setup completed successfully!"
fi

echo "------------------------------------------"
echo "AWS IoT Greengrass setup completed."
echo "To check Greengrass status: sudo systemctl status greengrass.service"
echo "To view logs: sudo tail -f /greengrass/v2/logs/greengrass.log"
