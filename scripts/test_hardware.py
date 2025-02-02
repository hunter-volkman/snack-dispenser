import RPi.GPIO as GPIO
import time
import cv2

def test_camera(device_id=0, num_frames=100):
    """Test camera functionality and performance."""
    cap = cv2.VideoCapture(device_id)
    if not cap.isOpened():
        return False, "Failed to open camera"
    
    # Get camera properties
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS)
    
    print(f"Camera detected - Resolution: {width}x{height}, Advertised FPS: {fps}")

    # Test frame capture
    frames_captured = 0
    start_time = time.time()
    
    # Save last frame for verification
    last_frame = None
    
    try:
        print("Capturing test frames...")
        while frames_captured < num_frames:
            ret, frame = cap.read()
            if not ret:
                print("  Warning: Frame capture failed")
                break
            frames_captured += 1
            last_frame = frame
            
            # Log every 20 frames
            if frames_captured % 20 == 0:
                print(f"  Captured {frames_captured}/{num_frames} frames...")

        end_time = time.time()
        actual_fps = frames_captured / (end_time - start_time)

    # Save test image
        image_path = "test_frame.jpg"
        if last_frame is not None:
            cv2.imwrite(image_path, last_frame)
            print(f"Test image saved: {image_path}")
        
        print("Camera test completed")
        return True, {
            "resolution": f"{width}x{height}",
            "advertised_fps": fps,
            "actual_fps": actual_fps,
            "frames_captured": frames_captured,
            "image_saved": image_path if last_frame is not None else "No image captured"
        }
    finally:
        cap.release()


def test_motor():
    """Test motor movement"""
    # Pin definitions
    DIR_PIN = 15
    STEP_PIN = 16 
    EN_PIN = 18 
    
    try:
        GPIO.setmode(GPIO.BOARD)
        GPIO.setup([STEP_PIN, DIR_PIN, EN_PIN], GPIO.OUT)
        
        # Enable motor
        GPIO.output(EN_PIN, GPIO.LOW)
        print("Motor enabled - should hear holding torque")
        time.sleep(2)
        
        # Test movement
        GPIO.output(DIR_PIN, GPIO.HIGH)
        print("Motor enabled - beginning test movement (50 steps)")
        
        # 50 steps
        for step in range(50):
            GPIO.output(STEP_PIN, GPIO.HIGH)
            time.sleep(0.01)
            GPIO.output(STEP_PIN, GPIO.LOW)
            time.sleep(0.01)
            if step % 10 == 0:
                print(f"  Step {step + 1}/50 completed")
            
        print("Motor test movement completed")
        return True
    except Exception as e:
        print(f"Motor test failed: {e}")
        return False
    finally:
        GPIO.cleanup()

def main():
    print("Starting hardware tests...\n")
    
    print("=== Testing Camera ===")
    success, result = test_camera()
    if success:
        print("Camera test PASSED")
        for key, value in result.items():
            print(f"  {key}: {value}")
    else:
        print(f"Camera test FAILED: {result}")
    
    print("\n=== Testing Motor ===")
    if test_motor():
        print("Motor test PASSED")
    else:
        print("Motor test FAILED")

if __name__ == "__main__":
    main()