import numpy as np
import cv2
import logging
from pathlib import Path
import time
import argparse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ModelVerifier:
    def __init__(self, model_path):
        """Initialize verifier with model path."""
        self.model_path = Path(model_path)
        self.input_shape = (224, 224, 3)
        self.load_model()
    
    def load_model(self):
        """Load the trained model."""
        model_data = np.load(self.model_path)
        self.coef = model_data['coef']
        self.intercept = model_data['intercept']
        logger.info("Model loaded successfully")
    
    def preprocess_image(self, image):
        """Preprocess image for inference."""
        img = cv2.resize(image, self.input_shape[:2])
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        img = img.astype(np.float32) / 255.0
        # Flatten the image for logistic regression
        return img.reshape(1, -1)
    
    def run_inference(self, image):
        """Run inference on image."""
        processed_image = self.preprocess_image(image)
        
        start_time = time.time()
        # Logistic regression prediction
        score = np.dot(processed_image, self.coef.T) + self.intercept
        probability = 1 / (1 + np.exp(-score))
        inference_time = time.time() - start_time
        
        return float(probability[0]), inference_time
    
    def verify_with_sample_images(self):
        """Test model with sample images."""
        results = []
        base_path = Path.home() / 'snack-bot/data'
        
        # Test empty bowl images
        empty_path = base_path / 'training' / 'empty'
        for img_path in list(empty_path.glob('*.jpg'))[:5]:
            image = cv2.imread(str(img_path))
            if image is not None:
                confidence, inference_time = self.run_inference(image)
                results.append({
                    'image': img_path.name,
                    'expected': 'empty',
                    'confidence': confidence,
                    'inference_time': inference_time
                })
        
        # Test full bowl images
        full_path = base_path / 'training' / 'full'
        for img_path in list(full_path.glob('*.jpg'))[:5]:
            image = cv2.imread(str(img_path))
            if image is not None:
                confidence, inference_time = self.run_inference(image)
                results.append({
                    'image': img_path.name,
                    'expected': 'full',
                    'confidence': confidence,
                    'inference_time': inference_time
                })
        
        return results
    
    def verify_live(self, num_tests=5):
        """Test model with live camera."""
        results = []
        cap = cv2.VideoCapture(0)
        
        try:
            for i in range(num_tests):
                ret, frame = cap.read()
                if not ret:
                    logger.error("Failed to capture frame")
                    continue
                
                confidence, inference_time = self.run_inference(frame)
                
                # Save test image
                timestamp = time.strftime("%Y%m%d_%H%M%S")
                save_path = Path.home() / 'snack-bot/data/temp' / f"test_{timestamp}.jpg"
                save_path.parent.mkdir(parents=True, exist_ok=True)
                cv2.imwrite(str(save_path), frame)
                
                state = "empty" if confidence > 0.5 else "full"
                results.append({
                    'image': str(save_path),
                    'state': state,
                    'confidence': confidence,
                    'inference_time': inference_time
                })
                
                logger.info(f"Test {i+1}: {state} ({confidence:.2f}) in {inference_time*1000:.1f}ms")
                time.sleep(1)  # Wait between captures
                
        finally:
            cap.release()
        
        return results
    
    def print_results(self, results):
        """Print verification results."""
        logger.info("\nVerification Results:")
        
        total_time = sum(r['inference_time'] for r in results)
        avg_time = total_time / len(results)
        
        logger.info(f"\nAverage inference time: {avg_time*1000:.1f}ms")
        logger.info(f"Number of tests: {len(results)}")
        
        for r in results:
            if 'expected' in r:
                logger.info(
                    f"\nImage: {r['image']}\n"
                    f"Expected: {r['expected']}\n"
                    f"Confidence: {r['confidence']:.2f}\n"
                    f"Inference time: {r['inference_time']*1000:.1f}ms"
                )
            else:
                logger.info(
                    f"\nImage: {r['image']}\n"
                    f"Detected state: {r['state']}\n"
                    f"Confidence: {r['confidence']:.2f}\n"
                    f"Inference time: {r['inference_time']*1000:.1f}ms"
                )

def main():
    parser = argparse.ArgumentParser(description='Verify trained model')
    parser.add_argument('--live', action='store_true', help='Run live camera tests')
    parser.add_argument('--num-tests', type=int, default=5, help='Number of live tests')
    
    args = parser.parse_args()
    
    model_path = str(Path.home() / 'snack-bot/data/model/model.npz')
    verifier = ModelVerifier(model_path)
    
    try:
        if args.live:
            results = verifier.verify_live(args.num_tests)
        else:
            results = verifier.verify_with_sample_images()
        
        verifier.print_results(results)
        
    except Exception as e:
        logger.error(f"Verification failed: {e}")
        raise

if __name__ == "__main__":
    main()