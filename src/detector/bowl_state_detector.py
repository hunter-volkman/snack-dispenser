#!/usr/bin/env python3
"""
Combined Bowl State Detector and Motor (Hopper) Controller

This component uses a camera to detect the bowl state (empty/full)
using a pre-trained model, publishes the result via MQTT to AWS IoT Core,
and automatically actuates a stepper motor to dispense portions when the
bowl is detected as empty.

It also subscribes to the "bowl/command" topic. When it receives an ad-hoc
command message such as {"empty": true}, it will trigger the motor.

For development purposes, DEBUG_MODE forces motor activation regardless of
the model’s prediction and DEBUG_SAVE_IMAGES saves each captured image with
debug metadata.
"""

import cv2
import numpy as np
import joblib
import time
import json
import os
import sys
import traceback
import logging
import yaml
import RPi.GPIO as GPIO
import csv
from datetime import datetime

import awsiot.greengrasscoreipc
import awsiot.greengrasscoreipc.client as client
from awsiot.greengrasscoreipc.model import (
    PublishToIoTCoreRequest,
    QOS,
    SubscribeToTopicRequest
)

# ----------------- Development Flags -----------------
DEBUG_MODE = True          # When True, force motor activation for debugging.
DEBUG_SAVE_IMAGES = True   # When True, save captured images and metadata for inspection.
# -------------------------------------------------------

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger("BowlStateAndHopper")

# Detector configuration
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
        """Initialize motor configuration and GPIO setup."""
        self.load_motor_config()
        logger.info("Setting up GPIO pins...")
        GPIO.setmode(GPIO.BOARD)
        GPIO.setup([self.step_pin, self.dir_pin, self.en_pin], GPIO.OUT)
        # Disable the motor by default (assuming HIGH disables it)
        GPIO.output(self.en_pin, GPIO.HIGH)
        logger.info("GPIO setup complete")

    def load_motor_config(self):
        """Load motor configuration from YAML file."""
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
            logger.warning(f"Error loading motor config: {e}. Using default pins")
            self.step_pin, self.dir_pin, self.en_pin = 16, 15, 18

    def load_model(self):
        """Load the pre-trained bowl state model."""
        base_dir = os.path.dirname(os.path.abspath(__file__))
        model_path = os.path.join(base_dir, "bowl_state_model.joblib")
        try:
            model = joblib.load(model_path)
            logger.info(f"Model loaded successfully from {model_path}")
            return model
        except Exception as e:
            logger.error(f"Failed to load model: {e}")
            logger.error(traceback.format_exc())
            sys.exit(1)

    def setup_camera(self):
        """Initialize the camera."""
        cap = cv2.VideoCapture(CAMERA_ID)
        if not cap.isOpened():
            raise RuntimeError("Failed to open camera")
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, CAMERA_WIDTH)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAMERA_HEIGHT)
        for _ in range(3):  # Flush a few frames
            cap.grab()
        logger.info(f"Camera opened with resolution {CAMERA_WIDTH}x{CAMERA_HEIGHT}")
        return cap

    def enable_motor(self):
        """Enable the stepper motor (active low)."""
        logger.info("Enabling motor")
        GPIO.output(self.en_pin, GPIO.LOW)
        time.sleep(0.05)

    def disable_motor(self):
        """Disable the stepper motor."""
        logger.info("Disabling motor")
        GPIO.output(self.en_pin, GPIO.HIGH)

    def step(self, steps, rpm=30, steps_per_rev=200):
        """Move the motor a specified number of steps."""
        logger.info(f"Stepping motor: {steps} steps at {rpm} RPM")
        delay = 60.0 / (rpm * steps_per_rev)
        for i in range(steps):
            GPIO.output(self.step_pin, GPIO.HIGH)
            time.sleep(delay)
            GPIO.output(self.step_pin, GPIO.LOW)
            time.sleep(delay)

    def dispense(self, portions=1):
        """Dispense a specified number of portions by stepping the motor."""
        logger.info(f"Starting dispensing for {portions} portion(s)")
        try:
            self.enable_motor()
            steps_per_portion = 200  # Adjust as necessary for your mechanism
            for i in range(1, portions + 1):
                logger.info(f"Dispensing portion {i}/{portions}")
                self.step(steps_per_portion)
                time.sleep(0.5)
            logger.info("Dispensing complete")
        except Exception as e:
            logger.error(f"Error during dispensing: {e}")
            logger.error(traceback.format_exc())
        finally:
            self.disable_motor()

    def preprocess_frame(self, frame):
        """Prepare a captured frame for model inference."""
        resized = cv2.resize(frame, IMAGE_SIZE)
        rgb = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB)
        flattened = rgb.flatten().reshape(1, -1)
        return flattened

    def save_debug_image(self, frame, timestamp, prediction, is_empty, confidence):
        """Save the captured image and append metadata for debugging."""
        # Create a debug_images folder relative to this file
        debug_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "debug_images")
        if not os.path.exists(debug_dir):
            os.makedirs(debug_dir)
        
        # Create a filename based on the current timestamp
        dt_str = datetime.fromtimestamp(timestamp).strftime("%Y%m%d-%H%M%S")
        filename = f"capture_{dt_str}.jpg"
        file_path = os.path.join(debug_dir, filename)
        
        # Save the image
        cv2.imwrite(file_path, frame)
        
        # Append metadata to a CSV file
        metadata_file = os.path.join(debug_dir, "metadata.csv")
        header = ["timestamp", "filename", "frame_shape", "prediction", "is_empty", "confidence"]
        data_line = [
            str(timestamp),
            filename,
            str(frame.shape),
            str(prediction.tolist() if hasattr(prediction, "tolist") else prediction),
            str(is_empty),
            str(confidence)
        ]
        write_header = not os.path.exists(metadata_file) or os.stat(metadata_file).st_size == 0
        try:
            with open(metadata_file, "a", newline="") as csvfile:
                writer = csv.writer(csvfile)
                if write_header:
                    writer.writerow(header)
                writer.writerow(data_line)
            logger.info(f"Saved debug image to {file_path} with metadata appended.")
        except Exception as e:
            logger.error(f"Failed to write debug metadata: {e}")

    def is_bowl_empty(self):
        """Capture a frame and determine if the bowl is empty."""
        # Flush extra frames to get a more up-to-date image
        for _ in range(5):
            self.cap.grab()
            ret, frame = self.cap.read()
        ret, frame = self.cap.read()
        if not ret:
            logger.error("Failed to capture frame")
            return False, 0.0

        # Get current timestamp and log frame details
        capture_time = time.time()
        logger.info(f"Captured frame at {capture_time} with shape {frame.shape}")

        processed = self.preprocess_frame(frame)
        try:
            prediction = self.model.predict_proba(processed)[0]
        except Exception as e:
            logger.error(f"Error during model inference: {e}")
            return False, 0.0

        # Standard decision based on the model's prediction
        is_empty = prediction[0] > CONFIDENCE_THRESHOLD
        confidence = float(max(prediction))

        # If in debug mode, override the model’s decision so the motor always activates
        if DEBUG_MODE:
            logger.info("DEBUG_MODE enabled: Forcing bowl status to empty for testing")
            is_empty = True

        # Save the debug image and metadata if enabled.
        if DEBUG_SAVE_IMAGES:
            self.save_debug_image(frame, capture_time, prediction, is_empty, confidence)

        logger.info(f"Model prediction: {prediction} => bowl is {'empty' if is_empty else 'full'} with confidence {confidence:.2f}")
        return is_empty, confidence

    def get_ipc_client(self):
        """Create or get an existing IPC client with retry logic."""
        MAX_RECONNECT_ATTEMPTS = 5
        RETRY_INTERVAL = 2  # seconds
        for attempt in range(MAX_RECONNECT_ATTEMPTS):
            try:
                logger.info(f"Connecting to IPC (attempt {attempt + 1}/{MAX_RECONNECT_ATTEMPTS})...")
                ipc_client = awsiot.greengrasscoreipc.connect()
                logger.info("Successfully connected to IPC")
                return ipc_client
            except Exception as e:
                logger.error(f"IPC connection attempt {attempt + 1} failed: {str(e)}")
                if attempt < MAX_RECONNECT_ATTEMPTS - 1:
                    time.sleep(RETRY_INTERVAL)
        raise ConnectionError("Failed to establish IPC connection after maximum retries")

    def publish_state(self, is_empty, confidence):
        """Publish bowl state via MQTT with retry logic."""
        MAX_PUBLISH_RETRIES = 3

        # Add an extra field to indicate whether the motor should be activated
        motor_activation = bool(is_empty and confidence > CONFIDENCE_THRESHOLD)
        message = {
            "message": "Bowl State Update",
            "empty": bool(is_empty),
            "confidence": float(confidence),
            "timestamp": time.time(),
            "activateMotor": motor_activation
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

    def subscribe_for_commands(self):
        """Subscribe to the 'bowl/command' topic to allow ad-hoc motor triggers."""
        try:
            subscribe_request = SubscribeToTopicRequest(
                topic="bowl/command",
                qos=QOS.AT_LEAST_ONCE
            )

            def on_command(message):
                try:
                    payload = message.payload.decode()
                    command = json.loads(payload)
                    logger.info(f"Received command: {command}")
                    if command.get("empty") is True:
                        logger.info("Ad-hoc command received. Triggering motor dispensing...")
                        self.dispense()
                except Exception as e:
                    logger.error(f"Error processing command message: {e}")

            subscribe_op = self.ipc_client.new_subscribe_to_topic()
            subscribe_op.activate(subscribe_request, on_stream_event=on_command)
            logger.info("Subscribed to 'bowl/command' topic for ad-hoc motor triggers.")
        except Exception as e:
            logger.error(f"Failed to subscribe for commands: {e}")

    def run(self):
        """Main loop that combines bowl state detection, motor dispensing, and command subscription."""
        logger.info("Starting combined BowlState and Hopper controller...")
        try:
            self.ipc_client = self.get_ipc_client()
            self.subscribe_for_commands()

            while True:
                try:
                    if self.ipc_client is None:
                        self.ipc_client = self.get_ipc_client()
                        self.subscribe_for_commands()
                    
                    is_empty, conf = self.is_bowl_empty()
                    logger.info(f"Bowl is {'empty' if is_empty else 'full'} with confidence {conf:.2f}")

                    # Publish the state update.
                    if not self.publish_state(is_empty, conf):
                        self.consecutive_failures += 1
                        logger.warning(f"Publishing failed {self.consecutive_failures} times consecutively")
                        if self.consecutive_failures >= self.MAX_CONSECUTIVE_FAILURES:
                            logger.warning("Too many consecutive publish failures; recreating IPC client...")
                            self.ipc_client = None
                            self.consecutive_failures = 0
                    else:
                        self.consecutive_failures = 0

                    # If in debug mode, force dispensing regardless of detection.
                    if DEBUG_MODE:
                        logger.info("DEBUG_MODE active: Forcing motor dispensing.")
                        self.dispense()
                    elif is_empty and conf > CONFIDENCE_THRESHOLD:
                        logger.info("Bowl detected as empty, initiating dispensing...")
                        self.dispense()

                    time.sleep(10)  # Adjust the loop delay as needed.
                except Exception as e:
                    logger.error(f"Error in main loop: {str(e)}")
                    logger.error(traceback.format_exc())
                    time.sleep(10)
        except KeyboardInterrupt:
            logger.info("Keyboard interrupt received. Exiting.")
        except Exception as e:
            logger.error(f"Fatal error: {str(e)}")
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
