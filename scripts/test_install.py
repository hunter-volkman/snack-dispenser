#!/usr/bin/env python3
"""
Verify Edge Snack Dispenser installation and dependencies
"""
import sys
import cv2
import numpy as np
import RPi.GPIO as GPIO
import yaml
from pathlib import Path

def check_camera():
    """Test camera functionality"""
    print("Testing camera...")
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        return False, "Failed to open camera"
    
    ret, frame = cap.read()
    cap.release()
    
    if not ret:
        return False, "Failed to capture frame"
    
    return True, "Camera working"

def check_gpio():
    """Test GPIO access"""
    print("Testing GPIO...")
    try:
        GPIO.setmode(GPIO.BOARD)
        GPIO.setup(12, GPIO.OUT)
        GPIO.cleanup()
        return True, "GPIO working"
    except Exception as e:
        return False, f"GPIO error: {str(e)}"

def check_config():
    """Verify config file exists and is valid"""
    print("Checking configuration...")
    config_path = Path("config/config.yaml")
    if not config_path.exists():
        return False, "Config file missing"
    
    try:
        with open(config_path) as f:
            yaml.safe_load(f)
        return True, "Config valid"
    except Exception as e:
        return False, f"Config error: {str(e)}"

def main():
    """Run all tests"""
    tests = [
        ("Camera", check_camera),
        ("GPIO", check_gpio),
        ("Config", check_config)
    ]
    
    all_passed = True
    print("\n🤖 Running Edge Snack Dispenser system tests...\n")
    
    for name, test_func in tests:
        success, message = test_func()
        status = "✅" if success else "❌"
        print(f"{status} {name}: {message}")
        if not success:
            all_passed = False
    
    print("\n" + ("🎉 All tests passed!" if all_passed else "❌ Some tests failed"))
    sys.exit(0 if all_passed else 1)

if __name__ == "__main__":
    main()