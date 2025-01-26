import RPi.GPIO as GPIO
import time
import argparse

class NEMA17Controller:
    """Simple controller for NEMA 17 stepper motor with DRV8825 driver."""
    
    def __init__(self):
        # Pin Definitions
        self.STEP_PIN = 18
        self.DIR_PIN = 23
        self.ENABLE_PIN = 24
        
        # Setup GPIO
        GPIO.setmode(GPIO.BCM)
        GPIO.setup([self.STEP_PIN, self.DIR_PIN, self.ENABLE_PIN], GPIO.OUT)
        
        # Disable motor initially
        GPIO.output(self.ENABLE_PIN, GPIO.HIGH)
    
    def enable_motor(self, enable=True):
        """Enable or disable the motor (enable is active LOW)."""
        GPIO.output(self.ENABLE_PIN, not enable)
    
    def set_direction(self, clockwise=True):
        """Set motor direction."""
        GPIO.output(self.DIR_PIN, clockwise)
    
    def step(self, steps, delay=0.001):
        """Make a specific number of steps with given delay."""
        for _ in range(steps):
            GPIO.output(self.STEP_PIN, GPIO.HIGH)
            time.sleep(delay)
            GPIO.output(self.STEP_PIN, GPIO.LOW)
            time.sleep(delay)
    
    def rotate_degrees(self, degrees, clockwise=True, delay=0.001):
        """Rotate a specific number of degrees."""
        # NEMA 17 has 200 steps per revolution (1.8 degrees per step)
        steps = int((abs(degrees) / 360) * 200)
        self.set_direction(clockwise)
        self.step(steps, delay)
    
    def cleanup(self):
        """Cleanup GPIO resources."""
        # Disable motor
        self.enable_motor(False)  
        GPIO.cleanup()

def main():
    parser = argparse.ArgumentParser(description='Test NEMA 17 stepper motor')
    parser.add_argument('--degrees', type=float, default=360,
                      help='Degrees to rotate (default: 360)')
    parser.add_argument('--clockwise', action='store_true',
                      help='Rotate clockwise')
    parser.add_argument('--speed', type=float, default=0.001,
                      help='Step delay in seconds (default: 0.001)')
    
    args = parser.parse_args()
    
    motor = NEMA17Controller()
    
    try:
        print(f"Testing motor - {args.degrees}° {'clockwise' if args.clockwise else 'counterclockwise'}")
        motor.enable_motor(True)
        motor.rotate_degrees(args.degrees, args.clockwise, args.speed)
        print("Test complete")
        
    except KeyboardInterrupt:
        print("\nTest interrupted")
    finally:
        motor.cleanup()

if __name__ == "__main__":
    main()