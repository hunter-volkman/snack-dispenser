#!/usr/bin/env python3
"""
Verify AWS and Greengrass setup
"""
import subprocess
import sys
import json
from pathlib import Path

# AWS Configuration
AWS_REGION = "us-east-1"
AWS_PROFILE = "default"
TEST_TOPIC = "test/connectivity"

def check_greengrass_service():
    """Check if Greengrass service is running"""
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', 'greengrass.service'],
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
    
    missing = [file for file in required_files if not (cred_dir / file).exists()]
    return len(missing) == 0, f"Missing files: {', '.join(missing)}" if missing else "All credentials exist"

def check_aws_connectivity():
    """Test AWS IoT connectivity"""
    try:
        cmd = [
            'aws', 'iot', 'describe-endpoint',
            '--endpoint-type', 'iot:Data-ATS',
            '--query', 'endpointAddress',
            '--output', 'text'
        ]
        if AWS_PROFILE != "default":
            cmd.extend(['--profile', AWS_PROFILE])
            
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            return True, f"AWS IoT endpoint: {result.stdout.strip()}"
        return False, result.stderr.strip()
    except Exception as e:
        return False, str(e)

def check_mqtt_connectivity():
    """Test AWS IoT MQTT connectivity by publishing to a test topic"""
    payload = json.dumps({"test": "AWS MQTT Connectivity Check"})
    
    try:
        cmd = [
            'aws', 'iot-data', 'publish',
            '--topic', TEST_TOPIC,
            '--cli-binary-format', 'raw-in-base64-out',
            '--payload', payload,
            '--region', AWS_REGION
        ]
        if AWS_PROFILE != "default":
            cmd.extend(['--profile', AWS_PROFILE])
            
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            return True, f"Successfully published to topic {TEST_TOPIC}"
        return False, result.stderr.strip()
    except Exception as e:
        return False, str(e)

def main():
    """Run all tests"""
    tests = [
        ("Greengrass Service", check_greengrass_service),
        ("Device Credentials", check_credentials),
        ("AWS Connectivity", check_aws_connectivity),
        ("MQTT Connectivity", check_mqtt_connectivity)
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