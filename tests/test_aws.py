#!/usr/bin/env python3
"""
Verify AWS and Greengrass setup
"""
import subprocess
import sys
import json
from pathlib import Path

def check_greengrass_service():
    """Check if Greengrass service is running"""
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', 'greengrass'],
            capture_output=True,
            text=True
        )
        return result.stdout.strip() == 'active', result.stdout.strip()
    except Exception as e:
        return False, str(e)

def check_credentials():
    """Check if Greengrass credentials exist"""
    cred_dir = Path('/greengrass/v2/device_credentials')
    required_files = [
        'device.pem.crt',
        'private.pem.key',
        'public.pem.key',
        'root.ca.pem'
    ]
    
    missing = []
    for file in required_files:
        if not (cred_dir / file).exists():
            missing.append(file)
    
    return len(missing) == 0, missing

def check_aws_connectivity():
    """Test AWS IoT connectivity"""
    try:
        result = subprocess.run(
            ['aws', 'iot', 'describe-endpoint', '--endpoint-type', 'iot:Data-ATS'],
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            return True, "AWS IoT endpoint accessible"
        return False, result.stderr
    except Exception as e:
        return False, str(e)

def main():
    """Run all tests"""
    tests = [
        ("Greengrass Service", check_greengrass_service),
        ("Device Credentials", check_credentials),
        ("AWS Connectivity", check_aws_connectivity)
    ]
    
    all_passed = True
    print("\n🚀 Checking AWS and Greengrass setup...\n")
    
    for name, test_func in tests:
        success, message = test_func()
        status = "✅" if success else "❌"
        print(f"{status} {name}: {message}")
        if not success:
            all_passed = False
    
    print("\n" + ("🎉 All checks passed!" if all_passed else "❌ Some checks failed"))
    sys.exit(0 if all_passed else 1)

if __name__ == "__main__":
    main()