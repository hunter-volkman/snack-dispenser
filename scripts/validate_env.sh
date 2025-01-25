#!/bin/bash

echo "Validating environment setup..."

# Check Python
python3 --version
pip3 --version

# Check AWS CLI
aws --version

# Check Greengrass
systemctl status greengrass.service

# Check camera
vcgencmd get_camera

# Check GPIO
gpio -v

# Check directories
ls -la /greengrass/v2

echo "Validation complete."