#!/bin/bash
# deploy_aws_sample.sh
# A minimal AWS Greengrass deployment script that sets up a simple
# "hello world" component with basic MQTT functionality

set -e
set -o pipefail

# Configuration
COMPONENT_NAME="com.example.helloworld"
COMPONENT_VERSION="1.0.0"
THING_NAME="HelloWorldCore"
REGION="us-east-1"
S3_BUCKET="hello-world-demo-artifacts"
IOT_POLICY_NAME="HelloWorldPolicy"

echo "🚀 Setting up and deploying Hello World sample component..."

# Ensure AWS CLI is configured
if ! aws sts get-caller-identity &>/dev/null; then
    echo "❌ AWS CLI not configured. Please run 'aws configure' first."
    exit 1
fi

# Create IoT Thing if it doesn't exist
echo "🔧 Setting up AWS IoT Thing..."
if ! aws iot describe-thing --thing-name "$THING_NAME" &>/dev/null; then
    echo "Creating IoT Thing: $THING_NAME"
    aws iot create-thing --thing-name "$THING_NAME"
    
    # Create and attach IoT policy
    echo "Creating IoT Policy..."
    aws iot create-policy --policy-name "$IOT_POLICY_NAME" --policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Action": ["iot:*", "greengrass:*"],
            "Resource": "*"
        }]
    }' || echo "Policy already exists"
    
    # Create certificates
    echo "Creating certificates..."
    CERT_ARN=$(aws iot create-keys-and-certificate --set-as-active \
        --certificate-pem-outfile "device.pem.crt" \
        --private-key-outfile "private.pem.key" \
        --public-key-outfile "public.pem.key" \
        --query 'certificateArn' --output text)
    
    # Attach policy to certificate
    aws iot attach-policy --policy-name "$IOT_POLICY_NAME" --target "$CERT_ARN"
    
    # Attach certificate to thing
    aws iot attach-thing-principal --thing-name "$THING_NAME" --principal "$CERT_ARN"
    
    echo "Created thing, policy, and certificates. Save these files:"
    echo "- device.pem.crt"
    echo "- private.pem.key"
    echo "- public.pem.key"
fi

# Create a temporary directory for our component
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Create the Python component
cat > "$TEMP_DIR/hello_world.py" << 'EOF'
#!/usr/bin/env python3
import time
import json
import logging
import signal
import sys
import awsiot.greengrasscoreipc
from awsiot.greengrasscoreipc.model import (
    PublishMessage,
    QOS
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TIMEOUT = 10
running = True

def signal_handler(signum, frame):
    global running
    logger.info("Signal received, shutting down...")
    running = False

signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

def main():
    ipc_client = awsiot.greengrasscoreipc.connect()
    
    counter = 0
    while running:
        try:
            # Create message
            message = {
                "timestamp": int(time.time()),
                "message": f"Hello from Greengrass! Count: {counter}",
                "counter": counter
            }
            
            # Publish to IoT Core
            request = PublishMessage(
                topic="hello/world",
                qos=QOS.AT_LEAST_ONCE,
                payload=json.dumps(message).encode()
            )
            
            operation = ipc_client.new_publish_to_iot_core()
            operation.activate(request)
            future = operation.get_response()
            future.result(TIMEOUT)
            
            logger.info(f"Published: {message['message']}")
            counter += 1
            time.sleep(5)  # Publish every 5 seconds
            
        except Exception as e:
            logger.error(f"Failed to publish message: {e}")
            time.sleep(5)  # Wait before retrying

    logger.info("Hello World component stopped.")

if __name__ == "__main__":
    main()
EOF

# Create requirements.txt
cat > "$TEMP_DIR/requirements.txt" << 'EOF'
awsiotsdk
EOF

# Create the recipe file
cat > "$TEMP_DIR/recipe.yaml" << EOF
---
RecipeFormatVersion: 2020-01-25
ComponentName: ${COMPONENT_NAME}
ComponentVersion: ${COMPONENT_VERSION}
ComponentDescription: "A simple Hello World component that publishes messages to AWS IoT Core"
ComponentPublisher: Example
ComponentConfiguration:
  DefaultConfiguration:
    accessControl:
      aws.greengrass.ipc.mqttproxy:
        ${COMPONENT_NAME}:mqttproxy:1:
          policyDescription: "Allows access to publish messages"
          operations:
            - aws.greengrass#PublishToIoTCore
          resources:
            - "hello/world"
Manifests:
  - Platform:
      os: linux
    Artifacts:
      - URI: s3://${S3_BUCKET}/hello-world.zip
        Unarchive: ZIP
    Lifecycle:
      Install:
        Script: |
          python3 -m pip install --user -r {artifacts:decompressedPath}/requirements.txt
      Run:
        Script: |
          python3 {artifacts:decompressedPath}/hello_world.py
EOF

# Create and upload artifacts
echo "📦 Creating and uploading artifacts..."
(cd "$TEMP_DIR" && zip -r hello-world.zip *)

# Create S3 bucket if it doesn't exist
if ! aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
    aws s3api create-bucket --bucket "$S3_BUCKET" --region "$REGION"
fi

aws s3 cp "$TEMP_DIR/hello-world.zip" "s3://${S3_BUCKET}/hello-world.zip"

# Create or update component
echo "🛠️ Creating component version..."
aws greengrassv2 create-component-version \
    --inline-recipe fileb://"$TEMP_DIR/recipe.yaml"

# Deploy the component
echo "🚀 Deploying component..."
DEPLOYMENT_NAME="HelloWorldDeployment"
TARGET_ARN="arn:aws:iot:${REGION}:$(aws sts get-caller-identity --query Account --output text):thing/${THING_NAME}"

aws greengrassv2 create-deployment \
    --target-arn "$TARGET_ARN" \
    --deployment-name "$DEPLOYMENT_NAME" \
    --components "{\"${COMPONENT_NAME}\": {\"componentVersion\": \"${COMPONENT_VERSION}\"}}"

echo "✅ Deployment initiated!"
echo ""
echo "Next steps:"
echo "1. If this is your first deployment, you need to set up Greengrass on your device:"
echo "   - Copy the certificate files (device.pem.crt, private.pem.key) to /greengrass/v2/device_credentials/"
echo "   - Download the root CA: curl -o root.ca.pem https://www.amazontrust.com/repository/AmazonRootCA1.pem"
echo "   - Move root.ca.pem to /greengrass/v2/device_credentials/"
echo ""
echo "2. Check deployment status:"
echo "   aws greengrassv2 list-deployments"
echo ""
echo "3. View component logs:"
echo "   sudo tail -f /greengrass/v2/logs/com.example.helloworld.log"
echo ""
echo "4. Monitor messages in AWS IoT Core:"
echo "   aws iot-data get-topic --topic 'hello/world'"
echo ""
echo "5. Use AWS IoT Console to subscribe to 'hello/world' topic"