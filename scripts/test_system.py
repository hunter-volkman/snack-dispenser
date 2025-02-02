import os
import sys
import subprocess
import psutil

def check_environment():
    """Verify Python environment and dependencies."""
    try:
        import cv2
        import numpy
        import RPi.GPIO
        print("Required packages available")
        return True
    except ImportError as e:
        print(f"Missing package: {e}")
        return False

def check_camera():
    """Verify camera device exists."""
    return os.path.exists('/dev/video0')

def check_gpio():
    """Verify GPIO access."""
    try:
        import RPi.GPIO as GPIO
        GPIO.setmode(GPIO.BOARD)
        GPIO.setup(12, GPIO.OUT)
        GPIO.cleanup()
        return True
    except Exception as e:
        print(f"GPIO test failed: {e}")
        return False

def check_system_resources():
    """Check system resources."""
    cpu_percent = psutil.cpu_percent()
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    
    return {
        "cpu_usage": cpu_percent,
        "memory_available": memory.available / (1024 * 1024),  # MB
        "disk_free": disk.free / (1024 * 1024 * 1024)  # GB
    }

def main():
    print("Running system tests...\n")
    
    # Check Python environment
    print("1. Checking Python environment...")
    env_ok = check_environment()
    
    # Check camera
    print("\n2. Checking camera...")
    camera_ok = check_camera()
    
    # Check GPIO
    print("\n3. Checking GPIO...")
    gpio_ok = check_gpio()
    
    # Check system resources
    print("\n4. Checking system resources...")
    resources = check_system_resources()
    
    # Print results
    print("\nTest Results:")
    print(f"Environment Check: {'PASS' if env_ok else 'FAIL'}")
    print(f"Camera Check: {'PASS' if camera_ok else 'FAIL'}")
    print(f"GPIO Check: {'PASS' if gpio_ok else 'FAIL'}")
    print("\nSystem Resources:")
    print(f"CPU Usage: {resources['cpu_usage']}%")
    print(f"Memory Available: {resources['memory_available']:.2f} MB")
    print(f"Disk Space Free: {resources['disk_free']:.2f} GB")
    
    # Set exit code
    if not all([env_ok, camera_ok, gpio_ok]):
        sys.exit(1)

if __name__ == "__main__":
    main()