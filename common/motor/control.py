#!/usr/bin/env python3
import RPi.GPIO as GPIO
import time
import yaml
import os
import logging

# Configure logger with standardized logging level and formatting
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger("EdgeSnackDispenser.Motor")

class MotorController:
    def __init__(self):
        logger.info("Initializing MotorController...")
        self.load_config()
        self.setup_gpio()
        logger.info("MotorController initialization complete")

    def load_config(self):
        # Load motor settings from common/config/config.yaml
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
            logger.error(f"Configuration file not found at {config_path}. Using default pin settings.")
            self.step_pin, self.dir_pin, self.en_pin = 16, 15, 18
        except Exception as e:
            logger.exception(f"Failed to load motor config due to unexpected error: {e}")
            self.step_pin, self.dir_pin, self.en_pin = 16, 15, 18

    def setup_gpio(self):
        logger.info("Setting up GPIO pins...")
        GPIO.setmode(GPIO.BOARD)
        GPIO.setup([self.step_pin, self.dir_pin, self.en_pin], GPIO.OUT)
        GPIO.output(self.en_pin, GPIO.HIGH)  # Disable motor initially
        logger.info(f"GPIO setup complete with step_pin={self.step_pin}, dir_pin={self.dir_pin}, en_pin={self.en_pin}")

    def enable_motor(self):
        logger.info("Enabling motor")
        GPIO.output(self.en_pin, GPIO.LOW)
        time.sleep(0.05)  # Allow time for the driver to enable

    def disable_motor(self):
        logger.info("Disabling motor")
        GPIO.output(self.en_pin, GPIO.HIGH)

    def step(self, steps, rpm=30, steps_per_rev=200):
        """Perform a fixed number of steps at the given RPM."""
        logger.info(f"Stepping motor: {steps} steps at {rpm} RPM with {steps_per_rev} steps/rev")
        delay = 60.0 / (rpm * steps_per_rev)
        for step_num in range(steps):
            GPIO.output(self.step_pin, GPIO.HIGH)
            time.sleep(delay)
            GPIO.output(self.step_pin, GPIO.LOW)
            time.sleep(delay)
            if step_num % 10 == 0:
                logger.debug(f"Step {step_num}/{steps} complete")

    def dispense(self, portions=1):
        """Dispense a snack by rotating the motor a fixed amount."""
        logger.info(f"Starting dispensing process for {portions} portion(s)")
        try:
            self.enable_motor()
            steps_per_portion = 200  # Calibrate this value for your hardware
            for portion in range(portions):
                logger.info(f"Dispensing portion {portion + 1}/{portions}")
                self.step(steps_per_portion)
                time.sleep(0.5)  # Pause between portions if dispensing more than one
            logger.info("Dispensing process complete")
        except Exception as e:
            logger.exception(f"Error during dispensing: {e}")
        finally:
            self.disable_motor()

    def cleanup(self):
        logger.info("Cleaning up GPIO and shutting down MotorController")
        GPIO.cleanup()

if __name__ == "__main__":
    logger.info("Starting standalone motor control test")
    motor = MotorController()
    try:
        motor.dispense()
    except Exception as e:
        logger.exception(f"Unhandled exception during standalone motor test: {e}")
    finally:
        motor.cleanup()
        logger.info("Motor control test complete. Exiting.")
