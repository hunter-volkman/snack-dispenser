#!/usr/bin/env python3
"""
Bowl state detection for Snack Bot
Uses trained model to detect if bowl is empty or full
"""
import cv2
import numpy as np
import joblib
import yaml
import logging
from pathlib import Path
import os
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class BowlStateDetector:
    def __init__(self):
        """Initialize detector with configuration."""
        # Get project root directory (2 levels up from this file)
        self.project_root = Path(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
        self.load_config()
        self.load_model()
        self.setup_camera()
    
    def load_config(self):
        """Load configuration from yaml."""
        config_path = self.project_root / 'config' / 'config.yaml'
        try:
            with open(config_path, 'r') as f:
                config = yaml.safe_load(f)
                self.image_size = tuple(config['vision']['image_size'])
                self.confidence_threshold = config['vision']['confidence_threshold']
                self.camera_id = config['hardware']['camera']['device_id']
        except Exception as e:
            logger.error(f"Error loading config: {e}")
            # Default values if config fails
            self.image_size = (224, 224)
            self.confidence_threshold = 0.8
            self.camera_id = 0
    
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
    
    def setup_camera(self):
        """Initialize the camera."""
        self.camera = cv2.VideoCapture(self.camera_id)
        if not self.camera.isOpened():
            raise RuntimeError("Failed to open camera")
        
        # Set camera properties
        self.camera.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
        self.camera.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
    
    def preprocess_frame(self, frame):
        """Preprocess frame for model input."""
        # Resize to expected input size
        resized = cv2.resize(frame, self.image_size)
        # Convert to RGB (model was trained on RGB)
        rgb = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB)
        # Flatten for model input
        flattened = rgb.flatten().reshape(1, -1)
        return flattened
    
    def predict_single_frame(self):
        """Capture and predict a single frame."""
        try:
            ret, frame = self.camera.read()
            if not ret:
                logger.error("Failed to capture frame")
                return None, 0.0
            
            # Preprocess the frame
            processed = self.preprocess_frame(frame)
            
            # Get model prediction
            prediction = self.model.predict_proba(processed)[0]
            is_empty = prediction[0] > 0.5
            confidence = max(prediction)
            
            return is_empty, confidence
            
        except Exception as e:
            logger.error(f"Error in prediction: {e}")
            return None, 0.0
    
    def is_bowl_empty(self, num_frames=3, delay=0.5):
        """
        Check if the bowl is empty using multiple frames for robustness.
        Args:
            num_frames: Number of frames to check
            delay: Delay (in seconds) between capturing frames
        Returns:
            tuple: (is_empty, confidence)
        """
        predictions = []
        confidences = []

        # Get multiple predictions
        for _ in range(num_frames):
            is_empty, confidence = self.predict_single_frame()
            if is_empty is not None:
                predictions.append(is_empty)
                confidences.append(confidence)
            time.sleep(delay)  # Add delay between frames

        if not predictions:
            return False, 0.0

        # Use majority voting for final prediction
        final_empty = sum(predictions) > len(predictions) / 2
        avg_confidence = sum(confidences) / len(confidences)

        # Only return empty if confidence threshold is met
        if final_empty and avg_confidence < self.confidence_threshold:
            final_empty = False

        return final_empty, avg_confidence
    
    def close(self):
        """Release camera resources."""
        if hasattr(self, 'camera'):
            self.camera.release()

def main():
    """Test the detector."""
    detector = BowlStateDetector()
    try:
        while True:
            is_empty, confidence = detector.is_bowl_empty()
            state = "empty" if is_empty else "full"
            logger.info(f"Bowl is {state} (confidence: {confidence:.2f})")
            
            user_input = input("\nCheck again? (y/n): ")
            if user_input.lower() != 'y':
                break
    finally:
        detector.close()

if __name__ == "__main__":
    main()