import RPi.GPIO as GPIO
import time
import argparse

class NEMA17Controller:
    def __init__(self):
        self.DIR_PIN = 15
        self.STEP_PIN = 16
        self.ENABLE_PIN = 18
        
        GPIO.setmode(GPIO.BOARD)
        GPIO.setup([self.STEP_PIN, self.DIR_PIN, self.ENABLE_PIN], GPIO.OUT)
        
        # Start with motor disabled
        # HIGH = motor disabled
        GPIO.output(self.ENABLE_PIN, GPIO.HIGH)
        print("Motor controller initialized (motor disabled)")
    
    def rotate_degrees(self, degrees, clockwise=True, delay=0.005):
        # Calculate steps for given degrees
        steps = int((abs(degrees) / 360) * 200)
        print(f"Rotating {degrees}° ({steps} steps)")
        
        # Enable motor only before moving
        self.enable_motor(True)
        # Brief pause to stabilize motor
        time.sleep(0.1)
        
        self.set_direction(clockwise)
        # Brief pause after changing direction
        time.sleep(0.1)  
        
        self.step(steps, delay)
        
        # Disable motor after movement
        self.enable_motor(False)
   
    def enable_motor(self, enable=True):
        GPIO.output(self.ENABLE_PIN, GPIO.LOW if enable else GPIO.HIGH)
        print(f"Motor {'enabled' if enable else 'disabled'}")
   
    def set_direction(self, clockwise=True):
        GPIO.output(self.DIR_PIN, GPIO.HIGH if clockwise else GPIO.LOW)
        print(f"Direction set to {'clockwise' if clockwise else 'counterclockwise'}")
   
    def step(self, steps, delay=0.005):
        print(f"Starting {steps} steps...")
        for i in range(steps):
            GPIO.output(self.STEP_PIN, GPIO.HIGH)
            time.sleep(delay)
            GPIO.output(self.STEP_PIN, GPIO.LOW)
            time.sleep(delay)
            if i % 50 == 0:
                # Log progress every 50 steps
                print(f"Step {i}/{steps}")
    
    def cleanup(self):
        # Ensure motor is disabled on cleanup
        self.enable_motor(False)  
        GPIO.cleanup()
        print("GPIO cleanup complete")

def main():
    parser = argparse.ArgumentParser(description='Test NEMA 17 stepper motor')
    parser.add_argument('--degrees', type=float, default=90, help='Degrees to rotate (default: 90°)')
    parser.add_argument('--clockwise', action='store_true', help='Rotate clockwise (default: counterclockwise)')
    parser.add_argument('--speed', type=float, default=0.005, help='Delay between steps in seconds (default: 0.005)')
    
    args = parser.parse_args()
    
    motor = NEMA17Controller()
    
    try:
        print("Starting motor test...")
        # Wait before starting
        time.sleep(1)
        motor.rotate_degrees(args.degrees, args.clockwise, args.speed)
        print("Test complete")
    except KeyboardInterrupt:
        print("\nTest interrupted by user")
    finally:
        motor.cleanup()

if __name__ == "__main__":
    main()
