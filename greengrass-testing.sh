#!/bin/bash
# greengrass-deploy-test.sh
# Deploys a simple test component that publishes MQTT messages

set -e
set -o pipefail

# Source the centralized project configuration
# Make sure aws-config.sh is in the same directory
source ./aws-config.sh

# Use the S3_BUCKET from aws-config.sh and define the test component name
# This changes the component name from "com.example.mqtt.test" to "com.snackdispenser.mqtt.test"
TEST_COMPONENT_NAME="com.${PROJECT_NAME}.mqtt.test"

# Other configuration values
COMPONENT_VERSION="1.0.0"
COMPONENTS_DIR="components"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
INFO="${GREEN}[INFO]${NC}"
WARN="${YELLOW}[WARN]${NC}"
ERROR="${RED}[ERROR]${NC}"

# Configuration file for Greengrass setup (created by aws-setup.sh)
CONFIG_FILE="greengrass-config.json"

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${ERROR} Configuration file $CONFIG_FILE not found!"
    echo "Please run aws-setup.sh first"
    exit 1
fi

# Load config values
THING_NAME=$(jq -r '.thingName' "$CONFIG_FILE")
REGION=$(jq -r '.region' "$CONFIG_FILE")
AWS_ACCOUNT_ID=$(jq -r '.accountId' "$CONFIG_FILE")

# Clean previous failed deployments
cleanup_failed_deployments() {
    echo -e "${INFO} Cleaning up any failed deployments..."
    sudo rm -rf /greengrass/v2/deployments/*
}

# Verify source files exist
verify_sources() {
    echo -e "${INFO} Verifying source files..."
    if [ ! -f "src/test/mqtt_test.py" ]; then
        echo -e "${ERROR} Missing: src/test/mqtt_test.py"
        echo -e "${INFO} Creating src/test directory..."
        mkdir -p src/test
        
        # Create the test file
        cat > src/test/mqtt_test.py << 'EOF'
#!/usr/bin/env python3
import time
import json
import traceback
import sys
import awsiot.greengrasscoreipc
import awsiot.greengrasscoreipc.client as client
from awsiot.greengrasscoreipc.model import (
    PublishToIoTCoreRequest,
    QOS
)

print("Starting MQTT Test Component...")
sys.stdout.flush()

try:
    ipc_client = awsiot.greengrasscoreipc.connect()
    print("Successfully connected to IPC client")
    sys.stdout.flush()
    
    while True:
        try:
            message = {
                "message": "Hello from Greengrass!",
                "timestamp": time.time()
            }
            
            request = PublishToIoTCoreRequest(
                topic_name="test/messages",
                qos=QOS.AT_LEAST_ONCE,
                payload=json.dumps(message).encode()
            )
            
            operation = ipc_client.new_publish_to_iot_core()
            operation.activate(request)
            future = operation.get_response()
            future.result(timeout=5.0)
            
            print(f"Successfully published: {message}")
            sys.stdout.flush()
            
        except Exception as e:
            print(f"Failed to publish message: {e}")
            print(traceback.format_exc())
            sys.stdout.flush()
        
        time.sleep(5)

except Exception as e:
    print(f"Exception in main: {e}")
    print(traceback.format_exc())
    sys.stdout.flush()
EOF
        chmod +x src/test/mqtt_test.py
    fi
}

# Create S3 bucket for components
# Uses the S3_BUCKET from aws-config.sh
create_s3_bucket() {
    echo -e "${INFO} Creating S3 bucket for components..."
    if ! aws s3 ls "s3://${S3_BUCKET}" 2>&1 > /dev/null; then
        aws s3 mb "s3://${S3_BUCKET}" --region "$REGION"
    else
        echo -e "${WARN} S3 bucket already exists"
    fi
}

# Package component
package_component() {
    echo -e "${INFO} Packaging test component..."
    
    # Create component directories
    rm -rf "$COMPONENTS_DIR"
    mkdir -p "$COMPONENTS_DIR/test"
    mkdir -p "$COMPONENTS_DIR/recipes"
    
    # Copy source file
    cp src/test/mqtt_test.py "$COMPONENTS_DIR/test/"
    
    # Create recipe with proper bucket name and using the TEST_COMPONENT_NAME
    cat > "$COMPONENTS_DIR/recipes/${TEST_COMPONENT_NAME}.yaml" << EOF
---
RecipeFormatVersion: 2020-01-25
ComponentName: ${TEST_COMPONENT_NAME}
ComponentVersion: ${COMPONENT_VERSION}
ComponentDescription: "Simple MQTT test component"
ComponentPublisher: Example
ComponentConfiguration:
  DefaultConfiguration:
    accessControl:
      aws.greengrass.ipc.mqttproxy:
        ${TEST_COMPONENT_NAME}:mqtt:1:
          policyDescription: "Allows access to publish to test/messages topic"
          operations:
            - aws.greengrass#PublishToIoTCore
          resources:
            - test/messages
ComponentDependencies:
  aws.greengrass.TokenExchangeService:
    VersionRequirement: ^2.0.0
Manifests:
  - Platform:
      os: linux
    Artifacts:
      - URI: s3://${S3_BUCKET}/test/test.zip
        Unarchive: ZIP
    Lifecycle:
      Run:
        RequiresPrivilege: false
        Script: python3 {artifacts:decompressedPath}/test/mqtt_test.py
EOF
    
    # Create zip package
    (cd "$COMPONENTS_DIR/test" && zip -r ../test.zip .)
}

# Upload component to S3
upload_component() {
    echo -e "${INFO} Uploading component to S3..."
    
    # Check if bucket is accessible
    if ! aws s3 ls "s3://${S3_BUCKET}" &>/dev/null; then
        echo -e "${ERROR} Cannot access S3 bucket. Please verify it exists and you have permissions."
        exit 1
    fi
    
    aws s3 cp "$COMPONENTS_DIR/test.zip" "s3://${S3_BUCKET}/test/"
    echo -e "${INFO} Upload of test.zip completed"
}

# Create and deploy component
create_deployment() {
    echo -e "${INFO} Creating Greengrass deployment..."
    
    # Create component from recipe using the TEST_COMPONENT_NAME
    aws greengrassv2 create-component-version \
        --inline-recipe fileb://"$COMPONENTS_DIR/recipes/${TEST_COMPONENT_NAME}.yaml" \
        --region "$REGION"
    
    # Create deployment with required nucleus components
    aws greengrassv2 create-deployment \
        --target-arn "arn:aws:iot:${REGION}:${AWS_ACCOUNT_ID}:thing/${THING_NAME}" \
        --deployment-name "TestMQTTDeployment" \
        --components '{
            "aws.greengrass.Cli": {
                "componentVersion": "2.13.0"
            },
            "aws.greengrass.TokenExchangeService": {
                "componentVersion": "2.0.3"
            },
            "'"${TEST_COMPONENT_NAME}"'": {
                "componentVersion": "1.0.0"
            }
        }' \
        --region "$REGION"
}

# Verify deployment
verify_deployment() {
    echo -e "${INFO} Verifying deployment..."
    echo -e "${INFO} Waiting for deployment to complete (this may take a minute)..."
    
    # Wait for deployment (up to 2 minutes)
    for i in {1..24}; do
        if aws greengrassv2 list-installed-components \
            --core-device-thing-name "$THING_NAME" \
            --region "$REGION" | grep -q "${TEST_COMPONENT_NAME}"; then
            echo -e "${INFO} Component successfully deployed!"
            return 0
        fi
        echo -n "."
        sleep 5
    done
    
    echo -e "\n${ERROR} Deployment verification timed out. Checking Greengrass logs..."
    sudo tail -n 50 /greengrass/v2/logs/greengrass.log
    exit 1
}

# Main deployment process
main() {
    echo "🚀 Deploying test MQTT component..."
    
    cleanup_failed_deployments
    verify_sources
    create_s3_bucket
    package_component
    upload_component
    create_deployment
    verify_deployment
    
    echo -e "\n${GREEN}✅ Test component deployment completed!${NC}"
    echo -e "${INFO} Next steps:"
    echo "1. Check Greengrass logs: sudo tail -f /greengrass/v2/logs/greengrass.log"
    echo "2. Check component logs: sudo tail -f /greengrass/v2/logs/${TEST_COMPONENT_NAME}.log"
    echo "3. Monitor MQTT messages in AWS IoT Core Test Client (topic: test/messages)"
    echo "4. View component status: sudo /greengrass/v2/bin/greengrass-cli component list"
}

# Run main function
main