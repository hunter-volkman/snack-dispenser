#!/bin/bash
set -e

# Configuration
THING_NAME="SnackBotCore"
THING_GROUP="SnackBotGroup"
REGION="us-east-1"

echo "🚀 Setting up AWS configuration for Snack Bot..."

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create IAM role for TokenExchangeService
echo "Creating IAM role for TokenExchangeService..."
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "credentials.iot.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
    --role-name GreengrassV2TokenExchangeRole \
    --assume-role-policy-document file://trust-policy.json

# Create and attach role policy
cat > role-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iot:DescribeCertificate",
                "iot:Connect",
                "iot:Publish",
                "iot:Subscribe",
                "iot:Receive",
                "s3:GetObject",
                "greengrass:*"
            ],
            "Resource": "*"
        }
    ]
}
EOF

aws iam put-role-policy \
    --role-name GreengrassV2TokenExchangeRole \
    --policy-name GreengrassV2TokenExchangeRoleAccess \
    --policy-document file://role-policy.json

# Create IoT Thing
echo "Creating IoT Thing..."
aws iot create-thing --thing-name "$THING_NAME"
aws iot create-thing-group --thing-group-name "$THING_GROUP"

# Create certificates
echo "Creating certificates..."
CERT_ARN=$(aws iot create-keys-and-certificate \
    --set-as-active \
    --certificate-pem-outfile "device.pem.crt" \
    --private-key-outfile "private.pem.key" \
    --public-key-outfile "public.pem.key" \
    --query 'certificateArn' \
    --output text)

# Download root CA
curl -o root.ca.pem https://www.amazontrust.com/repository/AmazonRootCA1.pem

# Create and attach IoT policy
echo "Creating IoT policy..."
cat > iot-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iot:Connect",
                "iot:Publish",
                "iot:Subscribe",
                "iot:Receive",
                "greengrass:*"
            ],
            "Resource": "*"
        }
    ]
}
EOF

aws iot create-policy \
    --policy-name GreengrassV2IoTThingPolicy \
    --policy-document file://iot-policy.json

aws iot attach-policy \
    --policy-name GreengrassV2IoTThingPolicy \
    --target "$CERT_ARN"

aws iot attach-thing-principal \
    --thing-name "$THING_NAME" \
    --principal "$CERT_ARN"

# Setup Greengrass directories
echo "Setting up Greengrass directories..."
sudo mkdir -p /greengrass/v2
sudo mkdir -p /greengrass/v2/device_credentials
sudo chmod 755 /greengrass
sudo chmod 755 /greengrass/v2
sudo chmod 700 /greengrass/v2/device_credentials

# Move certificates
sudo mv {device.pem.crt,private.pem.key,public.pem.key,root.ca.pem} \
    /greengrass/v2/device_credentials/

sudo chmod 644 /greengrass/v2/device_credentials/device.pem.crt
sudo chmod 644 /greengrass/v2/device_credentials/public.pem.key
sudo chmod 644 /greengrass/v2/device_credentials/root.ca.pem
sudo chmod 600 /greengrass/v2/device_credentials/private.pem.key

# Install Greengrass
echo "Installing Greengrass..."
curl -s https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip \
    -o greengrass-nucleus.zip
unzip greengrass-nucleus.zip -d GreengrassInstaller

sudo -E java -Droot="/greengrass/v2" \
    -Dlog.store=FILE \
    -jar ./GreengrassInstaller/lib/Greengrass.jar \
    --aws-region "$REGION" \
    --thing-name "$THING_NAME" \
    --thing-group-name "$THING_GROUP" \
    --component-default-user pi:pi \
    --provision true \
    --setup-system-service true \
    --deploy-dev-tools true

# Cleanup
rm -rf GreengrassInstaller greengrass-nucleus.zip \
    trust-policy.json role-policy.json iot-policy.json

echo "✅ AWS setup completed successfully!"
echo "📝 Next steps:"
echo "1. Check Greengrass service: sudo systemctl status greengrass"
echo "2. View logs: sudo tail -f /greengrass/v2/logs/greengrass.log"
echo "3. List core devices: aws greengrassv2 list-core-devices"