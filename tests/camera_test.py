import cv2
import time
import os

def test_camera(device_id=0, num_frames=100):
    """Test camera functionality and performance."""
    cap = cv2.VideoCapture(device_id)
    if not cap.isOpened():
        return False, "Failed to open camera"
    
    # Get camera properties
    width = cap.get(cv2.CAP_PROP_FRAME_WIDTH)
    height = cap.get(cv2.CAP_PROP_FRAME_HEIGHT)
    fps = cap.get(cv2.CAP_PROP_FPS)
    
    # Test frame capture
    frames_captured = 0
    start_time = time.time()
    
    # Save last frame for verification
    last_frame = None
    
    try:
        while frames_captured < num_frames:
            ret, frame = cap.read()
            if not ret:
                break
            frames_captured += 1
            last_frame = frame
        
        end_time = time.time()
        actual_fps = frames_captured / (end_time - start_time)
        
        # Save test image
        if last_frame is not None:
            cv2.imwrite('test_frame.jpg', last_frame)
            
        return True, {
            "resolution": f"{width}x{height}",
            "advertised_fps": fps,
            "actual_fps": actual_fps,
            "frames_captured": frames_captured
        }
    finally:
        cap.release()

if __name__ == "__main__":
    success, result = test_camera()
    if success:
        print("Camera Test Results:")
        for key, value in result.items():
            print(f"{key}: {value}")
    else:
        print(f"Camera test failed: {result}")