#!/bin/bash
# greengrass-deploy-vision.sh
# Deploys the BowlStateDetector component which uses vision to detect bowl state (empty/full)
# and publishes the result via MQTT.

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

# Configuration
CONFIG_FILE="greengrass-config.json"
COMPONENT_VERSION="1.0.0"
S3_BUCKET="edge-snack-dispenser-demo-artifacts"
COMPONENTS_DIR="components"

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${ERROR} Configuration file $CONFIG_FILE not found!"
    echo "Please run aws-setup.sh first"
    exit 1
fi

# Load config values from JSON
THING_NAME=$(jq -r '.thingName' "$CONFIG_FILE")
REGION=$(jq -r '.region' "$CONFIG_FILE")
AWS_ACCOUNT_ID=$(jq -r '.accountId' "$CONFIG_FILE")

# Clean up any previous failed deployments
cleanup_failed_deployments() {
    echo -e "${INFO} Cleaning up any failed deployments..."
    sudo rm -rf /greengrass/v2/deployments/*
}

# Verify (and if needed, create) the Python source file
verify_sources() {
    echo -e "${INFO} Verifying source files for BowlStateDetector..."
    if [ ! -f "src/vision/bowl_state_detector.py" ]; then
        echo -e "${WARN} BowlStateDetector source not found. Creating it..."
        mkdir -p src/vision
        cat > src/vision/bowl_state_detector.py << 'EOF'
#!/usr/bin/env python3
import cv2
import numpy as np
import joblib
import time
import json
import os
import sys
import traceback
import awsiot.greengrasscoreipc
import awsiot.greengrasscoreipc.client as client
from awsiot.greengrasscoreipc.model import (
    PublishToIoTCoreRequest,
    QOS
)

# --- Default configuration values ---
IMAGE_SIZE = (224, 224)             # Resize frames to 224x224
CONFIDENCE_THRESHOLD = 0.7          # Threshold for considering bowl empty
CAMERA_ID = 0                       # Default camera device ID
CAMERA_WIDTH = 640                  # Camera resolution width
CAMERA_HEIGHT = 480                 # Camera resolution height

def load_model():
    """Load the pre-trained bowl state model."""
    base_dir = os.path.dirname(os.path.abspath(__file__))
    model_path = os.path.join(base_dir, "bowl_state_model.joblib")
    try:
        model = joblib.load(model_path)
        print(f"Model loaded successfully from {model_path}")
        sys.stdout.flush()
        return model
    except Exception as e:
        print(f"Failed to load model: {e}")
        print(traceback.format_exc())
        sys.stdout.flush()
        raise

def setup_camera():
    """Open the camera and set its resolution."""
    cap = cv2.VideoCapture(CAMERA_ID)
    if not cap.isOpened():
        raise RuntimeError("Failed to open camera")
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, CAMERA_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAMERA_HEIGHT)
    for _ in range(3):  # Flush frames
        cap.grab()
    print(f"Camera opened with resolution {CAMERA_WIDTH}x{CAMERA_HEIGHT}")
    sys.stdout.flush()
    return cap

def preprocess_frame(frame):
    """Resize and convert the frame for model input."""
    resized = cv2.resize(frame, IMAGE_SIZE)
    rgb = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB)
    flattened = rgb.flatten().reshape(1, -1)
    return flattened

def is_bowl_empty(cap, model):
    """Capture frame, process it, and determine if bowl is empty."""
    ret, frame = cap.read()
    if not ret:
        print("Failed to capture frame")
        sys.stdout.flush()
        return False, 0.0
    processed = preprocess_frame(frame)
    prediction = model.predict_proba(processed)[0]
    is_empty = prediction[0] > CONFIDENCE_THRESHOLD
    confidence = float(max(prediction))
    return is_empty, confidence

def publish_state(ipc_client, is_empty, confidence):
    """Publish bowl state via MQTT using Greengrass IPC."""
    try:
        message = {
            "message": "Bowl State Update",
            "empty": bool(is_empty),
            "confidence": float(confidence),
            "timestamp": time.time()
        }
        
        request = PublishToIoTCoreRequest(
            topic_name="bowl/state",
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
        print(f"Failed to publish message: {str(e)}")
        print(traceback.format_exc())
        sys.stdout.flush()

def get_ipc_client():
    """Create or get existing IPC client with connection retry logic."""
    MAX_RECONNECT_ATTEMPTS = 5
    RETRY_INTERVAL = 2  # seconds
    
    for attempt in range(MAX_RECONNECT_ATTEMPTS):
        try:
            print(f"Connecting to IPC (attempt {attempt + 1}/{MAX_RECONNECT_ATTEMPTS})...")
            sys.stdout.flush()
            client = awsiot.greengrasscoreipc.connect()
            print("Successfully connected to IPC")
            sys.stdout.flush()
            return client
        except Exception as e:
            print(f"Connection attempt {attempt + 1} failed: {str(e)}")
            sys.stdout.flush()
            if attempt < MAX_RECONNECT_ATTEMPTS - 1:
                time.sleep(RETRY_INTERVAL)
    
    raise ConnectionError("Failed to establish IPC connection after maximum retries")

def publish_state(ipc_client, is_empty, confidence):
    """Publish bowl state via MQTT using Greengrass IPC."""
    MAX_PUBLISH_RETRIES = 3
    
    message = {
        "message": "Bowl State Update",
        "empty": bool(is_empty),
        "confidence": float(confidence),
        "timestamp": time.time()
    }
    
    request = PublishToIoTCoreRequest(
        topic_name="bowl/state",
        qos=QOS.AT_LEAST_ONCE,
        payload=json.dumps(message).encode()
    )
    
    for attempt in range(MAX_PUBLISH_RETRIES):
        try:
            operation = ipc_client.new_publish_to_iot_core()
            operation.activate(request)
            future = operation.get_response()
            future.result(timeout=5.0)
            print(f"Successfully published: {message}")
            sys.stdout.flush()
            return True
        except Exception as e:
            print(f"Publish attempt {attempt + 1} failed: {str(e)}")
            if attempt == MAX_PUBLISH_RETRIES - 1:
                print(traceback.format_exc())
            sys.stdout.flush()
            if attempt < MAX_PUBLISH_RETRIES - 1:
                time.sleep(1)
    
    return False

def main():
    print("Starting BowlStateDetector component...")
    sys.stdout.flush()
    
    model = None
    cap = None
    ipc_client = None
    consecutive_failures = 0
    MAX_CONSECUTIVE_FAILURES = 3
    
    try:
        # Initial setup
        model = load_model()
        cap = setup_camera()
        ipc_client = get_ipc_client()
        
        while True:
            try:
                # Check if we need to reconnect IPC
                if ipc_client is None:
                    ipc_client = get_ipc_client()
                
                # Get bowl state
                is_empty, conf = is_bowl_empty(cap, model)
                print(f"Bowl is {'empty' if is_empty else 'full'} with confidence {conf:.2f}")
                sys.stdout.flush()
                
                # Publish state
                if not publish_state(ipc_client, is_empty, conf):
                    consecutive_failures += 1
                    print(f"Publishing failed {consecutive_failures} times in a row")
                    sys.stdout.flush()
                    
                    if consecutive_failures >= MAX_CONSECUTIVE_FAILURES:
                        print("Too many consecutive failures, recreating IPC client...")
                        sys.stdout.flush()
                        ipc_client = None
                        consecutive_failures = 0
                else:
                    consecutive_failures = 0
                
                time.sleep(10)
                
            except Exception as e:
                print(f"Error in main loop: {str(e)}")
                print(traceback.format_exc())
                sys.stdout.flush()
                time.sleep(10)  # Wait before retrying
                
    except KeyboardInterrupt:
        print("Keyboard interrupt received. Exiting.")
        sys.stdout.flush()
    except Exception as e:
        print(f"Fatal error in main: {str(e)}")
        print(traceback.format_exc())
        sys.stdout.flush()
    finally:
        if cap:
            cap.release()
            print("Camera released.")
        print("Exiting component.")
        sys.stdout.flush()

if __name__ == "__main__":
    main()
EOF
        chmod +x src/vision/bowl_state_detector.py
    fi

    # Warn if model file is missing
    if [ ! -f "src/vision/bowl_state_model.joblib" ]; then
        echo -e "${WARN} Model file src/vision/bowl_state_model.joblib not found. Please add your trained model file."
    fi
}

# Create S3 bucket if needed
create_s3_bucket() {
    echo -e "${INFO} Creating S3 bucket for components..."
    if ! aws s3 ls "s3://${S3_BUCKET}" >/dev/null 2>&1; then
        aws s3 mb "s3://${S3_BUCKET}" --region "$REGION"
    else
        echo -e "${WARN} S3 bucket already exists."
    fi
}

# Package component
package_component() {
    echo -e "${INFO} Packaging BowlStateDetector component..."
    
    # Clean and create directories
    rm -rf "$COMPONENTS_DIR"
    mkdir -p "$COMPONENTS_DIR/vision"
    mkdir -p "$COMPONENTS_DIR/recipes"
    
    # Copy files
    cp src/vision/bowl_state_detector.py "$COMPONENTS_DIR/vision/"
    if [ -f "src/vision/bowl_state_model.joblib" ]; then
        cp src/vision/bowl_state_model.joblib "$COMPONENTS_DIR/vision/"
    fi
    
    # Create component recipe
    cat > "$COMPONENTS_DIR/recipes/com.example.vision.bowlstate.yaml" << EOF
---
RecipeFormatVersion: 2020-01-25
ComponentName: com.example.vision.bowlstate
ComponentVersion: ${COMPONENT_VERSION}
ComponentDescription: "Component that detects if the bowl is empty or full using vision and publishes the state via MQTT."
ComponentPublisher: Example
ComponentConfiguration:
  DefaultConfiguration:
    accessControl:
      aws.greengrass.ipc.mqttproxy:
        com.example.vision.bowlstate:mqtt:1:
          policyDescription: "Allows access to publish to bowl/state topic"
          operations:
            - aws.greengrass#PublishToIoTCore
          resources:
            - bowl/state
ComponentDependencies:
  aws.greengrass.TokenExchangeService:
    VersionRequirement: ^2.0.0
Manifests:
  - Platform:
      os: linux
    Artifacts:
      - URI: s3://${S3_BUCKET}/vision/vision.zip
        Unarchive: ZIP
    Lifecycle:
      Run:
        RequiresPrivilege: true
        Script: python3 {artifacts:decompressedPath}/vision/bowl_state_detector.py
EOF
    
    # Create zip package
    (cd "$COMPONENTS_DIR/vision" && zip -r ../vision.zip .)
}

# Upload component
upload_component() {
    echo -e "${INFO} Uploading component package to S3..."
    if ! aws s3 ls "s3://${S3_BUCKET}" >/dev/null 2>&1; then
        echo -e "${ERROR} Cannot access S3 bucket. Please verify its existence and your permissions."
        exit 1
    fi
    aws s3 cp "$COMPONENTS_DIR/vision.zip" "s3://${S3_BUCKET}/vision/"
    echo -e "${INFO} Upload completed."
}

# Create deployment
create_deployment() {
    echo -e "${INFO} Creating Greengrass deployment for BowlStateDetector..."
    
    aws greengrassv2 create-component-version \
        --inline-recipe fileb://"$COMPONENTS_DIR/recipes/com.example.vision.bowlstate.yaml" \
        --region "$REGION"
    
    aws greengrassv2 create-deployment \
        --target-arn "arn:aws:iot:${REGION}:${AWS_ACCOUNT_ID}:thing/${THING_NAME}" \
        --deployment-name "BowlStateDetectorDeployment" \
        --components '{
            "aws.greengrass.Cli": {
                "componentVersion": "2.13.0"
            },
            "aws.greengrass.TokenExchangeService": {
                "componentVersion": "2.0.3"
            },
            "com.example.vision.bowlstate": {
                "componentVersion": "'"${COMPONENT_VERSION}"'"
            }
        }' \
        --region "$REGION"
}

# Verify deployment
verify_deployment() {
    echo -e "${INFO} Verifying deployment..."
    echo -e "${INFO} Waiting for deployment to complete (this may take a few minutes)..."
    
    for i in {1..24}; do
        if aws greengrassv2 list-installed-components --core-device-thing-name "$THING_NAME" --region "$REGION" | grep -q "com.example.vision.bowlstate"; then
            echo -e "${INFO} Component successfully deployed!"
            return 0
        fi
        echo -n "."
        sleep 5
    done
    
    echo -e "\n${ERROR} Deployment verification timed out. Check Greengrass logs for details."
    sudo tail -n 50 /greengrass/v2/logs/greengrass.log
    exit 1
}

# Main deployment process
main() {
    echo "🚀 Deploying BowlStateDetector component..."
    cleanup_failed_deployments
    verify_sources
    create_s3_bucket
    package_component
    upload_component
    create_deployment
    verify_deployment
    
    echo -e "\n${GREEN}✅ BowlStateDetector component deployment completed!${NC}"
    echo -e "${INFO} Next steps:"
    echo "1. Check Greengrass logs: sudo tail -f /greengrass/v2/logs/greengrass.log"
    echo "2. Check component logs: sudo tail -f /greengrass/v2/logs/com.example.vision.bowlstate.log"
    echo "3. Monitor MQTT messages in AWS IoT Core Test Client (topic: bowl/state)"
    echo "4. View component status: sudo /greengrass/v2/bin/greengrass-cli component list"
}

# Run main function
main