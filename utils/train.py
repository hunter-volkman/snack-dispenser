#!/usr/bin/env python3
"""
Training script for Edge Snack Dispenser vision system.
Trains a simple classifier to detect bowl state.
"""
import cv2
import numpy as np
import yaml
import joblib
from pathlib import Path
import logging
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class BowlStateTrainer:
    def __init__(self):
        """Initialize trainer with configuration."""
        # Get project root directory (2 levels up from this file)
        self.project_root = Path(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
        self.load_config()
        
        # Setup paths
        self.data_dir = self.project_root / 'data'
        self.model_dir = self.data_dir / 'model'
        self.model_dir.mkdir(parents=True, exist_ok=True)
    
    def load_config(self):
        """Load configuration from yaml."""
        config_path = self.project_root / 'config' / 'config.yaml'
        try:
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
            self.image_size = tuple(config['vision']['image_size'])
        except Exception as e:
            logger.error(f"Error loading config: {e}")
            self.image_size = (640, 480)  # Fallback default

    
    def load_dataset(self):
        """Load and prepare training data."""
        images = []
        labels = []
        
        # Load empty bowl images (label 0)
        empty_dir = self.data_dir / 'training' / 'empty'
        for img_path in empty_dir.glob('*.jpg'):
            img = cv2.imread(str(img_path))
            if img is not None:
                img = cv2.resize(img, self.image_size)
                img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
                images.append(img.flatten())
                labels.append(0)
        
        # Load full bowl images (label 1)
        full_dir = self.data_dir / 'training' / 'full'
        for img_path in full_dir.glob('*.jpg'):
            img = cv2.imread(str(img_path))
            if img is not None:
                img = cv2.resize(img, self.image_size)
                img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
                images.append(img.flatten())
                labels.append(1)
        
        return np.array(images), np.array(labels)
    
    def train(self):
        """Train the model."""
        logger.info("Loading dataset...")
        X, y = self.load_dataset()
        
        if len(X) == 0:
            raise ValueError("No training data found!")
        
        logger.info(f"Dataset loaded: {len(X)} images")
        
        # Train model
        from sklearn.model_selection import train_test_split
        from sklearn.linear_model import LogisticRegression
        
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.2, random_state=42
        )
        
        logger.info("Training model...")
        model = LogisticRegression(max_iter=1000)
        model.fit(X_train, y_train)
        
        # Evaluate
        train_score = model.score(X_train, y_train)
        test_score = model.score(X_test, y_test)
        
        logger.info(f"Training accuracy: {train_score:.4f}")
        logger.info(f"Testing accuracy: {test_score:.4f}")
        
        return model
    
    def save_model(self, model):
        """Save the trained model."""
        model_path = self.model_dir / 'bowl_state_model.joblib'
        joblib.dump(model, model_path)
        logger.info(f"Model saved to {model_path}")

def main():
    trainer = BowlStateTrainer()
    try:
        model = trainer.train()
        trainer.save_model(model)
        logger.info("Training completed successfully!")
    except Exception as e:
        logger.error(f"Training failed: {e}")
        raise

if __name__ == "__main__":
    main()