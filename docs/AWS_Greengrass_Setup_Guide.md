# AWS Greengrass Setup Guide for Edge Snack Dispenser

This guide walks you through deploying **Edge Snack Dispenser** on AWS Greengrass using a Raspberry Pi 4.

## Overview

The Edge Snack Dispenser uses computer vision to detect an empty snack bowl and activates a stepper motor to dispense food. This setup leverages AWS Greengrass V2 for local component execution and MQTT messaging to AWS IoT Core.

## Prerequisites

- **Hardware:** Raspberry Pi 4 (2GB+ RAM), USB Camera (e.g., Logitech C920), NEMA 17 Stepper Motor with DRV8825 driver, 12V Power Supply.
- **AWS:** An account with IoT Core and Greengrass permissions.
- **Software:** Raspberry Pi OS (64-bit), AWS CLI, Python 3.7+, and Greengrass Core V2.

## Steps

### 1. Set Up Your Raspberry Pi

Update your system and install required packages:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3-pip python3-venv awscli libopenjp2-7 libilmbase23 libopenexr-dev libavcodec-dev libavformat-dev libswscale-dev libv4l-dev libgtk-3-0 libwebp-dev fswebcam
```

Create and activate a Python virtual environment, then install dependencies:

```bash
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

### 2. Install AWS Greengrass Core

Create necessary directories and install Greengrass Core:

```bash
sudo mkdir -p /greengrass/v2/device_credentials
curl -s https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip -o greengrass-nucleus.zip
unzip greengrass-nucleus.zip -d GreengrassInstaller
sudo -E java -Droot="/greengrass/v2" -Dlog.store=FILE -jar ./GreengrassInstaller/lib/Greengrass.jar \
  --aws-region "us-east-1" --thing-name "EdgeSnackDispenserCore" \
  --component-default-user pi:pi --provision true --setup-system-service true --deploy-dev-tools true
```

Verify Greengrass is running:

```bash
sudo systemctl status greengrass

```

### 3. Configure AWS IoT and Certificates

* Create an IoT Thing named EdgeSnackDispenserCore.
* Create an IAM role (e.g., GreengrassV2TokenExchangeRole) and attach the required policies.
* Generate device certificates and attach them to your IoT Thing.
* Move the certificates to /greengrass/v2/device_credentials/.

### 4. Deploy the Component

Use the deployment script scripts/deploy_component.sh (see repository root) to package, upload, and deploy the component.

### 5. Monitor and Troubleshoot
View logs on the Raspberry Pi:

```bash
sudo tail -f /greengrass/v2/logs/com.edgesnackdispenser.core.log
```

For further details, please refer to the AWS Greengrass V2 documentation.

For additional troubleshooting or setup details, consult the README.md in the repository root.