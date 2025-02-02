#!/bin/bash
set -e

echo "Deploying Edge Snack Dispenser containerized modules to Azure IoT Edge..."

# Variables (update these values as needed)
IOT_HUB_NAME="YourIoTHubName"
DEPLOYMENT_NAME="EdgeSnackDispenserDeployment"
DEVICE_ID="YourDeviceID"

echo "Deploying modules using deployment manifest (azure/config/deployment.json)..."
az iot edge deployment create --deployment-id ${DEPLOYMENT_NAME} \
    --hub-name ${IOT_HUB_NAME} \
    --content azure/config/deployment.json \
    --target-condition "deviceId='${DEVICE_ID}'"

echo "Azure IoT Edge deployment initiated. Use 'iotedge list' to monitor module status."
