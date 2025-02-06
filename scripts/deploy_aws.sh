#!/bin/bash
# deploy_aws.sh - Deploys Edge Snack Dispenser component to AWS Greengrass

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
REGION="us-east-1"
S3_BUCKET="edge-snack-dispenser-artifacts"
COMPONENT_NAME="com.edgesnackdispenser.core"
COMPONENT_VERSION="1.0.0"

# Create the recipe file
create_recipe() {
    cat > recipe.yaml << EOF
---
RecipeFormatVersion: 2020-01-25
ComponentName: ${COMPONENT_NAME}
ComponentVersion: ${COMPONENT_VERSION}
ComponentDescription: "Edge Snack Dispenser with computer vision-based snack level detection"
ComponentPublisher: EdgeSnackDispenser

ComponentConfiguration:
  DefaultConfiguration:
    checkInterval: 5
    confidenceThreshold: 0.7
    accessControl:
      aws.greengrass.ipc.mqttproxy:
        policies:
          - policyDescription: "Allows MQTT communication"
            operations:
              - aws.greengrass#PublishToIoTCore
              - aws.greengrass#SubscribeToIoTCore
            resources:
              - "edgesnackdispenser/+/status"
              - "edgesnackdispenser/+/control"

Manifests:
  - Platform:
      os: linux
    Artifacts:
      - URI: s3://${S3_BUCKET}/edge-snack-dispenser.zip
        Unarchive: ZIP
    Lifecycle:
      Install:
        RequiresPrivilege: true
        Script: |
          pip3 install --user -r {artifacts:decompressedPath}/requirements.txt
          pip3 install --user opencv-python-headless numpy pyyaml scikit-learn RPi.GPIO
      Run:
        RequiresPrivilege: true
        Script: |
          export PYTHONPATH={artifacts:decompressedPath}
          python3 -u aws/main.py
EOF
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${ERROR} Please run as root (sudo ./deploy_aws.sh)"
    exit 1
fi

# Verify AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
    echo -e "${ERROR} AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo -e "${INFO} Deploying Edge Snack Dispenser component..."

# Create S3 bucket if it doesn't exist
if ! aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
    echo -e "${INFO} Creating S3 bucket..."
    aws s3api create-bucket --bucket "$S3_BUCKET" --region "$REGION"
fi

# Package component
echo -e "${INFO} Packaging component..."
zip -r edge-snack-dispenser.zip aws/ common/ requirements.txt

# Upload to S3
echo -e "${INFO} Uploading to S3..."
aws s3 cp edge-snack-dispenser.zip "s3://${S3_BUCKET}/"

# Create recipe and component
echo -e "${INFO} Creating component..."
create_recipe
aws greengrassv2 create-component-version --inline-recipe fileb://recipe.yaml

# Deploy component
echo -e "${INFO} Deploying component..."
TARGET_ARN="arn:aws:iot:${REGION}:${AWS_ACCOUNT_ID}:thing/${THING_NAME}"

aws greengrassv2 create-deployment \
    --target-arn "$TARGET_ARN" \
    --deployment-name "${COMPONENT_NAME}-deployment" \
    --components "{\"${COMPONENT_NAME}\": {\"componentVersion\": \"${COMPONENT_VERSION}\"}}"

# Clean up temporary files
rm -f edge-snack-dispenser.zip recipe.yaml

echo -e "\n${GREEN}✅ Deployment initiated!${NC}"
echo -e "${INFO} Monitor the deployment:"
echo "1. View deployment status:  aws greengrassv2 list-deployments"
echo "2. Check component logs:    sudo tail -f /greengrass/v2/logs/${COMPONENT_NAME}.log"
echo "3. View MQTT messages:      aws iot-data get-topic --topic 'edgesnackdispenser/+/status'"