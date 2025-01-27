#!/bin/bash

# Set variables
BUCKET_NAME="snack-bot-data"
COMPONENTS_DIR="components"
VERSION="1.0.0"

# Create staging directories
mkdir -p staging/{vision,motor}

# Copy vision component files
cp src/vision/vision_processor.py staging/vision/
cp src/utils/config_loader.py staging/vision/
cp src/utils/image_manager.py staging/vision/

# Create vision requirements.txt
cat > staging/vision/requirements.txt << EOF
opencv-python==4.8.1.78
numpy==1.24.3
tflite-runtime==2.11.0
boto3==1.28.44
awsiot.greengrasscoreipc
EOF

# Copy motor component files
cp src/motor/motor_controller.py staging/motor/
cp src/utils/config_loader.py staging/motor/

# Create motor requirements.txt
cat > staging/motor/requirements.txt << EOF
RPi.GPIO==0.7.1
boto3==1.28.44
awsiot.greengrasscoreipc
EOF

# Upload to S3
aws s3 sync staging/vision/ s3://${BUCKET_NAME}/components/vision/
aws s3 sync staging/motor/ s3://${BUCKET_NAME}/components/motor/

# Clean up staging directory
rm -rf staging

echo "Deployment package prepared and uploaded to S3"