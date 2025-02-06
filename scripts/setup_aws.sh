#!/bin/bash
# setup_aws.sh - Sets up AWS IoT and Greengrass for Edge Snack Dispenser

set -e
set -o pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
INFO="${GREEN}[INFO]${NC}"
WARN="${YELLOW}[WARN]${NC}"
ERROR="${RED}[ERROR]${NC}"

# Configuration
THING_NAME="EdgeSnackDispenserCore"
THING_GROUP="EdgeSnackDispenserGroup"
REGION="us-east-1"
S3_BUCKET="edge-snack-dispenser-artifacts"
ROLE_NAME="EdgeSnackDispenserRole"
COMPONENT_NAME="com.edgesnackdispenser.core"
IOT_POLICY_NAME="${THING_NAME}Policy"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${ERROR} Please run as root (sudo ./setup_aws.sh)"
    exit 1
fi

# Verify AWS CLI is configured
if ! aws sts get-caller-identity &>/dev/null; then
    echo -e "${ERROR} AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo -e "${INFO} Setting up Edge Snack Dispenser AWS resources..."

# Create IoT Thing and Thing Group
echo -e "${INFO} Creating IoT Thing and Thing Group..."
aws iot create-thing --thing-name "$THING_NAME" || echo -e "${WARN} Thing already exists"
aws iot create-thing-group --thing-group-name "$THING_GROUP" || echo -e "${WARN} Thing Group already exists"

# Create and configure IAM role
echo -e "${INFO} Setting up IAM role..."
aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {
                "Service": "credentials.iot.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }]
    }' || echo -e "${WARN} Role already exists"

# Attach required policies
echo -e "${INFO} Attaching policies..."

# Create and attach custom policy for Greengrass token exchange
echo -e "${INFO} Creating token exchange policy..."
aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "GreengrassV2TokenExchangeAccess" \
    --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "iot:DescribeCertificate",
                    "iot:GetCredentials",
                    "iot:AssumeRoleWithCertificate",
                    "iot:Connect",
                    "iot:Publish",
                    "iot:Subscribe",
                    "iot:Receive"
                ],
                "Resource": "*"
            }
        ]
    }'

# Attach Greengrass access policy
echo -e "${INFO} Attaching Greengrass access policy..."
aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AWSGreengrassResourceAccessRolePolicy" || \
    echo -e "${WARN} Failed to attach AWSGreengrassResourceAccessRolePolicy, continuing with custom policy"

# Attach custom inline policy for component access
echo -e "${INFO} Attaching custom inline policies..."
aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "GreengrassAccess" \
    --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "iot:*",
                    "greengrass:*"
                ],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "s3:GetObject",
                    "s3:ListBucket"
                ],
                "Resource": [
                    "arn:aws:s3:::'$S3_BUCKET'",
                    "arn:aws:s3:::'$S3_BUCKET'/*"
                ]
            }
        ]
    }'

# Create token exchange role alias
echo -e "${INFO} Creating token exchange role alias..."
aws iot create-role-alias \
    --role-alias "GreengrassV2TokenExchangeRoleAlias" \
    --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}" \
    --credential-duration-seconds 3600 || echo -e "${WARN} Role alias already exists"

# Create certificates
echo -e "${INFO} Creating certificates..."
CERT_ARN=$(aws iot create-keys-and-certificate --set-as-active \
    --certificate-pem-outfile "device.pem.crt" \
    --private-key-outfile "private.pem.key" \
    --public-key-outfile "public.pem.key" \
    --query 'certificateArn' --output text)

# Download root CA
curl -s https://www.amazontrust.com/repository/AmazonRootCA1.pem -o root.ca.pem

# Create IoT policy
echo -e "${INFO} Creating IoT policy..."
aws iot create-policy --policy-name "$IOT_POLICY_NAME" --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iot:Connect",
                "iot:Publish",
                "iot:Subscribe",
                "iot:Receive",
                "iot:DescribeCertificate",
                "greengrass:*"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": "iot:AssumeRoleWithCertificate",
            "Resource": "arn:aws:iot:'$REGION':'$AWS_ACCOUNT_ID':rolealias/GreengrassV2TokenExchangeRoleAlias"
        }
    ]
}' || echo -e "${WARN} Policy already exists"

# Attach policy to certificate
aws iot attach-policy --policy-name "$IOT_POLICY_NAME" --target "$CERT_ARN"
aws iot attach-thing-principal --thing-name "$THING_NAME" --principal "$CERT_ARN"

# Install system dependencies
echo -e "${INFO} Installing system dependencies..."
apt-get update
apt-get install -y python3-pip openjdk-17-jre-headless

# Create Greengrass user
echo -e "${INFO} Setting up Greengrass user..."
groupadd --system ggc_group || true
useradd --system --no-create-home --shell /bin/false ggc_user -G ggc_group || true

# Set up Greengrass directories
echo -e "${INFO} Setting up Greengrass directories..."
mkdir -p /greengrass/v2
mkdir -p /greengrass/v2/device_credentials

# Install certificates
cp device.pem.crt /greengrass/v2/device_credentials/
cp private.pem.key /greengrass/v2/device_credentials/
cp root.ca.pem /greengrass/v2/device_credentials/

# Set permissions
chown -R ggc_user:ggc_group /greengrass
chmod 740 /greengrass/v2/device_credentials/*

# Install Greengrass
echo -e "${INFO} Installing Greengrass..."
curl -s https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip -o greengrass-nucleus.zip
unzip -q greengrass-nucleus.zip -d GreengrassInstaller

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
rm -rf GreengrassInstaller greengrass-nucleus.zip

# Start Greengrass service
echo -e "${INFO} Starting Greengrass service..."
systemctl enable greengrass
systemctl start greengrass

# Wait for service to start
echo -e "${INFO} Waiting for Greengrass service to initialize..."
sleep 10

# Deploy Greengrass dev tools
echo -e "${INFO} Deploying Greengrass dev tools..."
aws greengrassv2 create-deployment \
    --target-arn "arn:aws:iot:${REGION}:${AWS_ACCOUNT_ID}:thing/${THING_NAME}" \
    --deployment-name "DevTools" \
    --components '{
        "aws.greengrass.Cli": {
            "componentVersion": "2.13.0"
        }
    }' || echo -e "${WARN} Dev tools deployment already exists"

# Verify Greengrass is running
if systemctl is-active --quiet greengrass; then
    echo -e "${INFO} Greengrass service is running"
else
    echo -e "${ERROR} Greengrass service failed to start. Check logs for details."
    echo "Logs: sudo tail -f /greengrass/v2/logs/greengrass.log"
    exit 1
fi

echo -e "\n${GREEN}✅ Setup complete!${NC}"
echo -e "${INFO} Next steps:"
echo "1. Deploy the component:    sudo ./deploy_aws.sh"
echo "2. Monitor deployment:      sudo tail -f /greengrass/v2/logs/greengrass.log"