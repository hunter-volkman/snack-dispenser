#!/bin/bash
set -e

echo "Setting up Azure IoT Edge on Raspberry Pi for Edge Snack Dispenser..."

# Update system and install dependencies (if not already done)
sudo apt update && sudo apt upgrade -y

# Install Azure IoT Edge runtime
curl -fsSL https://aka.ms/install-iotedge | sudo bash

echo "Azure IoT Edge runtime installation completed."
echo "Register your device in Azure IoT Hub and configure /etc/iotedge/config.yaml accordingly."
