#!/bin/bash
# component-deploy.sh
# Handles packaging and deployment of Greengrass components

set -e
set -o pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
INFO="${GREEN}[INFO]${NC}"
WARN="${YELLOW}[WARN]${NC}"
ERROR="${RED}[ERROR]${NC}"

# Default configuration
CONFIG_FILE="greengrass-config.json"
S3_BUCKET="edge-snack-dispenser-demo-artifacts"
COMPONENT_NAME="com.snackdispenser.core"
COMPONENT_VERSION="1.0.0"

# Load base configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${ERROR} Configuration file $CONFIG_FILE not found!"
    echo "Please run aws-setup.sh first"
    exit 1
fi

THING_NAME=$(jq -r '.thingName' "$CONFIG_FILE")
REGION=$(jq -r '.region' "$CONFIG_FILE")
AWS_ACCOUNT_ID=$(jq -r '.accountId' "$CONFIG_FILE")

# Verify AWS credentials
check_aws_credentials() {
    echo -e "${INFO} Verifying AWS credentials..."
    if ! aws sts get-caller-identity &>/dev/null; then
        echo -e "${ERROR} AWS credentials not configured!"
        exit 1
    fi
}

# Create component package
create_package() {
    echo -e "${INFO} Creating component package..."
    
    # Create temp directory for packaging
    TEMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TEMP_DIR"' EXIT
    
    # Copy necessary files
    echo -e "${INFO} Copying component files..."
    
    # Copy common directory
    cp -r common "$TEMP_DIR/"
    
    # Copy ML model if it exists
    if [ -d "data/model" ]; then
        cp -r data "$TEMP_DIR/"
    else
        echo -e "${WARN} ML model directory not found at data/model"
        echo -e "${WARN} Make sure to train your model first!"
    fi
    
    # Create requirements.txt
    cat > "$TEMP_DIR/requirements.txt" << 'EOF'
opencv-python-headless
numpy
scikit-learn
RPi.GPIO
pyyaml
awsiotsdk
EOF
    
    # Create the recipe file
    cat > "$TEMP_DIR/recipe.yaml" << EOF
---
RecipeFormatVersion: 2020-01-25
ComponentName: ${COMPONENT_NAME}
ComponentVersion: ${COMPONENT_VERSION}
ComponentDescription: "Smart Snack Dispenser with Computer Vision"
ComponentPublisher: ${AWS_ACCOUNT_ID}
ComponentConfiguration:
  DefaultConfiguration:
    check_interval: "5"
    min_dispense_interval: "30"
    confidence_threshold: "0.7"
    motor:
      step_pin: "16"
      dir_pin: "15"
      en_pin: "18"
    camera:
      device_id: "0"
      width: "640"
      height: "480"
    accessControl:
      aws.greengrass.ipc.mqttproxy:
        ${COMPONENT_NAME}:mqttproxy:1:
          policyDescription: "Allows access to publish and subscribe to IoT Core"
          operations:
            - aws.greengrass#PublishToIoTCore
            - aws.greengrass#SubscribeToIoTCore
          resources:
            - "snackdispenser/+/status"
            - "snackdispenser/+/control"
Manifests:
  - Platform:
      os: linux
    Artifacts:
      - URI: s3://${S3_BUCKET}/components/${COMPONENT_NAME}/${COMPONENT_VERSION}/artifact.zip
        Unarchive: ZIP
    Lifecycle:
      Install:
        RequiresPrivilege: true
        Script: |
          echo "Installing dependencies..."
          python3 -m pip install --user --break-system-packages -r {artifacts:decompressedPath}/requirements.txt
      Run:
        RequiresPrivilege: true
        Script: |
          echo "Starting Edge Snack Dispenser..."
          export PYTHONPATH={artifacts:decompressedPath}
          cd {artifacts:decompressedPath}
          python3 -u common/aws/main.py
EOF

    # Create artifact zip
    echo -e "${INFO} Creating artifact archive..."
    (cd "$TEMP_DIR" && zip -r artifact.zip * -x "*.git*" "*.pytest_cache*" "__pycache__*")
    
    echo -e "${INFO} Package created at: $TEMP_DIR/artifact.zip"
}

# Upload to S3
upload_to_s3() {
    echo -e "${INFO} Uploading to S3..."
    
    # Ensure bucket exists
    if ! aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
        echo -e "${INFO} Creating S3 bucket: $S3_BUCKET"
        aws s3api create-bucket \
            --bucket "$S3_BUCKET" \
            --region "$REGION"
    fi
    
    # Upload artifact
    aws s3 cp "$TEMP_DIR/artifact.zip" \
        "s3://${S3_BUCKET}/components/${COMPONENT_NAME}/${COMPONENT_VERSION}/artifact.zip"
    
    echo -e "${INFO} Upload complete"
}

# Create component version
create_component() {
    echo -e "${INFO} Creating component version..."
    aws greengrassv2 create-component-version \
        --inline-recipe fileb://"$TEMP_DIR/recipe.yaml"
    echo -e "${INFO} Component version created"
}

# Deploy component
deploy_component() {
    echo -e "${INFO} Deploying component..."
    TARGET_ARN="arn:aws:iot:${REGION}:${AWS_ACCOUNT_ID}:thing/${THING_NAME}"
    
    aws greengrassv2 create-deployment \
        --target-arn "$TARGET_ARN" \
        --deployment-name "${COMPONENT_NAME}-deployment" \
        --components "{\"${COMPONENT_NAME}\": {\"componentVersion\": \"${COMPONENT_VERSION}\"}}"
    
    echo -e "${INFO} Deployment initiated"
}

# Monitor deployment
monitor_deployment() {
    echo -e "${INFO} Monitoring deployment..."
    TARGET_ARN="arn:aws:iot:${REGION}:${AWS_ACCOUNT_ID}:thing/${THING_NAME}"
    
    while true; do
        DEPLOYMENT_STATUS=$(aws greengrassv2 list-deployments \
            --target-arn "$TARGET_ARN" \
            --query 'deployments[0].deploymentStatus' \
            --output text)
        
        echo -e "${INFO} Deployment status: $DEPLOYMENT_STATUS"
        
        case $DEPLOYMENT_STATUS in
            COMPLETED)
                echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
                break
                ;;
            FAILED)
                echo -e "${ERROR} Deployment failed!"
                echo "Check logs: sudo tail -f /greengrass/v2/logs/greengrass.log"
                exit 1
                ;;
            *)
                sleep 10
                ;;
        esac
    done
}

# Main deployment process
main() {
    echo "🚀 Deploying Snack Dispenser component..."
    
    check_aws_credentials
    create_package
    upload_to_s3
    create_component
    deploy_component
    monitor_deployment
    
    echo -e "\n${GREEN}✅ Component deployment completed!${NC}"
    echo -e "${INFO} Next steps:"
    echo "1. Check deployment status:  ./status.sh"
    echo "2. View component logs:      sudo tail -f /greengrass/v2/logs/${COMPONENT_NAME}.log"
    echo "3. Monitor MQTT messages:    aws iot-data get-topic --topic 'snackdispenser/${THING_NAME}/status'"
}

main "$@"