#!/usr/bin/env python3
"""
Viam Control Script for Edge Snack Dispenser

This script demonstrates a simple integration with Viam's API to send remote commands 
(e.g., dispensing a snack) via MQTT. It supports sending commands to either AWS IoT Core 
(for Greengrass) or an Azure IoT Edge MQTT broker.
"""

import json
import time
import argparse
import paho.mqtt.client as mqtt

# Endpoints for AWS and Azure (update these with your actual endpoints or use local brokers)
AWS_IOT_ENDPOINT = "your-aws-iot-endpoint.amazonaws.com"
AZURE_IOT_ENDPOINT = "your-azure-iot-endpoint.azure-devices.net"  # or local MQTT broker address for Azure

def dispense_snack(endpoint, port=1883, topic="edgesnackdispenser/dispense"):
    """Publish an MQTT message to trigger snack dispensing."""
    mqtt_client = mqtt.Client()
    mqtt_client.connect(endpoint, port, 60)
    command_payload = json.dumps({"command": "dispense", "portions": 1})
    mqtt_client.publish(topic, payload=command_payload)
    mqtt_client.disconnect()
    print(f"Dispense command sent to {endpoint} on topic '{topic}'")

def main():
    parser = argparse.ArgumentParser(description="Viam Control Script for Edge Snack Dispenser")
    parser.add_argument(
        "--platform", choices=["aws", "azure"], default="aws",
        help="Target platform: 'aws' for AWS IoT Core (Greengrass) or 'azure' for Azure IoT Edge"
    )
    parser.add_argument("--port", type=int, default=1883, help="MQTT broker port (default: 1883)")
    parser.add_argument(
        "--topic", default="edgesnackdispenser/dispense",
        help="MQTT topic to publish the command (default: edgesnackdispenser/dispense)"
    )
    args = parser.parse_args()

    print("Viam Control Script for Edge Snack Dispenser")
    time.sleep(2)

    if args.platform == "aws":
        endpoint = AWS_IOT_ENDPOINT
    elif args.platform == "azure":
        endpoint = AZURE_IOT_ENDPOINT
    else:
        endpoint = AWS_IOT_ENDPOINT  # Fallback

    dispense_snack(endpoint, port=args.port, topic=args.topic)

if __name__ == "__main__":
    main()
