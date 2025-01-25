import RPi.GPIO as GPIO
import time

class MotorTester:
    def __init__(self, motor_type="NEMA17"):
        self.motor_type = motor_type
        GPIO.setmode(GPIO.BCM)
        
        if motor_type == "NEMA17":
            self.setup_nema17()
        else:
            self.setup_28byj48()
    
    def setup_nema17(self):
        self.STEP_PIN = 18
        self.DIR_PIN = 23
        self.ENABLE_PIN = 24
        GPIO.setup(self.STEP_PIN, GPIO.OUT)
        GPIO.setup(self.DIR_PIN, GPIO.OUT)
        GPIO.setup(self.ENABLE_PIN, GPIO.OUT)
    
    def setup_28byj48(self):
        self.PINS = [17, 18, 27, 22]
        for pin in self.PINS:
            GPIO.setup(pin, GPIO.OUT)
            GPIO.output(pin, False)
    
    def test_movement(self, steps=200):
        if self.motor_type == "NEMA17":
            self.test_nema17(steps)
        else:
            self.test_28byj48(steps)
    
    def test_nema17(self, steps):
        GPIO.output(self.ENABLE_PIN, GPIO.LOW)  # Enable motor
        GPIO.output(self.DIR_PIN, GPIO.HIGH)    # Set direction
        
        for _ in range(steps):
            GPIO.output(self.STEP_PIN, GPIO.HIGH)
            time.sleep(0.001)
            GPIO.output(self.STEP_PIN, GPIO.LOW)
            time.sleep(0.001)
    
    def cleanup(self):
        GPIO.cleanup()

if __name__ == "__main__":
    tester = MotorTester()
    try:
        tester.test_movement()
    finally:
        tester.cleanup()
