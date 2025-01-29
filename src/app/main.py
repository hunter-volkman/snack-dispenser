#!/usr/bin/env python3
import os
import sys
import time
import json
import logging
import threading
from concurrent.futures import ThreadPoolExecutor
import awsiot.greengrasscoreipc
from awsiot.greengrasscoreipc.model import (
    PublishToIoTCore,
    QOS
)

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from vision.predict import BowlStateDetector
from motor.control import MotorController

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

TIMEOUT = 10

class SnackBotComponent:
    def __init__(self):
        """Initialize the Snack Bot component."""
        self.ipc_client = awsiot.greengrasscoreipc.connect()
        
        # Initialize state tracking
        self.last_state = None
        self.last_dispense_time = 0
        self.min_dispense_interval = 30  # Minimum seconds between dispenses
        
        # Load component configuration
        self.check_interval = 2  # Reduced check interval for responsiveness
        self.confidence_threshold = 0.7  # Slightly lower threshold
        self.consecutive_empty_required = 2  # Require multiple empty detections
        self.consecutive_empty_count = 0
        
        # Initialize systems
        self._init_systems()
        
        # Control flags
        self.running = True
        self.is_dispensing = False
        
        # Set up signal handling
        signal.signal(signal.SIGTERM, self.stop)
        signal.signal(signal.SIGINT, self.stop)
    
    def _init_systems(self):
        """Initialize vision and motor systems with retry logic."""
        max_retries = 3
        retry_delay = 5
        
        for attempt in range(max_retries):
            try:
                self.detector = BowlStateDetector()
                self.motor = MotorController()
                logger.info("Systems initialized successfully")
                return
            except Exception as e:
                logger.error(f"Attempt {attempt + 1}/{max_retries} failed: {e}")
                if attempt < max_retries - 1:
                    logger.info(f"Retrying in {retry_delay} seconds...")
                    time.sleep(retry_delay)
                else:
                    raise
    
    def publish_state(self, is_empty, confidence):
        """Publish bowl state to IoT Core."""
        try:
            message = {
                "timestamp": int(time.time()),
                "is_empty": is_empty,
                "confidence": confidence,
                "consecutive_empty": self.consecutive_empty_count
            }
            
            request = PublishToIoTCore(
                topic="snackbot/bowlstate",
                qos=QOS.AT_LEAST_ONCE,
                payload=json.dumps(message).encode()
            )
            
            operation = self.ipc_client.new_publish_to_iot_core()
            operation.activate(request)
            future = operation.get_response()
            future.result(TIMEOUT)
            
        except Exception as e:
            logger.error(f"Error publishing message: {e}")
    
    def should_dispense(self, is_empty, confidence):
        """Determine if we should dispense based on current state and history."""
        current_time = time.time()
        
        # Don't dispense if we recently dispensed
        if current_time - self.last_dispense_time < self.min_dispense_interval:
            return False
        
        # Update consecutive empty count
        if is_empty and confidence > self.confidence_threshold:
            self.consecutive_empty_count += 1
        else:
            self.consecutive_empty_count = 0
        
        # Only dispense if we've seen multiple consecutive empty states
        return (self.consecutive_empty_count >= self.consecutive_empty_required)
    
    def dispense_snack(self):
        """Dispense a snack with improved error handling."""
        if self.is_dispensing:
            return
        
        try:
            self.is_dispensing = True
            logger.info("Starting dispense cycle")
            
            # Dispense
            self.motor.dispense()
            self.last_dispense_time = time.time()
            self.consecutive_empty_count = 0
            
            # Wait briefly then verify bowl state
            time.sleep(2)
            is_empty, confidence = self.detector.is_bowl_empty()
            
            if is_empty and confidence > self.confidence_threshold:
                logger.warning("Bowl still empty after dispensing!")
            else:
                logger.info("Dispense successful")
            
            # Publish updated state
            self.publish_state(is_empty, confidence)
            
        except Exception as e:
            logger.error(f"Error during dispensing: {e}")
        finally:
            self.is_dispensing = False
    
    def run(self):
        """Main component loop with improved error handling."""
        logger.info("Starting Snack Bot component...")
        
        with ThreadPoolExecutor(max_workers=2) as executor:
            while self.running:
                try:
                    # Check bowl state
                    is_empty, confidence = self.detector.is_bowl_empty()
                    
                    # Log state changes
                    if self.last_state != is_empty:
                        logger.info(f"Bowl state changed: {'empty' if is_empty else 'full'} "
                                  f"(confidence: {confidence:.2f})")
                        self.last_state = is_empty
                    
                    # Publish state
                    self.publish_state(is_empty, confidence)
                    
                    # Check if we should dispense
                    if self.should_dispense(is_empty, confidence):
                        executor.submit(self.dispense_snack)
                    
                    # Wait before next check
                    time.sleep(self.check_interval)
                
                except Exception as e:
                    logger.error(f"Error in main loop: {e}")
                    time.sleep(1)
    
    def stop(self, signum=None, frame=None):
        """Stop the component gracefully."""
        logger.info("Stopping Snack Bot component...")
        self.running = False
        if hasattr(self, 'detector'):
            self.detector.close()
        if hasattr(self, 'motor'):
            self.motor.cleanup()

def main():
    """Run the component with improved error handling."""
    max_retries = 3
    retry_delay = 5
    
    for attempt in range(max_retries):
        try:
            component = SnackBotComponent()
            component.run()
            break
        except Exception as e:
            logger.error(f"Component error (attempt {attempt + 1}/{max_retries}): {e}")
            if attempt < max_retries - 1:
                logger.info(f"Retrying in {retry_delay} seconds...")
                time.sleep(retry_delay)
            else:
                logger.error("Max retries reached, exiting...")
                raise

if __name__ == "__main__":
    main()