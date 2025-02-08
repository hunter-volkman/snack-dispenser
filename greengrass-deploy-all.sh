#!/bin/bash
# greengrass-deploy-vision.sh
# Deploys the combined BowlStateDetector and HopperController component

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

# Verify and create required files
verify_sources() {
    echo -e "${INFO} Verifying source files..."
    
    # Create directories
    mkdir -p src/vision
    mkdir -p src/config
    
    # Create config.yaml for motor settings
    if [ ! -f "src/config/config.yaml" ]; then
        echo -e "${INFO} Creating motor configuration file..."
        cat > src/config/config.yaml << 'EOF'
hardware:
  motor:
    step_pin: 16
    dir_pin: 15
    en_pin: 18
EOF
    fi

    # Create main Python script
    if [ ! -f "src/vision/bowl_state_detector.py" ]; then
        echo -e "${WARN} Main component source not found. Creating it..."
        cat > src/vision/bowl_state_detector.py << 'EOF'
#!/usr/bin/env python3
# Combined BowlState and Hopper Controller
import cv2
import numpy as np
import joblib
import time
import json
import os
import sys
import traceback
import RPi.GPIO as GPIO
import yaml
import logging
import awsiot.greengrasscoreipc
import awsiot.greengrasscoreipc.client as client
from awsiot.greengrasscoreipc.model import (
    PublishToIoTCoreRequest,
    QOS
)

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger("BowlStateAndHopper")

# Vision configuration
IMAGE_SIZE = (224, 224)
CONFIDENCE_THRESHOLD = 0.7
CAMERA_ID = 0
CAMERA_WIDTH = 640
CAMERA_HEIGHT = 480

class BowlStateAndHopperController:
    def __init__(self):
        logger.info("Initializing combined controller...")
        self.setup_motor()
        self.model = self.load_model()
        self.cap = self.setup_camera()
        self.ipc_client = None
        self.consecutive_failures = 0
        self.MAX_CONSECUTIVE_FAILURES = 3
        logger.info("Initialization complete")

    def setup_motor(self):
        """Initialize motor configuration and GPIO setup"""
        self.load_motor_config()
        logger.info("Setting up GPIO pins...")
        GPIO.setmode(GPIO.BOARD)
        GPIO.setup([self.step_pin, self.dir_pin, self.en_pin], GPIO.OUT)
        GPIO.output(self.en_pin, GPIO.HIGH)
        logger.info("GPIO setup complete")

    def load_motor_config(self):
        """Load motor configuration from YAML file"""
        try:
            config_path = os.path.join(
                os.path.dirname(os.path.abspath(__file__)),
                "config.yaml"
            )
            with open(config_path, "r") as f:
                config = yaml.safe_load(f)
                motor_config = config.get("hardware", {}).get("motor", {})
                self.step_pin = motor_config.get("step_pin", 16)
                self.dir_pin = motor_config.get("dir_pin", 15)
                self.en_pin = motor_config.get("en_pin", 18)
                logger.info(f"Motor configuration loaded: {motor_config}")
        except Exception as e:
            logger.warning(f"Error loading motor config: {e}. Using defaults")
            self.step_pin, self.dir_pin, self.en_pin = 16, 15, 18

    def load_model(self):
        """Load the pre-trained bowl state model"""
        base_dir = os.path.dirname(os.path.abspath(__file__))
        model_path = os.path.join(base_dir, "bowl_state_model.joblib")
        try:
            model = joblib.load(model_path)
            logger.info(f"Model loaded successfully from {model_path}")
            return model
        except Exception as e:
            logger.error(f"Failed to load model: {e}")
            raise

    def setup_camera(self):
        """Initialize the camera"""
        cap = cv2.VideoCapture(CAMERA_ID)
        if not cap.isOpened():
            raise RuntimeError("Failed to open camera")
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, CAMERA_WIDTH)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAMERA_HEIGHT)
        for _ in range(3):  # Flush frames
            cap.grab()
        logger.info(f"Camera opened with resolution {CAMERA_WIDTH}x{CAMERA_HEIGHT}")
        return cap

    def enable_motor(self):
        """Enable the stepper motor"""
        logger.info("Enabling motor")
        GPIO.output(self.en_pin, GPIO.LOW)
        time.sleep(0.05)

    def disable_motor(self):
        """Disable the stepper motor"""
        logger.info("Disabling motor")
        GPIO.output(self.en_pin, GPIO.HIGH)

    def step(self, steps, rpm=30, steps_per_rev=200):
        """Move the motor a specified number of steps"""
        logger.info(f"Stepping motor: {steps} steps at {rpm} RPM")
        delay = 60.0 / (rpm * steps_per_rev)
        for i in range(steps):
            GPIO.output(self.step_pin, GPIO.HIGH)
            time.sleep(delay)
            GPIO.output(self.step_pin, GPIO.LOW)
            time.sleep(delay)

    def dispense(self, portions=1):
        """Dispense a specified number of portions"""
        logger.info(f"Starting dispensing for {portions} portion(s)")
        try:
            self.enable_motor()
            steps_per_portion = 200
            for i in range(1, portions+1):
                logger.info(f"Dispensing portion {i}/{portions}")
                self.step(steps_per_portion)
                time.sleep(0.5)
            logger.info("Dispensing complete")
        except Exception as e:
            logger.error(f"Error during dispensing: {e}")
        finally:
            self.disable_motor()

    def preprocess_frame(self, frame):
        """Prepare a frame for model inference"""
        resized = cv2.resize(frame, IMAGE_SIZE)
        rgb = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB)
        flattened = rgb.flatten().reshape(1, -1)
        return flattened

    def is_bowl_empty(self):
        """Capture frame and determine if bowl is empty"""
        ret, frame = self.cap.read()
        if not ret:
            logger.error("Failed to capture frame")
            return False, 0.0
        processed = self.preprocess_frame(frame)
        prediction = self.model.predict_proba(processed)[0]
        is_empty = prediction[0] > CONFIDENCE_THRESHOLD
        confidence = float(max(prediction))
        return is_empty, confidence

    def get_ipc_client(self):
        """Create or get existing IPC client with retry logic"""
        MAX_RECONNECT_ATTEMPTS = 5
        RETRY_INTERVAL = 2

        for attempt in range(MAX_RECONNECT_ATTEMPTS):
            try:
                logger.info(f"Connecting to IPC (attempt {attempt + 1}/{MAX_RECONNECT_ATTEMPTS})...")
                client = awsiot.greengrasscoreipc.connect()
                logger.info("Successfully connected to IPC")
                return client
            except Exception as e:
                logger.error(f"Connection attempt {attempt + 1} failed: {str(e)}")
                if attempt < MAX_RECONNECT_ATTEMPTS - 1:
                    time.sleep(RETRY_INTERVAL)

        raise ConnectionError("Failed to establish IPC connection after maximum retries")

    def publish_state(self, is_empty, confidence):
        """Publish bowl state via MQTT with retry logic"""
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
                operation = self.ipc_client.new_publish_to_iot_core()
                operation.activate(request)
                future = operation.get_response()
                future.result(timeout=5.0)
                logger.info(f"Successfully published: {message}")
                return True
            except Exception as e:
                logger.error(f"Publish attempt {attempt + 1} failed: {str(e)}")
                if attempt == MAX_PUBLISH_RETRIES - 1:
                    logger.error(traceback.format_exc())
                if attempt < MAX_PUBLISH_RETRIES - 1:
                    time.sleep(1)
        
        return False

    def run(self):
        """Main loop combining bowl state detection and automatic dispensing"""
        logger.info("Starting combined BowlState and Hopper controller...")
        
        try:
            self.ipc_client = self.get_ipc_client()
            
            while True:
                try:
                    # Check if we need to reconnect IPC
                    if self.ipc_client is None:
                        self.ipc_client = self.get_ipc_client()
                    
                    # Get bowl state
                    is_empty, conf = self.is_bowl_empty()
                    logger.info(f"Bowl is {'empty' if is_empty else 'full'} with confidence {conf:.2f}")
                    
                    # Publish state
                    if not self.publish_state(is_empty, conf):
                        self.consecutive_failures += 1
                        logger.warning(f"Publishing failed {self.consecutive_failures} times in a row")
                        
                        if self.consecutive_failures >= self.MAX_CONSECUTIVE_FAILURES:
                            logger.warning("Too many consecutive failures, recreating IPC client...")
                            self.ipc_client = None
                            self.consecutive_failures = 0
                    else:
                        self.consecutive_failures = 0
                    
                    # Automatically dispense if bowl is empty
                    if is_empty and conf > CONFIDENCE_THRESHOLD:
                        logger.info("Bowl detected as empty, initiating dispensing...")
                        self.dispense()
                    
                    time.sleep(10)
                    
                except Exception as e:
                    logger.error(f"Error in main loop: {str(e)}")
                    logger.error(traceback.format_exc())
                    time.sleep(10)  # Wait before retrying
                    
        except KeyboardInterrupt:
            logger.info("Keyboard interrupt received. Exiting.")
        except Exception as e:
            logger.error(f"Fatal error in main: {str(e)}")
            logger.error(traceback.format_exc())
        finally:
            if self.cap:
                self.cap.release()
                logger.info("Camera released")
            GPIO.cleanup()
            logger.info("GPIO cleaned up")
            logger.info("Component shutdown complete")

if __name__ == "__main__":
    controller = BowlStateAndHopperController()
    controller.run()
EOF
        chmod +x src/vision/bowl_state_detector.py
    fi

    # Create requirements.txt
    if [ ! -f "src/requirements.txt" ]; then
        echo -e "${INFO} Creating requirements.txt..."
        cat > src/requirements.txt << 'EOF'
opencv-python
numpy
joblib
RPi.GPIO
PyYAML
awsiotsdk
EOF
    fi

    # Warn if model file is missing
    if [ ! -f "src/vision/bowl_state_model.joblib" ]; then
        echo -e "${WARN} Model file src/vision/bowl_state_model.joblib not found. Please add your trained model file."
    fi
}

# Install system dependencies
install_dependencies() {
    echo -e "${INFO} Installing system dependencies..."
    # Required for OpenCV and GPIO access
    sudo apt-get update
    sudo apt-get install -y python3-opencv python3-rpi.gpio python3-pip
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
# Package component
package_component() {
    echo -e "${INFO} Packaging component..."
    
    # Clean and create directories
    rm -rf "$COMPONENTS_DIR"
    mkdir -p "$COMPONENTS_DIR/vision"
    mkdir -p "$COMPONENTS_DIR/config"
    mkdir -p "$COMPONENTS_DIR/recipes"
    
    # Copy files
    cp src/vision/bowl_state_detector.py "$COMPONENTS_DIR/vision/"
    cp src/config/config.yaml "$COMPONENTS_DIR/config/"
    cp src/requirements.txt "$COMPONENTS_DIR/vision/"  # Copy requirements to vision directory
    if [ -f "src/vision/bowl_state_model.joblib" ]; then
        cp src/vision/bowl_state_model.joblib "$COMPONENTS_DIR/vision/"
    fi
    
    # Create component recipe
    cat > "$COMPONENTS_DIR/recipes/com.example.vision.bowlstate.yaml" << EOF
---
RecipeFormatVersion: 2020-01-25
ComponentName: com.example.vision.bowlstate
ComponentVersion: ${COMPONENT_VERSION}
ComponentDescription: "Component that detects bowl state and controls the hopper motor"
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
      aws.greengrass.hardware.gpio:
        com.example.vision.bowlstate:gpio:1:
          policyDescription: "Allows access to GPIO"
          operations:
            - aws.greengrass.hardware.gpio.Read
            - aws.greengrass.hardware.gpio.Write
          resources:
            - "*"
ComponentDependencies:
  aws.greengrass.TokenExchangeService:
    VersionRequirement: ^2.0.0
  aws.greengrass.Nucleus:
    VersionRequirement: ^2.0.0
Manifests:
  - Platform:
      os: linux
    Lifecycle:
      Install:
        Script: |
          apt-get update
          apt-get install -y python3-opencv python3-rpi.gpio python3-pip
          pip3 install -r {artifacts:decompressedPath}/vision/requirements.txt
      Run:
        RequiresPrivilege: true
        Script: |
          export PYTHONPATH={artifacts:decompressedPath}/vision
          python3 {artifacts:decompressedPath}/vision/bowl_state_detector.py
    Artifacts:
      - URI: s3://${S3_BUCKET}/vision/vision.zip
        Unarchive: ZIP
      - URI: s3://${S3_BUCKET}/config/config.zip
        Unarchive: ZIP
EOF
    
    # Create zip packages
    (cd "$COMPONENTS_DIR/vision" && zip -r ../vision.zip .)
    (cd "$COMPONENTS_DIR/config" && zip -r ../config.zip .)
}

# Upload component
upload_component() {
    echo -e "${INFO} Uploading component packages to S3..."
    if ! aws s3 ls "s3://${S3_BUCKET}" >/dev/null 2>&1; then
        echo -e "${ERROR} Cannot access S3 bucket. Please verify its existence and your permissions."
        exit 1
    fi
    aws s3 cp "$COMPONENTS_DIR/vision.zip" "s3://${S3_BUCKET}/vision/"
    aws s3 cp "$COMPONENTS_DIR/config.zip" "s3://${S3_BUCKET}/config/"
    echo -e "${INFO} Upload completed."
}

# Create deployment
create_deployment() {
    echo -e "${INFO} Creating Greengrass deployment..."
    
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
            "aws.greengrass.Nucleus": {
                "componentVersion": "2.13.0"
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
    echo "🚀 Deploying combined BowlState and Hopper controller..."
    cleanup_failed_deployments
    verify_sources
    install_dependencies
    create_s3_bucket
    package_component
    upload_component
    create_deployment
    verify_deployment
    
    echo -e "\n${GREEN}✅ Component deployment completed!${NC}"
    echo -e "${INFO} Next steps:"
    echo "1. Check Greengrass logs: sudo tail -f /greengrass/v2/logs/greengrass.log"
    echo "2. Check component logs: sudo tail -f /greengrass/v2/logs/com.example.vision.bowlstate.log"
    echo "3. Monitor MQTT messages in AWS IoT Core Test Client (topic: bowl/state)"
    echo "4. View component status: sudo /greengrass/v2/bin/greengrass-cli component list"
}

# Run main function
main