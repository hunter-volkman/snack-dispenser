#!/usr/bin/env python3
import time
import json
import logging
import signal
import sys
import os

import awsiot.greengrasscoreipc
from awsiot.greengrasscoreipc.model import PublishMessage, QOS


# Add the common directory to sys.path so we can import shared modules
base_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "common")
if base_dir not in sys.path:
    sys.path.insert(0, base_dir)

from vision.predict import BowlStateDetector
from motor.control import MotorController

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("EdgeSnackDispenser")

# Global flag for graceful shutdown
running = True
def signal_handler(signum, frame):
    global running
    logger.info("Signal received, shutting down...")
    running = False

signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

def publish_state(ipc_client, state, confidence):
    """Publish the current bowl state to AWS IoT Core via Greengrass IPC."""
    message = {
        "timestamp": int(time.time()),
        "bowl_empty": state,
        "confidence": confidence
    }
    try:
        request = PublishMessage(
            topic="edgesnackdispenser/bowlstate",
            qos=QOS.AT_LEAST_ONCE,
            payload=json.dumps(message).encode()
        )
        operation = ipc_client.new_publish_to_iot_core()
        operation.activate(request)
        operation.get_response().result(10)
        logger.info("Published state to IoT Core")
    except Exception as e:
        logger.error(f"Failed to publish state: {e}")

def main():
    ipc_client = awsiot.greengrasscoreipc.connect()
    detector = BowlStateDetector()
    motor = MotorController()

    # Settings (in seconds)
    check_interval = 5
    min_dispense_interval = 30
    last_dispense_time = 0

    logger.info("Starting Edge Snack Dispenser component...")

    while running:
        try:
            is_empty, confidence = detector.is_bowl_empty()
            logger.info(f"Bowl state: {'empty' if is_empty else 'full'} (confidence: {confidence:.2f})")
            publish_state(ipc_client, is_empty, confidence)

            # If the bowl is empty and confidence is high enough, dispense a snack
            if is_empty and confidence >= detector.confidence_threshold:
                if time.time() - last_dispense_time >= min_dispense_interval:
                    logger.info("Dispensing snack...")
                    motor.dispense()
                    last_dispense_time = time.time()
                else:
                    logger.info("Skipping dispense due to cooldown interval.")
            time.sleep(check_interval)
        except Exception as e:
            logger.error(f"Error in main loop: {e}")
            time.sleep(1)

    detector.close()
    motor.cleanup()
    logger.info("Edge Snack Dispenser component stopped.")

if __name__ == "__main__":
    main()
