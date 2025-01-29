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
import argparse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class DataCollector:
    def __init__(self, config_path, storage_path):
        """Initialize data collector with configuration."""
        with open(config_path, 'r') as f:
            self.config = yaml.safe_load(f)
        
        self.data_dir = Path(storage_path)
        self.camera = None
        self.image_size = tuple(self.config['vision']['image_size'])
    
    def setup_camera(self):
        """Initialize the camera."""
        self.camera = cv2.VideoCapture(self.config['hardware']['camera']['device_id'])
        if not self.camera.isOpened():
            raise RuntimeError("Failed to open camera")
        
        # Set camera resolution from config
        cam_width = self.config['hardware']['camera']['resolution']['width']
        cam_height = self.config['hardware']['camera']['resolution']['height']
        self.camera.set(cv2.CAP_PROP_FRAME_WIDTH, cam_width)
        self.camera.set(cv2.CAP_PROP_FRAME_HEIGHT, cam_height)
    
    def collect_samples(self, label, num_samples):
        """Collect labeled samples for training."""
        try:
            self.setup_camera()
            save_dir = self.data_dir / label
            save_dir.mkdir(parents=True, exist_ok=True)
            
            logger.info(f"Collecting {num_samples} samples for '{label}' state")
            count = 0

            # Clear any buffered frames
            for _ in range(3):
                self.camera.read()

            while count < num_samples:
                ret, frame = self.camera.read()
                if not ret:
                    logger.warning("Failed to capture frame, retrying...")
                    continue
                
                # Resize to training size and save
                resized = cv2.resize(frame, self.image_size)
                timestamp = time.strftime("%Y%m%d_%H%M%S")
                filename = f"{label}_{timestamp}_{count:02d}.jpg"
                save_path = save_dir / filename
                cv2.imwrite(str(save_path), resized)
                
                count += 1
                logger.info(f"Saved image {count}/{num_samples}: {filename}")
                time.sleep(0.5)  # Prevent duplicate captures
            
        finally:
            if self.camera is not None:
                self.camera.release()
    
    def verify_dataset(self):
        """Verify collected dataset."""
        stats = {}
        corrupted = []
        
        for label_dir in self.data_dir.iterdir():
            if label_dir.is_dir():
                label = label_dir.name
                stats[label] = 0
                for image_path in label_dir.glob('*.jpg'):
                    try:
                        img = cv2.imread(str(image_path))
                        if img is None:
                            corrupted.append(image_path)
                        else:
                            h, w = img.shape[:2]
                            if (w, h) != self.image_size:
                                logger.warning(f"Wrong size for {image_path}: {w}x{h}, expected: {self.image_size}")
                            stats[label] += 1
                    except Exception as e:
                        corrupted.append(image_path)
        
        logger.info("\nDataset Statistics:")
        for label, count in stats.items():
            logger.info(f"{label}: {count} images")
        
        if corrupted:
            logger.warning(f"\nFound {len(corrupted)} corrupted images:")
            for path in corrupted:
                logger.warning(f"- {path}")
        
        return stats, corrupted

def main():
    parser = argparse.ArgumentParser(description='Collect training data for Snack Bot.')
    parser.add_argument('--config', default='config/config.yaml', help='Path to config file')
    parser.add_argument('--storage', default='data/training', help='Path to store training data')
    parser.add_argument('--label', help='Label for the data (e.g., "empty", "full")')
    parser.add_argument('--samples', type=int, default=20, help='Number of samples to collect')
    parser.add_argument('--verify', action='store_true', help='Verify collected dataset')
    
    args = parser.parse_args()
    
    collector = DataCollector(args.config, args.storage)
    
    if args.verify:
        collector.verify_dataset()
    elif args.label:
        collector.collect_samples(args.label, args.samples)
    else:
        logger.error("Please provide a label using --label or use --verify to verify the dataset.")

if __name__ == "__main__":
    main()