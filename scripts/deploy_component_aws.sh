#!/bin/bash
set -e

echo "Deploying Edge Snack Dispenser component to AWS Greengrass..."

THING_NAME="EdgeSnackDispenserCoreThing"
REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

ARTIFACT_ZIP="edge-snack-dispenser.zip"
echo "Packaging component into ${ARTIFACT_ZIP}..."
zip -r ${ARTIFACT_ZIP} aws/ common/

S3_BUCKET="edge-snack-dispenser-artifacts"
echo "Uploading artifact to S3 bucket ${S3_BUCKET}..."
aws s3 mb s3://${S3_BUCKET} || true
aws s3 cp ${ARTIFACT_ZIP} s3://${S3_BUCKET}/

RECIPE_FILE="docs/edge-snack-dispenser.core-1.0.0.yaml"
echo "Creating component version using recipe file ${RECIPE_FILE}..."
aws greengrassv2 create-component-version --inline-recipe fileb://${RECIPE_FILE}

DEPLOYMENT_NAME="EdgeSnackDispenserDeployment"
TARGET_ARN="arn:aws:iot:${REGION}:${AWS_ACCOUNT_ID}:thing/${THING_NAME}"
echo "Starting deployment to ${TARGET_ARN}..."
aws greengrassv2 create-deployment \
  --target-arn "${TARGET_ARN}" \
  --deployment-name "${DEPLOYMENT_NAME}" \
  --components "{\"com.edgesnackdispenser.core\":{\"componentVersion\":\"1.0.0\"}}"

echo "Deployment initiated. Please monitor device logs for status."
