#!/usr/bin/env python3
import RPi.GPIO as GPIO
import time
import yaml
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("EdgeSnackDispenser.Motor")

class MotorController:
    def __init__(self):
        self.load_config()
        self.setup_gpio()

    def load_config(self):
        # Load motor settings from common/config/config.yaml
        base_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "config")
        config_path = os.path.join(base_dir, "config.yaml")
        try:
            with open(config_path, "r") as f:
                config = yaml.safe_load(f)
                motor_config = config.get("hardware", {}).get("motor", {})
                self.step_pin = motor_config.get("step_pin", 16)
                self.dir_pin = motor_config.get("dir_pin", 15)
                self.en_pin = motor_config.get("en_pin", 18)
        except Exception as e:
            logger.error(f"Failed to load motor config: {e}")
            # Use default values if config loading fails
            self.step_pin = 16
            self.dir_pin = 15
            self.en_pin = 18

    def setup_gpio(self):
        GPIO.setmode(GPIO.BOARD)
        GPIO.setup([self.step_pin, self.dir_pin, self.en_pin], GPIO.OUT)
        GPIO.output(self.en_pin, GPIO.HIGH)  # Disable motor initially

    def enable_motor(self):
        GPIO.output(self.en_pin, GPIO.LOW)
        time.sleep(0.05)  # Allow time for the driver to enable

    def disable_motor(self):
        GPIO.output(self.en_pin, GPIO.HIGH)

    def step(self, steps, rpm=30, steps_per_rev=200):
        """Perform a fixed number of steps at the given RPM."""
        delay = 60.0 / (rpm * steps_per_rev)
        for _ in range(steps):
            GPIO.output(self.step_pin, GPIO.HIGH)
            time.sleep(delay)
            GPIO.output(self.step_pin, GPIO.LOW)
            time.sleep(delay)

    def dispense(self, portions=1):
        """Dispense a snack by rotating the motor a fixed amount."""
        try:
            self.enable_motor()
            steps_per_portion = 200  # Calibrate this value for your hardware
            for _ in range(portions):
                self.step(steps_per_portion)
                time.sleep(0.5)  # Pause between portions if dispensing more than one
            logger.info("Dispensing complete")
        except Exception as e:
            logger.error(f"Error during dispensing: {e}")
        finally:
            self.disable_motor()

    def cleanup(self):
        GPIO.cleanup()

if __name__ == "__main__":
    # Standalone test for motor control
    motor = MotorController()
    motor.dispense()
    motor.cleanup()
