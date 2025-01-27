import RPi.GPIO as GPIO
import time
import cv2

def test_camera():
    """Test camera capture"""
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        return False
    ret, frame = cap.read()
    cap.release()
    return ret

def test_motor():
    """Test motor movement"""
    # Pin definitions
    STEP_PIN = 12  # GPIO18
    DIR_PIN = 16   # GPIO23
    EN_PIN = 18    # GPIO24
    
    try:
        GPIO.setmode(GPIO.BOARD)
        GPIO.setup([STEP_PIN, DIR_PIN, EN_PIN], GPIO.OUT)
        
        # Enable motor
        GPIO.output(EN_PIN, GPIO.LOW)
        print("Motor enabled - should hear holding torque")
        time.sleep(2)
        
        # Test movement
        GPIO.output(DIR_PIN, GPIO.HIGH)
        for _ in range(50):  # 50 steps
            GPIO.output(STEP_PIN, GPIO.HIGH)
            time.sleep(0.01)
            GPIO.output(STEP_PIN, GPIO.LOW)
            time.sleep(0.01)
            
        return True
    except Exception as e:
        print(f"Motor test failed: {e}")
        return False
    finally:
        GPIO.cleanup()

def main():
    print("Starting hardware tests...")
    
    print("\nTesting camera...")
    if test_camera():
        print("Camera test PASSED")
    else:
        print("Camera test FAILED")
    
    print("\nTesting motor...")
    if test_motor():
        print("Motor test PASSED")
    else:
        print("Motor test FAILED")

if __name__ == "__main__":
    main()