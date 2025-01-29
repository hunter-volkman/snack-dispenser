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
        """Initialize the camera."""
        self.camera = cv2.VideoCapture(self.camera_id)
        if not self.camera.isOpened():
            raise RuntimeError("Failed to open camera")
        
        # Set camera properties
        self.camera.set(cv2.CAP_PROP_FRAME_WIDTH, self.camera_width)
        self.camera.set(cv2.CAP_PROP_FRAME_HEIGHT, self.camera_height)
        self.camera.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        
        # Clear buffer
        for _ in range(5):
            self.camera.read()
    
    def preprocess_frame(self, frame):
        """Preprocess frame for model input."""
        try:
            # Resize to expected input size
            resized = cv2.resize(frame, self.image_size)
            # Convert to RGB (model was trained on RGB)
            rgb = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB)
            # Flatten for model input
            flattened = rgb.flatten().reshape(1, -1)
            return flattened
        except Exception as e:
            logger.error(f"Error in preprocessing: {e}")
            return None
    
    def predict_single_frame(self):
        """Capture and predict a single frame."""
        try:
            # Clear buffer frames
            for _ in range(2):
                self.camera.grab()
            
            ret, frame = self.camera.read()
            if not ret or frame is None:
                logger.error("Failed to capture frame")
                return None, 0.0
            
            processed = self.preprocess_frame(frame)
            if processed is None:
                return None, 0.0
            
            # Get model prediction
            prediction = self.model.predict_proba(processed)[0]
            is_empty = prediction[0] > 0.5
            confidence = max(prediction)
            
            return is_empty, confidence
            
        except Exception as e:
            logger.error(f"Error in prediction: {e}")
            return None, 0.0
    
    def is_bowl_empty(self):
        """
        Check if bowl is empty using multiple frames for robustness.
        Returns:
            tuple: (is_empty, confidence)
        """
        predictions = []
        confidences = []
        
        # Get multiple predictions
        for _ in range(self.frame_buffer_size):
            is_empty, confidence = self.predict_single_frame()
            if is_empty is not None:
                predictions.append(is_empty)
                confidences.append(confidence)
        
        if not predictions:
            return self.last_state or False, 0.0
        
        # Calculate current prediction
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
        if hasattr(self, 'camera'):
            self.camera.release()

def main():
    """Test the detector."""
    detector = BowlStateDetector()
    try:
        print("\nStarting bowl state detection. Press Ctrl+C to exit.")
        while True:
            is_empty, confidence = detector.is_bowl_empty()
            state = "empty" if is_empty else "full"
            logger.info(f"Bowl is {state} (confidence: {confidence:.2f})")
            
            user_input = input("\nCheck again? (y/n): ")
            if user_input.lower() != 'y':
                break
    except KeyboardInterrupt:
        print("\nStopping detection...")
    finally:
        detector.close()

if __name__ == "__main__":
    main()