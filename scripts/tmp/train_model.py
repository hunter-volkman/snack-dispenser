import tflite_runtime.interpreter as tflite
import numpy as np
import logging
from pathlib import Path
import cv2
from sklearn.model_selection import train_test_split
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class BowlStateTrainer:
    def __init__(self, data_path):
        """Initialize trainer with data path."""
        self.data_path = Path(data_path)
        self.input_shape = (224, 224, 3)
        self.batch_size = 32
        self.epochs = 20

    def prepare_dataset(self):
        """Load and prepare training data."""
        images = []
        labels = []

        # Load empty bowl images
        empty_path = self.data_path / 'training' / 'empty'
        for img_path in empty_path.glob('*.jpg'):
            img = self._load_and_preprocess_image(img_path)
            if img is not None:
                images.append(img)
                labels.append(0)  # 0 for empty

        # Load full bowl images
        full_path = self.data_path / 'training' / 'full'
        for img_path in full_path.glob('*.jpg'):
            img = self._load_and_preprocess_image(img_path)
            if img is not None:
                images.append(img)
                labels.append(1)  # 1 for full

        return np.array(images), np.array(labels)

    def _load_and_preprocess_image(self, image_path):
        """Load and preprocess single image."""
        try:
            img = cv2.imread(str(image_path))
            img = cv2.resize(img, self.input_shape[:2])
            img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            img = img.astype(np.float32) / 255.0
            return img
        except Exception as e:
            logger.error(f"Error loading {image_path}: {e}")
            return None

    def train(self):
        """Train a model using scikit-learn for simplicity on the Raspberry Pi."""
        # Prepare data
        X, y = self.prepare_dataset()
        X_train, X_val, y_train, y_val = train_test_split(
            X.reshape(len(X), -1), y, test_size=0.2, random_state=42
        )

        # Train a simple logistic regression model (for Pi compatibility)
        from sklearn.linear_model import LogisticRegression
        model = LogisticRegression(max_iter=500)
        model.fit(X_train, y_train)
        accuracy = model.score(X_val, y_val)
        logger.info(f"Validation accuracy: {accuracy:.4f}")

        return model

    def export_model(self, model, export_dir):
        """Export a model to a simple format for Raspberry Pi."""
        export_path = Path(export_dir)
        export_path.mkdir(parents=True, exist_ok=True)

        # Save model coefficients and intercepts
        model_path = export_path / 'model.npz'
        np.savez(model_path, coef=model.coef_, intercept=model.intercept_)

        logger.info(f"Model exported to {model_path}")
        return str(model_path)

def main():
    base_path = Path.home() / 'snack-bot/data'
    trainer = BowlStateTrainer(base_path)

    try:
        # Train model
        logger.info("Starting training...")
        model = trainer.train()

        # Export model
        export_dir = base_path / 'model'
        model_path = trainer.export_model(model, export_dir)

        logger.info(f"Training complete. Model exported to: {model_path}")

    except Exception as e:
        logger.error(f"Training failed: {e}")
        raise

if __name__ == "__main__":
    main()
