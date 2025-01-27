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
        GPIO.output(self.ENABLE_PIN, GPIO.HIGH)
        print("Motor controller initialized (motor disabled)")
    
    def rotate_degrees(self, degrees, clockwise=True, rpm=60):
        # Calculate the delay per step based on the desired RPM
        # Delay in seconds per step
        delay = 60 / (200 * rpm)  

        # Calculate the number of steps for the given degrees
        steps = int((abs(degrees) / 360) * 200)
        print(f"Rotating {degrees}° ({steps} steps) at {rpm} RPM")

        # Enable motor before moving
        self.enable_motor(True)
        time.sleep(0.1)

        self.set_direction(clockwise)
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
        for i in range(steps):
            GPIO.output(self.STEP_PIN, GPIO.HIGH)
            time.sleep(delay)
            GPIO.output(self.STEP_PIN, GPIO.LOW)
            time.sleep(delay)
            if i % 50 == 0 and i != 0:
                print(f"Step {i}/{steps}")
    
    def cleanup(self):
        self.enable_motor(False)
        GPIO.cleanup()
        print("GPIO cleanup complete")

def main():
    parser = argparse.ArgumentParser(description='Test NEMA 17 stepper motor')
    parser.add_argument('--degrees', type=float, default=90, help='Degrees to rotate (default: 90°)')
    parser.add_argument('--clockwise', action='store_true', help='Rotate clockwise (default: counterclockwise)')
    parser.add_argument('--rpm', type=float, default=60, help='Motor speed in RPM (default: 60 RPM)')
    
    args = parser.parse_args()
    
    motor = NEMA17Controller()
    start_time = time.time()
    
    try:
        print("Starting motor test...")
        time.sleep(1)
        steps = motor.rotate_degrees(args.degrees, args.clockwise, args.rpm)
        elapsed_time = time.time() - start_time
        print("Motor Test Results:")
        print(f"degrees_rotated: {args.degrees}")
        print(f"direction: {'clockwise' if args.clockwise else 'counterclockwise'}")
        print(f"steps_taken: {steps}")
        print(f"rpm: {args.rpm}")
        print(f"elapsed_time: {elapsed_time:.2f} seconds")
    except KeyboardInterrupt:
        print("\nTest interrupted by user")
    finally:
        motor.cleanup()
