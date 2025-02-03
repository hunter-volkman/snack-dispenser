#!/usr/bin/env python3
"""
Verify trained model for Edge Snack Dispenser vision system.
Tests both sample images and live camera feed.
"""
import cv2
import numpy as np
import joblib
import time
import logging
import argparse
import os
import yaml
from pathlib import Path
from tabulate import tabulate

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ModelVerifier:
    def __init__(self):
        """Initialize verifier with project configuration."""
        self.project_root = Path(__file__).parent.parent.parent
        
        # Load configuration
        config_path = self.project_root / 'config' / 'config.yaml'
        try:
            with open(config_path, 'r') as f:
                self.config = yaml.safe_load(f)
        except Exception as e:
            logger.error(f"Error loading config: {e}")
            raise

        self.model_path = self.project_root / 'data/model/bowl_state_model.joblib'
        self.data_path = self.project_root / 'data/training'
        self.image_size = tuple(self.config['vision']['image_size'])
        
        logger.info(f"Using image size: {self.image_size}")
        self.load_model()
    
    def load_model(self):
        """Load the trained model."""
        if not self.model_path.exists():
            raise FileNotFoundError(f"Model not found at {self.model_path}")
        self.model = joblib.load(self.model_path)
        logger.info("Model loaded successfully")
    
    def preprocess_image(self, image):
        """Preprocess image for inference."""
        resized = cv2.resize(image, self.image_size)
        rgb = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB)
        return rgb.reshape(1, -1)
    
    def predict(self, image):
        """Run prediction with timing."""
        start_time = time.time()
        processed = self.preprocess_image(image)
        prediction = self.model.predict_proba(processed)[0]
        inference_time = time.time() - start_time
        
        is_empty = prediction[0] > 0.5
        confidence = prediction[0] if is_empty else 1 - prediction[0]
        
        return is_empty, confidence, inference_time
    
    def test_sample_images(self):
        """Test model with saved training images."""
        results = []
        
        for state in ['empty', 'full']:
            image_dir = self.data_path / state
            if not image_dir.exists():
                logger.warning(f"No {state} images found in {image_dir}")
                continue
            
            # Test first 5 images of each class
            for img_path in list(image_dir.glob('*.jpg'))[:5]:
                image = cv2.imread(str(img_path))
                if image is None:
                    continue
                
                is_empty, confidence, inference_time = self.predict(image)
                results.append({
                    'image': img_path.name,
                    'expected': state == 'empty',
                    'predicted': is_empty,
                    'confidence': confidence,
                    'time_ms': inference_time * 1000
                })
        
        return results
    
    def test_live(self, num_tests=5):
        """Test model with live camera feed."""
        results = []
        cap = cv2.VideoCapture(0)
        
        if not cap.isOpened():
            raise RuntimeError("Failed to open camera")
        
        try:
            for i in range(num_tests):
                # Clear buffer
                for _ in range(3):
                    cap.read()
                
                ret, frame = cap.read()
                if not ret:
                    logger.error("Failed to capture frame")
                    continue
                
                # Run prediction
                is_empty, confidence, inference_time = self.predict(frame)
                state = "empty" if is_empty else "full"
                logger.info(f"Test {i+1}: Predicted {state} (confidence: {confidence:.2f})")
                
                results.append({
                    'image': f'live_{i}',
                    'predicted': is_empty,
                    'confidence': confidence,
                    'time_ms': inference_time * 1000
                })
                
                time.sleep(1)  # Wait between captures
                
        finally:
            cap.release()
        
        return results
    
    def print_results(self, results):
        """Print verification results in a formatted table."""
        if not results:
            logger.error("No results to display")
            return
        
        # Calculate statistics
        if 'expected' in results[0]:
            correct = sum(1 for r in results if r['expected'] == r['predicted'])
            accuracy = correct / len(results) * 100
            logger.info(f"Accuracy: {accuracy:.1f}%")
        
        avg_time = sum(r['time_ms'] for r in results) / len(results)
        avg_conf = sum(r['confidence'] for r in results) / len(results)
        
        logger.info(f"Average inference time: {avg_time:.1f}ms")
        logger.info(f"Average confidence: {avg_conf:.2f}")
        
        # Create table
        table_data = []
        for r in results:
            row = [
                r['image'],
                'Empty' if r['predicted'] else 'Full',
                f"{r['confidence']:.2f}",
                f"{r['time_ms']:.1f}ms"
            ]
            if 'expected' in r:
                row.insert(1, 'Empty' if r['expected'] else 'Full')
            table_data.append(row)
        
        headers = ['Image', 'Predicted', 'Confidence', 'Time']
        if 'expected' in results[0]:
            headers.insert(1, 'Expected')
        
        print('\n' + tabulate(table_data, headers=headers, tablefmt='grid'))

def main():
    parser = argparse.ArgumentParser(description='Verify Edge Snack Dispenser vision model')
    parser.add_argument('--live', action='store_true', help='Run live camera tests')
    parser.add_argument('--num-tests', type=int, default=5, 
                       help='Number of live tests to run')
    args = parser.parse_args()
    
    try:
        verifier = ModelVerifier()
        results = verifier.test_live(args.num_tests) if args.live \
                 else verifier.test_sample_images()
        verifier.print_results(results)
        
    except Exception as e:
        logger.error(f"Verification failed: {e}")
        raise

if __name__ == "__main__":
    main()