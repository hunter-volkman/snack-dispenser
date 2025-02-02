#!/usr/bin/env python3
import cv2
import numpy as np
import joblib
import yaml
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("EdgeSnackDispenser.Vision")

class BowlStateDetector:
    def __init__(self):
        self.load_config()
        self.load_model()
        self.setup_camera()

    def load_config(self):
        # Load vision and camera settings from common/config/config.yaml
        base_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "config")
        config_path = os.path.join(base_dir, "config.yaml")
        try:
            with open(config_path, "r") as f:
                config = yaml.safe_load(f)
                vision_config = config.get("vision", {})
                self.image_size = tuple(vision_config.get("image_size", [224, 224]))
                self.confidence_threshold = vision_config.get("confidence_threshold", 0.7)
                camera_config = config.get("hardware", {}).get("camera", {})
                self.camera_id = camera_config.get("device_id", 0)
                self.camera_width = camera_config.get("resolution", {}).get("width", 640)
                self.camera_height = camera_config.get("resolution", {}).get("height", 480)
        except Exception as e:
            logger.error(f"Error loading vision config: {e}")
            self.image_size = (224, 224)
            self.confidence_threshold = 0.7
            self.camera_id = 0
            self.camera_width = 640
            self.camera_height = 480

    def load_model(self):
        # Load the pre-trained model from data/model/bowl_state_model.joblib
        base_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
        model_path = os.path.join(base_dir, "data", "model", "bowl_state_model.joblib")
        try:
            self.model = joblib.load(model_path)
            logger.info("Model loaded successfully")
        except Exception as e:
            logger.error(f"Failed to load model: {e}")
            raise

    def setup_camera(self):
        self.camera = cv2.VideoCapture(self.camera_id)
        if not self.camera.isOpened():
            raise RuntimeError("Failed to open camera")
        self.camera.set(cv2.CAP_PROP_FRAME_WIDTH, self.camera_width)
        self.camera.set(cv2.CAP_PROP_FRAME_HEIGHT, self.camera_height)
        # Flush a few initial frames for a fresh capture
        for _ in range(3):
            self.camera.grab()

    def preprocess_frame(self, frame):
        resized = cv2.resize(frame, self.image_size)
        rgb = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB)
        flattened = rgb.flatten().reshape(1, -1)
        return flattened

    def is_bowl_empty(self):
        """Capture one frame, process it, and run inference."""
        ret, frame = self.camera.read()
        if not ret:
            logger.error("Failed to capture frame")
            return False, 0.0
        processed = self.preprocess_frame(frame)
        prediction = self.model.predict_proba(processed)[0]
        # Assume prediction[0] is probability for "empty" and prediction[1] for "full"
        is_empty = prediction[0] > 0.5
        confidence = max(prediction)
        return is_empty, confidence

    def close(self):
        if self.camera:
            self.camera.release()

if __name__ == "__main__":
    detector = BowlStateDetector()
    state, conf = detector.is_bowl_empty()
    print(f"Bowl is {'empty' if state else 'full'} with confidence {conf:.2f}")
    detector.close()
