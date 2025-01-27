#!/usr/bin/env python3
"""
Main Greengrass component application for Snack Bot
"""
import os
import sys
import time
import json
import logging
import threading
import signal
from concurrent.futures import ThreadPoolExecutor
import awsiot.greengrasscoreipc
from awsiot.greengrasscoreipc.model import (
    PublishToIoTCore,
    QOS
)

# Add the vision module to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from vision.predict import BowlStateDetector
from motor.control import MotorController

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TIMEOUT = 10

class SnackBotComponent:
    def __init__(self):
        """Initialize the Snack Bot component."""
        self.ipc_client = awsiot.greengrasscoreipc.connect()
        
        # Load component configuration
        self.check_interval = 5  # Default check interval
        self.confidence_threshold = 0.8  # Default confidence threshold
        self.load_configuration()
        
        # Initialize vision and motor systems
        self.detector = BowlStateDetector()
        self.motor = MotorController()
        
        # Control flags
        self.running = True
        self.is_dispensing = False
        
        # Set up signal handling
        signal.signal(signal.SIGTERM, self.stop)
        signal.signal(signal.SIGINT, self.stop)
    
    def load_configuration(self):
        """Load component configuration."""
        try:
            # In a real component, this would load from Greengrass configuration
            # For now, we'll use default values
            pass
        except Exception as e:
            logger.error(f"Error loading configuration: {e}")
    
    def publish_state(self, is_empty, confidence):
        """Publish bowl state to IoT Core."""
        try:
            message = {
                "timestamp": int(time.time()),
                "is_empty": is_empty,
                "confidence": confidence
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
    
    def dispense_snack(self):
        """Dispense a snack."""
        if self.is_dispensing:
            return
        
        try:
            self.is_dispensing = True
            self.motor.dispense()
            # Publish dispense event
            self.publish_state(False, 1.0)  # Bowl should be full after dispensing
        except Exception as e:
            logger.error(f"Error dispensing: {e}")
        finally:
            self.is_dispensing = False
    
    def run(self):
        """Main component loop."""
        logger.info("Starting Snack Bot component...")
        
        with ThreadPoolExecutor(max_workers=2) as executor:
            while self.running:
                try:
                    # Check bowl state
                    is_empty, confidence = self.detector.is_bowl_empty()
                    logger.info(f"Bowl state: {'empty' if is_empty else 'full'} "
                              f"(confidence: {confidence:.2f})")
                    
                    # Publish state
                    self.publish_state(is_empty, confidence)
                    
                    # Dispense if empty
                    if (is_empty and 
                        confidence > self.confidence_threshold and 
                        not self.is_dispensing):
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
    component = SnackBotComponent()
    try:
        component.run()
    except Exception as e:
        logger.error(f"Component error: {e}")
    finally:
        component.stop()

if __name__ == "__main__":
    main()