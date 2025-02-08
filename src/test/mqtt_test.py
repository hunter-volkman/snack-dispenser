#!/usr/bin/env python3
import time
import json
import traceback
import sys
import awsiot.greengrasscoreipc
import awsiot.greengrasscoreipc.client as client
from awsiot.greengrasscoreipc.model import (
    PublishToIoTCoreRequest,
    QOS
)

print("Starting MQTT Test Component...")
sys.stdout.flush()

try:
    ipc_client = awsiot.greengrasscoreipc.connect()
    print("Successfully connected to IPC client")
    sys.stdout.flush()
    
    while True:
        try:
            message = {
                "message": "Hello from Greengrass!",
                "timestamp": time.time()
            }
            
            request = PublishToIoTCoreRequest(
                topic_name="test/messages",
                qos=QOS.AT_LEAST_ONCE,
                payload=json.dumps(message).encode()
            )
            
            operation = ipc_client.new_publish_to_iot_core()
            operation.activate(request)
            future = operation.get_response()
            future.result(timeout=5.0)
            
            print(f"Successfully published: {message}")
            sys.stdout.flush()
            
        except Exception as e:
            print(f"Failed to publish message: {e}")
            print(traceback.format_exc())
            sys.stdout.flush()
        
        time.sleep(5)

except Exception as e:
    print(f"Exception in main: {e}")
    print(traceback.format_exc())
    sys.stdout.flush()
