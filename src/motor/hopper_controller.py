#!/usr/bin/env python3
import RPi.GPIO as GPIO
import time
import yaml
import os
import logging
import json
import awsiot.greengrasscoreipc
import awsiot.greengrasscoreipc.client as client
from awsiot.greengrasscoreipc.model import SubscribeToIoTCoreRequest, QOS

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger("HopperController")

class HopperController:
    def __init__(self):
        logger.info("Initializing HopperController...")
        self.load_config()
        self.setup_gpio()
        logger.info("HopperController initialization complete")

    def load_config(self):
        base_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "config")
        config_path = os.path.join(base_dir, "config.yaml")
        try:
            logger.info(f"Loading motor configuration from {config_path}")
            with open(config_path, "r") as f:
                config = yaml.safe_load(f)
                motor_config = config.get("hardware", {}).get("motor", {})
                self.step_pin = motor_config.get("step_pin", 16)
                self.dir_pin = motor_config.get("dir_pin", 15)
                self.en_pin = motor_config.get("en_pin", 18)
                logger.info(f"Motor configuration loaded: {motor_config}")
        except FileNotFoundError:
            logger.error(f"Configuration file not found at {config_path}. Using default pins.")
            self.step_pin, self.dir_pin, self.en_pin = 16, 15, 18
        except Exception as e:
            logger.exception(f"Error loading motor config: {e}")
            self.step_pin, self.dir_pin, self.en_pin = 16, 15, 18

    def setup_gpio(self):
        logger.info("Setting up GPIO pins...")
        GPIO.setmode(GPIO.BOARD)
        GPIO.setup([self.step_pin, self.dir_pin, self.en_pin], GPIO.OUT)
        GPIO.output(self.en_pin, GPIO.HIGH)
        logger.info("GPIO setup complete.")

    def enable_motor(self):
        logger.info("Enabling motor")
        GPIO.output(self.en_pin, GPIO.LOW)
        time.sleep(0.05)

    def disable_motor(self):
        logger.info("Disabling motor")
        GPIO.output(self.en_pin, GPIO.HIGH)

    def step(self, steps, rpm=30, steps_per_rev=200):
        logger.info(f"Stepping motor: {steps} steps at {rpm} RPM")
        delay = 60.0 / (rpm * steps_per_rev)
        for i in range(steps):
            GPIO.output(self.step_pin, GPIO.HIGH)
            time.sleep(delay)
            GPIO.output(self.step_pin, GPIO.LOW)
            time.sleep(delay)

    def dispense(self, portions=1):
        logger.info(f"Starting dispensing for {portions} portion(s)")
        try:
            self.enable_motor()
            steps_per_portion = 200
            for i in range(1, portions+1):
                logger.info(f"Dispensing portion {i}/{portions}")
                self.step(steps_per_portion)
                time.sleep(0.5)
            logger.info("Dispensing complete")
        except Exception as e:
            logger.exception(f"Error during dispensing: {e}")
        finally:
            self.disable_motor()

    def subscribe_to_bowl_state(self):
        try:
            ipc_client = awsiot.greengrasscoreipc.connect()
            subscribe_request = SubscribeToIoTCoreRequest(
                topic_name="bowl/state",
                qos=QOS.AT_LEAST_ONCE
            )
            # Create the subscription operation without arguments,
            # then pass the stream handler as the second argument to activate.
            operation = ipc_client.new_subscribe_to_iot_core()
            operation.activate(subscribe_request, self.handle_message)
            logger.info("Subscribed to 'bowl/state'")
            while True:
                time.sleep(1)
        except Exception as e:
            logger.error(f"Error subscribing to 'bowl/state': {e}")

    def handle_message(self, stream, payload):
        try:
            message = payload.decode() if isinstance(payload, bytes) else payload
            logger.info(f"Received message: {message}")
            data = json.loads(message)
            if data.get("empty") is True:
                logger.info("Bowl reported empty; triggering dispense.")
                self.dispense()
            else:
                logger.info("Bowl not empty; no action taken.")
        except Exception as e:
            logger.error(f"Error processing message: {e}")

    def cleanup(self):
        logger.info("Cleaning up GPIO and shutting down HopperController.")
        GPIO.cleanup()

if __name__ == "__main__":
    motor = HopperController()
    try:
        motor.subscribe_to_bowl_state()
    except KeyboardInterrupt:
        logger.info("Keyboard interrupt received. Exiting.")
    finally:
        motor.cleanup()
        logger.info("HopperController shutdown complete.")
