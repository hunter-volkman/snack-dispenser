#!/bin/bash
set -e

# ====================================================================
# setup_aws_combined.sh
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
#    - Sets up a Python virtual environment and installs Python dependencies.
#
# Usage:
#   ./setup_aws.sh [--configure-aws] [--setup-local]
#
# If no arguments are provided, both sections run.
#
# ====================================================================

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

  echo "Setting up Greengrass directories..."
  sudo mkdir -p /greengrass/v2/device_credentials
  sudo chmod 755 /greengrass
  sudo chmod 755 /greengrass/v2
  sudo chmod 700 /greengrass/v2/device_credentials

  echo "Moving certificates to /greengrass/v2/device_credentials/ ..."
  sudo mv {device.pem.crt,private.pem.key,public.pem.key,root.ca.pem} /greengrass/v2/device_credentials/
  sudo chmod 644 /greengrass/v2/device_credentials/device.pem.crt
  sudo chmod 644 /greengrass/v2/device_credentials/public.pem.key
  sudo chmod 644 /greengrass/v2/device_credentials/root.ca.pem
  sudo chmod 600 /greengrass/v2/device_credentials/private.pem.key

  rm -f trust-policy.json role-policy.json iot-policy.json

  echo "AWS IoT configuration completed successfully!"
  echo "Next, proceed with local environment setup."
fi

# -------------------------------
# Part 2: Local Environment Setup for Greengrass
# -------------------------------
if [ "$RUN_SETUP_LOCAL" = true ]; then
  echo "------------------------------------------"
  echo "Setting up local environment for Edge Snack Dispenser"
  echo "------------------------------------------"

  if ! grep -q "Raspberry Pi" /proc/cpuinfo; then
      echo "❌ This script must be run on a Raspberry Pi"
      exit 1
  fi

  echo "Updating system and installing required packages..."
  sudo apt update && sudo apt upgrade -y
  sudo apt install -y python3-pip python3-venv awscli libopenjp2-7 libilmbase23 \
      libopenexr-dev libavcodec-dev libavformat-dev libswscale-dev libv4l-dev libgtk-3-0 \
      libwebp-dev fswebcam

  if [ ! -d "venv" ]; then
      echo "Creating Python virtual environment..."
      python3 -m venv venv
  fi
  source venv/bin/activate

  echo "Installing Python dependencies..."
  pip install --upgrade pip
  pip install -r requirements.txt

  echo "Local environment setup completed successfully!"
fi

echo "------------------------------------------"
echo "Combined AWS setup completed."
echo "You can now run further deployment steps (e.g., deploy_component_aws.sh) as needed."
