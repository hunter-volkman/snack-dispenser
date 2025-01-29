#!/usr/bin/env python3
"""
Bowl state detection for Snack Bot
Uses trained model to detect if bowl is empty or full.
If the bowl is predicted to be empty, rotate the motor 200 steps.
This script is intended to run once and exit (e.g. via cron).
"""

import cv2
import numpy as np
import joblib
import yaml
import logging
from pathlib import Path
import os
import time
import sys

# Import MotorController from your control.py
# Make sure "src" is recognized as a package (add __init__.py in src/).
# Then run: python -m src.vision.predict (from project root).
from src.motor.control import MotorController

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class BowlStateDetector:
    def __init__(self):
        """Initialize detector with configuration."""
        self.project_root = Path(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
        self.load_config()
        self.load_model()
        self.setup_camera()

        self.last_state = None
        self.state_confidence = 0.0
        self.consecutive_opposite_predictions = 0

    def load_model(self):
        """Load the trained model."""
        try:
            model_path = self.project_root / 'data' / 'model' / 'bowl_state_model.joblib'
            if not model_path.exists():
                raise FileNotFoundError(f"Model file not found at {model_path}")
            self.model = joblib.load(model_path)
            logger.info("Model loaded successfully")
        except Exception as e:
            logger.error(f"Error loading model: {e}")
            raise
    
    def load_config(self):
        """Load configuration from yaml."""
        config_path = self.project_root / 'config' / 'config.yaml'
        try:
            with open(config_path, 'r') as f:
                config = yaml.safe_load(f)
                self.image_size = tuple(config['vision']['image_size'])
                self.confidence_threshold = config['vision'].get('confidence_threshold', 0.7)
                self.camera_id = config['hardware']['camera']['device_id']
                self.camera_width = config['hardware']['camera']['resolution']['width']
                self.camera_height = config['hardware']['camera']['resolution']['height']
                self.required_consecutive_changes = config['vision'].get('required_consecutive_changes', 2)
                self.frame_buffer_size = config['vision'].get('frame_buffer_size', 3)
        except Exception as e:
            logger.error(f"Error loading config: {e}")
            # Default values if config fails
            self.image_size = (224, 224)
            self.confidence_threshold = 0.7
            self.camera_id = 0
            self.camera_width = 640
            self.camera_height = 480
            self.required_consecutive_changes = 2
            self.frame_buffer_size = 3
    
    def setup_camera(self):
        """Initialize the camera once."""
        self.camera = cv2.VideoCapture(self.camera_id)
        if not self.camera.isOpened():
            raise RuntimeError("Failed to open camera")
        
        # Set camera properties
        self.camera.set(cv2.CAP_PROP_FRAME_WIDTH, self.camera_width)
        self.camera.set(cv2.CAP_PROP_FRAME_HEIGHT, self.camera_height)
        self.camera.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        
        # (Optional) flush buffer at start
        self.flush_camera_buffer(num_frames=5)

    def flush_camera_buffer(self, num_frames=5):
        """
        Discard a certain number of frames from the camera buffer
        so the next read() is fresh.
        """
        for _ in range(num_frames):
            self.camera.grab()

    def preprocess_frame(self, frame):
        """Preprocess frame for model input."""
        try:
            resized = cv2.resize(frame, self.image_size)
            rgb = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB)
            flattened = rgb.flatten().reshape(1, -1)
            return flattened
        except Exception as e:
            logger.error(f"Error in preprocessing: {e}")
            return None
    
    def predict_single_frame(self):
        """Predict on a single frame (assumes camera already open)."""
        try:
            ret, frame = self.camera.read()
            if not ret or frame is None:
                logger.error("Failed to capture frame")
                return None, 0.0
            
            processed = self.preprocess_frame(frame)
            if processed is None:
                return None, 0.0
            
            # Predict probabilities
            prediction = self.model.predict_proba(processed)[0]
            # Assume prediction[0] is "empty" probability, prediction[1] is "full"
            is_empty = (prediction[0] > 0.5)
            confidence = max(prediction)
            
            return is_empty, confidence
        except Exception as e:
            logger.error(f"Error in prediction: {e}")
            return None, 0.0

    def is_bowl_empty(self):
        """
        Check if bowl is empty using multiple frames for robustness.
        Returns:
            (is_empty, confidence)
        """
        predictions = []
        confidences = []
        
        for _ in range(self.frame_buffer_size):
            is_empty, confidence = self.predict_single_frame()
            if is_empty is not None:
                predictions.append(is_empty)
                confidences.append(confidence)
        
        if not predictions:
            # If we failed to get any frames, fallback to last known state or default.
            return self.last_state or False, 0.0
        
        current_empty = sum(predictions) > len(predictions) / 2
        avg_confidence = sum(confidences) / len(confidences)
        
        # State transition logic
        if self.last_state is None:
            self.last_state = current_empty
            self.state_confidence = avg_confidence
            return current_empty, avg_confidence
        
        if current_empty != self.last_state:
            self.consecutive_opposite_predictions += 1
            if self.consecutive_opposite_predictions >= self.required_consecutive_changes:
                self.last_state = current_empty
                self.state_confidence = avg_confidence
                self.consecutive_opposite_predictions = 0
        else:
            self.consecutive_opposite_predictions = 0
        
        return self.last_state, self.state_confidence
    
    def close(self):
        """Release camera resources."""
        if hasattr(self, 'camera') and self.camera is not None:
            self.camera.release()

def main():
    """
    Run one detection cycle, rotate motor if bowl is EMPTY.
    Adjust your cron or systemd schedule to call this script.
    """
    detector = BowlStateDetector()
    motor = MotorController()  # Create a motor controller instance
    
    try:
        # Flush the buffer right before capturing new frames
        detector.flush_camera_buffer(num_frames=5)

        # Run inference
        is_empty, confidence = detector.is_bowl_empty()
        state = "empty" if is_empty else "full"
        logger.info(f"Bowl is {state} (confidence: {confidence:.2f})")

        # If the bowl is predicted to be EMPTY, rotate the motor 200 steps
        if is_empty:
            logger.info("Bowl is empty; rotating motor 200 steps...")
            motor.enable_motor()
            motor.step(200, rpm=30)
            motor.disable_motor()
        else:
            logger.info("Bowl is full; doing nothing with motor.")
    
    except KeyboardInterrupt:
        logger.info("Interrupted by user.")
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
    finally:
        # Clean up
        detector.close()
        motor.cleanup()

if __name__ == "__main__":
    main()
