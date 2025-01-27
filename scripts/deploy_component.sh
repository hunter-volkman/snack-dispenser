#!/bin/bash
set -e

# Configuration
COMPONENT_NAME="com.snackbot.core"
COMPONENT_VERSION="1.0.0"
S3_BUCKET="snack-bot-data"
REGION="us-east-1"

# Get absolute paths
PROJECT_ROOT=$(pwd)
RECIPE_FILE="$PROJECT_ROOT/config/greengrass/com.snackbot.core-1.0.0.yaml"

echo "📦 Packaging and deploying Snack Bot component..."

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo "❌ Failed to get AWS account ID"
    exit 1
fi

# Verify recipe file exists
if [ ! -f "$RECIPE_FILE" ]; then
    echo "❌ Recipe file not found: $RECIPE_FILE"
    exit 1
fi

echo "📝 Using recipe file: $RECIPE_FILE"

# Create temporary directory for packaging
TEMP_DIR=$(mktemp -d)
PACKAGE_DIR="$TEMP_DIR/snackbot"

# Create package structure
mkdir -p "$PACKAGE_DIR"/{app,vision,motor}

# Copy files
echo "📁 Copying files..."
cp -r src/vision/*.py "$PACKAGE_DIR/vision/"
cp -r src/motor/*.py "$PACKAGE_DIR/motor/"
cp -r src/app/*.py "$PACKAGE_DIR/app/"
cp config/config.yaml "$PACKAGE_DIR/"
cp requirements.txt "$PACKAGE_DIR/"

# Create zip package
cd "$TEMP_DIR"
zip -r snackbot.zip snackbot/

# Upload to S3
echo "☁️ Uploading component to S3..."
aws s3 cp snackbot.zip "s3://$S3_BUCKET/components/$COMPONENT_NAME/$COMPONENT_VERSION/"

# Go back to project root
cd "$PROJECT_ROOT"

# Create component
echo "🔧 Creating component version..."
aws greengrassv2 create-component-version \
    --inline-recipe "fileb://$RECIPE_FILE" \
    --region "$REGION"

# Create deployment
echo "🚀 Creating deployment..."
DEPLOYMENT_ID=$(aws greengrassv2 create-deployment \
    --target-arn "arn:aws:iot:$REGION:$AWS_ACCOUNT_ID:thing/SnackBotCore" \
    --deployment-name "SnackBotDeployment" \
    --components "{\"$COMPONENT_NAME\":{\"componentVersion\":\"$COMPONENT_VERSION\"}}" \
    --region "$REGION" \
    --query "deploymentId" \
    --output text)

# Clean up
rm -rf "$TEMP_DIR"

echo "✅ Deployment created with ID: $DEPLOYMENT_ID"
echo "📝 Check deployment status with:"
echo "aws greengrassv2 get-deployment --deployment-id $DEPLOYMENT_ID --region $REGION"
echo "📝 View logs with:"
echo "sudo tail -f /greengrass/v2/logs/com.snackbot.core.log"