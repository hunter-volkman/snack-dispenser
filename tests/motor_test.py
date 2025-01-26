import RPi.GPIO as GPIO
import time
import argparse

class NEMA17Controller:
   def __init__(self):
       self.STEP_PIN = 18
       self.DIR_PIN = 23 
       self.ENABLE_PIN = 24
       
       GPIO.setmode(GPIO.BCM)
       GPIO.setup([self.STEP_PIN, self.DIR_PIN, self.ENABLE_PIN], GPIO.OUT)
       
       # Enable motor initially for testing
       GPIO.output(self.ENABLE_PIN, GPIO.LOW)
       print("Motor enabled")
   
   def enable_motor(self, enable=True):
       GPIO.output(self.ENABLE_PIN, not enable)
       print(f"Motor {'enabled' if enable else 'disabled'}")
   
   def set_direction(self, clockwise=True):
       GPIO.output(self.DIR_PIN, clockwise)
       print(f"Direction set to {'clockwise' if clockwise else 'counterclockwise'}")
   
   def step(self, steps, delay=0.005):  # Increased default delay
       print(f"Starting {steps} steps...")
       for i in range(steps):
           GPIO.output(self.STEP_PIN, GPIO.HIGH)
           time.sleep(delay)
           GPIO.output(self.STEP_PIN, GPIO.LOW)
           time.sleep(delay)
           if i % 50 == 0:
               print(f"Step {i}/{steps}")
   
   def rotate_degrees(self, degrees, clockwise=True, delay=0.005):
       steps = int((abs(degrees) / 360) * 200)
       print(f"Rotating {degrees}° ({steps} steps)")
       self.set_direction(clockwise)
       time.sleep(0.5)  # Wait for direction change
       self.step(steps, delay)
   
   def cleanup(self):
       self.enable_motor(False)
       GPIO.cleanup()
       print("Cleanup complete")

def main():
   parser = argparse.ArgumentParser(description='Test NEMA 17 stepper motor')
   parser.add_argument('--degrees', type=float, default=90)  # Changed default to 90
   parser.add_argument('--clockwise', action='store_true')
   parser.add_argument('--speed', type=float, default=0.005)  # Increased default speed
   
   args = parser.parse_args()
   
   motor = NEMA17Controller()
   
   try:
       print("Starting motor test...")
       time.sleep(1)  # Wait for enable
       motor.rotate_degrees(args.degrees, args.clockwise, args.speed)
       print("Test complete")
       
   except KeyboardInterrupt:
       print("\nTest interrupted")
   finally:
       motor.cleanup()

if __name__ == "__main__":
   main()