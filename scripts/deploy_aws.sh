#!/bin/bash
set -e  # Exit on first error
set -o pipefail  # Fail on first pipe error

echo "🚀 Deploying Edge Snack Dispenser component to AWS Greengrass..."

# Disable AWS CLI pager
export AWS_PAGER=""

# Define variables
THING_NAME="EdgeSnackDispenserCoreThing"
REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

S3_BUCKET="edge-snack-dispenser-demo-artifacts"
ARTIFACT_ZIP="edge-snack-dispenser.zip"
RECIPE_FILE="aws/recipes/edge-snack-dispenser.core-1.0.0.yaml"
DEPLOYMENT_NAME="EdgeSnackDispenserDeployment"
TARGET_ARN="arn:aws:iot:${REGION}:${AWS_ACCOUNT_ID}:thing/${THING_NAME}"

# --------------------------------------------
# 1️⃣ Remove previous deployments (if failed)
# --------------------------------------------
echo "🛠️ Cleaning up old failed deployments..."
DEPLOYMENTS=$(aws greengrassv2 list-deployments --query "deployments[?status=='FAILED'].deploymentId" --output text)
for DEPLOYMENT_ID in $DEPLOYMENTS; do
    echo "❌ Deleting failed deployment: $DEPLOYMENT_ID"
    aws greengrassv2 cancel-deployment --deployment-id "$DEPLOYMENT_ID" || true
done

# --------------------------------------------
# 2️⃣ Package & Upload Component Artifacts
# --------------------------------------------
echo "📦 Packaging component into ${ARTIFACT_ZIP}..."
zip -r ${ARTIFACT_ZIP} aws/ common/

echo "☁️ Uploading artifact to S3 bucket ${S3_BUCKET}..."
aws s3 mb s3://${S3_BUCKET} || true
aws s3 cp ${ARTIFACT_ZIP} s3://${S3_BUCKET}/

# --------------------------------------------
# 3️⃣ Create New Component Version
# --------------------------------------------
echo "🛠️ Creating component version using recipe file ${RECIPE_FILE}..."
aws greengrassv2 create-component-version --inline-recipe fileb://${RECIPE_FILE} || echo "⚠️ Component already exists"

# --------------------------------------------
# 4️⃣ Deploy Greengrass CLI (If Not Installed)
# --------------------------------------------
echo "🔍 Checking if Greengrass CLI is installed..."
if ! [ -f "/greengrass/v2/bin/greengrass-cli" ]; then
    echo "⚠️ Greengrass CLI is missing! Deploying aws.greengrass.Cli..."
    aws greengrassv2 create-deployment \
        --target-arn "${TARGET_ARN}" \
        --deployment-name "GreengrassCLIDeployment" \
        --components "{\"aws.greengrass.Cli\":{\"componentVersion\":\"2.13.0\"}}" || true
    echo "✅ Greengrass CLI deployment initiated. Waiting for 60 seconds..."
    sleep 60
fi

# --------------------------------------------
# 5️⃣ Deploy EdgeSnackDispenser Component
# --------------------------------------------
echo "🚀 Deploying Edge Snack Dispenser component..."
aws greengrassv2 create-deployment \
  --target-arn "${TARGET_ARN}" \
  --deployment-name "${DEPLOYMENT_NAME}" \
  --components "{
    \"aws.greengrass.Cli\": {\"componentVersion\": \"2.13.0\"},
    \"com.edgesnackdispenser.core\": {\"componentVersion\": \"1.0.0\"}
  }"

echo "✅ Deployment initiated. Monitor device logs for status."
