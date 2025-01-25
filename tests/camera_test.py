import cv2
import time
import os

def test_camera(device_id=0, num_frames=100):
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
    
    # Placeholder to store the last successfully captured frame
    last_frame = None  
    while frames_captured < num_frames:
        ret, frame = cap.read()
        if not ret:
            break
        frames_captured += 1
        
        # Keep the latest frame
        last_frame = frame 
    
    end_time = time.time()
    actual_fps = frames_captured / (end_time - start_time)

    # Save the last frame after the test
    if last_frame is not None:
        cv2.imshow("Last Frame", last_frame)
        # Wait for a key press to close the window
        cv2.waitKey(0)
        # Print debug info before saving
        print(f"Attempting to save the last frame to: {os.path.abspath('test_frame.jpg')}")
        success = cv2.imwrite("test_frame.jpg", last_frame)  # Save frame to a file
        if success:
            print("Frame saved successfully!")
        else:
            print("Failed to save the frame!")
    else:
        print("No frame captured to save.")
    
    cap.release()
    return True, {
        "resolution": f"{width}x{height}",
        "advertised_fps": fps,
        "actual_fps": actual_fps,
        "frames_captured": frames_captured
    }

if __name__ == "__main__":
    success, result = test_camera()
    print(f"Camera Test Results: {result}")
