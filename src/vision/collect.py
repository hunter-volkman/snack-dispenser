#!/usr/bin/env python3
"""
Data collection script for Snack Bot vision system.
Captures and saves labeled images for training.
"""
import cv2
import time
import yaml
from pathlib import Path
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class DataCollector:
    def __init__(self):
        """Initialize data collector with configuration."""
        with open('config/config.yaml', 'r') as f:
            self.config = yaml.safe_load(f)
        
        self.data_dir = Path('data/training')
        self.camera = None
        self.image_size = tuple(self.config['vision']['image_size'])
    
    def setup_camera(self):
        """Initialize the camera."""
        self.camera = cv2.VideoCapture(self.config['hardware']['camera']['device_id'])
        if not self.camera.isOpened():
            raise RuntimeError("Failed to open camera")
        
        # Set resolution
        self.camera.set(cv2.CAP_PROP_FRAME_WIDTH, 
                       self.config['hardware']['camera']['resolution']['width'])
        self.camera.set(cv2.CAP_PROP_FRAME_HEIGHT, 
                       self.config['hardware']['camera']['resolution']['height'])
    
    def collect_samples(self, label, num_samples=20):
        """Collect labeled samples for training."""
        try:
            self.setup_camera()
            save_dir = self.data_dir / label
            save_dir.mkdir(parents=True, exist_ok=True)
            
            logger.info(f"Collecting {num_samples} samples for '{label}' state")
            logger.info("Press SPACE to capture, 'q' to quit")
            
            count = 0
            while count < num_samples:
                ret, frame = self.camera.read()
                if not ret:
                    continue
                
                # Show live preview
                cv2.imshow('Preview', frame)
                key = cv2.waitKey(1) & 0xFF
                
                if key == ord('q'):
                    break
                elif key == ord(' '):  # Space bar
                    # Save image
                    timestamp = time.strftime("%Y%m%d_%H%M%S")
                    filename = f"{label}_{timestamp}_{count:02d}.jpg"
                    save_path = save_dir / filename
                    
                    # Resize and save
                    resized = cv2.resize(frame, self.image_size)
                    cv2.imwrite(str(save_path), resized)
                    
                    count += 1
                    logger.info(f"Saved image {count}/{num_samples}: {filename}")
                    time.sleep(0.5)  # Prevent duplicate captures
        
        finally:
            if self.camera is not None:
                self.camera.release()
            cv2.destroyAllWindows()
    
    def verify_dataset(self):
        """Verify collected dataset."""
        stats = {'empty': 0, 'full': 0}
        
        for label in stats.keys():
            label_dir = self.data_dir / label
            if label_dir.exists():
                stats[label] = len(list(label_dir.glob('*.jpg')))
        
        logger.info("\nDataset Statistics:")
        for label, count in stats.items():
            logger.info(f"{label}: {count} images")
        
        return stats

def main():
    collector = DataCollector()
    
    # Collect samples for each class
    for label in ['empty', 'full']:
        input(f"\nPress Enter to start collecting '{label}' samples...")
        collector.collect_samples(label)
    
    # Verify dataset
    collector.verify_dataset()

if __name__ == "__main__":
    main()