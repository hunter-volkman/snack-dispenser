import cv2
import time
import os
import logging
from pathlib import Path
import argparse
import sys
import select

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class DataCollector:
    def __init__(self, storage_path):
        """Initialize data collector."""
        self.storage_path = Path(storage_path)
        self.camera = None
        
    def initialize_camera(self):
        """Initialize and test camera."""
        logger.info("Initializing camera...")
        self.camera = cv2.VideoCapture(0)
        if not self.camera.isOpened():
            raise RuntimeError("Cannot open camera")
            
        # Test frame capture
        ret, frame = self.camera.read()
        if not ret:
            raise RuntimeError("Cannot read frame")
            
        logger.info("Camera initialized successfully")
    
    def collect_samples(self, label, num_samples=50):
        """Collect labeled images."""
        try:
            self.initialize_camera()
            save_dir = self.storage_path / 'training' / label
            save_dir.mkdir(parents=True, exist_ok=True)
            
            collected = 0
            logger.info(f"Starting collection for '{label}' state")
            logger.info("Press Enter to capture, 'q' + Enter to quit")
            
            while collected < num_samples:
                ret, frame = self.camera.read()
                if not ret:
                    logger.warning("Failed to capture frame, retrying...")
                    continue
                
                # Check for input (non-blocking)
                if sys.stdin in select.select([sys.stdin], [], [], 0)[0]:
                    line = sys.stdin.readline().strip()
                    if line.lower() == 'q':
                        break
                    elif line == '':  # Enter was pressed
                        # Save image
                        timestamp = time.strftime("%Y%m%d_%H%M%S")
                        filename = f"{label}_{timestamp}_{collected}.jpg"
                        save_path = save_dir / filename
                        cv2.imwrite(str(save_path), frame)
                        collected += 1
                        logger.info(f"Saved image {collected}/{num_samples}")
                        # Save a preview of the last capture
                        preview_path = self.storage_path / 'preview.jpg'
                        cv2.imwrite(str(preview_path), frame)
                        logger.info(f"Preview saved to {preview_path}")
                        time.sleep(0.5)  # Prevent duplicate captures
                
                # Small delay to prevent CPU overuse
                time.sleep(0.1)
                
        except Exception as e:
            logger.error(f"Error during collection: {e}")
            raise
        finally:
            if self.camera is not None:
                self.camera.release()
    
    def verify_dataset(self):
        """Verify collected dataset."""
        dataset_info = {'empty': 0, 'full': 0}
        corrupted = []
        
        for label in dataset_info.keys():
            label_dir = self.storage_path / 'training' / label
            if not label_dir.exists():
                continue
            
            for image_path in label_dir.glob('*.jpg'):
                try:
                    img = cv2.imread(str(image_path))
                    if img is None:
                        corrupted.append(image_path)
                    else:
                        dataset_info[label] += 1
                except Exception as e:
                    corrupted.append(image_path)
        
        logger.info("\nDataset Statistics:")
        for label, count in dataset_info.items():
            logger.info(f"{label}: {count} images")
        
        if corrupted:
            logger.warning(f"\nFound {len(corrupted)} corrupted images:")
            for path in corrupted:
                logger.warning(f"- {path}")
        
        return dataset_info, corrupted

def main():
    parser = argparse.ArgumentParser(description='Collect training data')
    parser.add_argument('--label', choices=['empty', 'full'], help='Bowl state label')
    parser.add_argument('--samples', type=int, default=50, help='Number of samples')
    parser.add_argument('--verify', action='store_true', help='Verify dataset')
    
    args = parser.parse_args()
    
    storage_path = Path.home() / 'snack-bot/data'
    collector = DataCollector(storage_path)
    
    if args.verify:
        collector.verify_dataset()
    elif args.label:
        collector.collect_samples(args.label, args.samples)

if __name__ == "__main__":
    main()