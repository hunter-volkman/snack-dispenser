#!/usr/bin/env python3
"""
Motor control for Snack Bot
Handles stepper motor control for snack dispensing
"""
import RPi.GPIO as GPIO
import time
import yaml
import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class MotorController:
    def __init__(self):
        """Initialize motor controller with configuration."""
        self.load_config()
        self.setup_gpio()
    
    def load_config(self):
        """Load configuration from yaml."""
        try:
            with open('~/snack-bot/config/config.yaml', 'r') as f:
                config = yaml.safe_load(f)
                self.step_pin = config['hardware']['motor']['step_pin']
                self.dir_pin = config['hardware']['motor']['dir_pin']
                self.en_pin = config['hardware']['motor']['en_pin']
        except Exception as e:
            logger.error(f"Error loading config: {e}")
            # Default values if config fails
            self.dir_pin = 15 
            self.step_pin = 16
            self.en_pin = 18  
    
    def setup_gpio(self):
        """Set up GPIO pins."""
        GPIO.setmode(GPIO.BOARD)
        GPIO.setup([self.step_pin, self.dir_pin, self.en_pin], GPIO.OUT)
        
        # Initialize pins
        GPIO.output(self.en_pin, GPIO.HIGH)  # Motor disabled
        GPIO.output(self.dir_pin, GPIO.HIGH)  # Set direction
        GPIO.output(self.step_pin, GPIO.LOW)
    
    def enable_motor(self):
        """Enable motor driver."""
        GPIO.output(self.en_pin, GPIO.LOW)
        time.sleep(0.05)  # Wait for driver to enable
    
    def disable_motor(self):
        """Disable motor driver."""
        GPIO.output(self.en_pin, GPIO.HIGH)
    
    def step(self, steps, delay=0.005):
        """
        Perform specified number of steps.
        Args:
            steps: Number of steps to move
            delay: Delay between steps (seconds)
        """
        for _ in range(steps):
            GPIO.output(self.step_pin, GPIO.HIGH)
            time.sleep(delay)
            GPIO.output(self.step_pin, GPIO.LOW)
            time.sleep(delay)
    
    def dispense(self, amount=1):
        """
        Dispense snacks.
        Args:
            amount: Number of portions to dispense
        """
        try:
            logger.info(f"Dispensing {amount} portion(s)...")
            self.enable_motor()
            
            # Perform dispensing movement
            # These values should be calibrated for your specific setup
            steps_per_portion = 200  # One full rotation
            
            for _ in range(amount):
                self.step(steps_per_portion)
                time.sleep(0.5)  # Wait between portions
            
            logger.info("Dispensing complete")
            
        except Exception as e:
            logger.error(f"Error during dispensing: {e}")
        finally:
            self.disable_motor()
    
    def cleanup(self):
        """Clean up GPIO resources."""
        self.disable_motor()
        GPIO.cleanup()

def main():
    """Test the motor controller."""
    controller = MotorController()
    try:
        while True:
            user_input = input("\nDispense snack? (y/n): ")
            if user_input.lower() != 'y':
                break
                
            controller.dispense()
            
    except KeyboardInterrupt:
        print("\nStopping motor test")
    finally:
        controller.cleanup()

if __name__ == "__main__":
    main()