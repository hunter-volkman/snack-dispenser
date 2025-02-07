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
