#!/bin/bash
# cleanup_aws_sample.sh
# Removes all AWS resources created by deploy_aws_sample.sh and cleans up local Greengrass installation

set -e
set -o pipefail

# Configuration (must match deploy_aws_sample.sh)
COMPONENT_NAME="com.example.helloworld"
COMPONENT_VERSION="1.0.0"
THING_NAME="HelloWorldCore"
REGION="us-east-1"
S3_BUCKET="hello-world-demo-artifacts"
IOT_POLICY_NAME="HelloWorldPolicy"

echo "🧹 Cleaning up Hello World sample resources..."

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Function to check if IoT Thing exists
thing_exists() {
    aws iot describe-thing --thing-name "$1" > /dev/null 2>&1
    return $?
}

# Function to check if IoT Policy exists
policy_exists() {
    aws iot get-policy --policy-name "$1" > /dev/null 2>&1
    return $?
}

# 0. Stop Greengrass service and clean up local installation
echo "Stopping Greengrass service..."
sudo systemctl stop greengrass || true

echo "Removing Greengrass installation..."
sudo rm -rf /greengrass
sudo rm -rf GreengrassInstaller
rm -f greengrass-nucleus.zip

# Clean up system service
echo "Removing Greengrass system service..."
sudo systemctl disable greengrass || true
sudo rm -f /etc/systemd/system/greengrass.service
sudo systemctl daemon-reload

# Remove Greengrass user and group
echo "Removing Greengrass user and group..."
sudo userdel ggc_user || true
sudo groupdel ggc_group || true

# 1. Cancel any active deployments for this component
echo "Checking for active deployments..."
DEPLOYMENTS=$(aws greengrassv2 list-deployments \
    --target-arn "arn:aws:iot:${REGION}:${AWS_ACCOUNT_ID}:thing/${THING_NAME}" \
    --query 'deployments[?components."`'${COMPONENT_NAME}'`"].deploymentId' \
    --output text)

if [ ! -z "$DEPLOYMENTS" ]; then
    for DEPLOYMENT_ID in $DEPLOYMENTS; do
        echo "Canceling deployment: $DEPLOYMENT_ID"
        aws greengrassv2 cancel-deployment --deployment-id "$DEPLOYMENT_ID" || true
    done
fi

# 2. Delete Greengrass component versions
echo "Deleting Greengrass component versions..."
COMPONENT_ARN="arn:aws:greengrass:${REGION}:${AWS_ACCOUNT_ID}:components:${COMPONENT_NAME}"
VERSIONS=$(aws greengrassv2 list-component-versions --arn "$COMPONENT_ARN" \
    --query 'componentVersions[].componentVersion' --output text)

if [ ! -z "$VERSIONS" ]; then
    for VERSION in $VERSIONS; do
        echo "Deleting component version: $VERSION"
        aws greengrassv2 delete-component --arn "${COMPONENT_ARN}:versions:${VERSION}" || true
    done
fi

# 3. Clean up IoT Thing and certificates
if thing_exists "$THING_NAME"; then
    echo "Cleaning up IoT Thing: $THING_NAME"
    
    # Get certificates attached to thing
    PRINCIPALS=$(aws iot list-thing-principals --thing-name "$THING_NAME" \
        --query 'principals[]' --output text)
    
    if [ ! -z "$PRINCIPALS" ]; then
        for CERT_ARN in $PRINCIPALS; do
            echo "Processing certificate: $CERT_ARN"
            CERT_ID=$(echo "$CERT_ARN" | awk -F/ '{print $NF}')
            
            # Detach policy if it exists
            if policy_exists "$IOT_POLICY_NAME"; then
                echo "Detaching policy from certificate..."
                aws iot detach-policy --policy-name "$IOT_POLICY_NAME" \
                    --target "$CERT_ARN" || true
            fi
            
            # Detach certificate from thing
            echo "Detaching certificate from thing..."
            aws iot detach-thing-principal --thing-name "$THING_NAME" \
                --principal "$CERT_ARN"
            
            # Deactivate and delete certificate
            echo "Deactivating certificate..."
            aws iot update-certificate --certificate-id "$CERT_ID" \
                --new-status INACTIVE
            
            echo "Deleting certificate..."
            aws iot delete-certificate --certificate-id "$CERT_ID" --force
        done
    fi
    
    # Delete the thing
    echo "Deleting IoT Thing..."
    aws iot delete-thing --thing-name "$THING_NAME"
fi

# 4. Delete Greengrass Core Device registration
echo "Removing Greengrass Core Device registration..."
aws greengrassv2 delete-core-device --core-device-thing-name "$THING_NAME" || true

# 5. Clean up Token Exchange Role and Alias
ROLE_NAME="GreengrassV2TokenExchangeRole"
ROLE_ALIAS_NAME="GreengrassV2TokenExchangeRoleAlias"

echo "Cleaning up Token Exchange Role and Alias..."
# Delete role alias
aws iot delete-role-alias --role-alias "$ROLE_ALIAS_NAME" || true

# Detach and delete IAM role policies
ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[*].PolicyArn' --output text || echo "")
if [ ! -z "$ATTACHED_POLICIES" ]; then
    for POLICY_ARN in $ATTACHED_POLICIES; do
        echo "Detaching policy $POLICY_ARN from role..."
        aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" || true
    done
fi

# Delete IAM role
aws iam delete-role --role-name "$ROLE_NAME" || true

# 6. Delete IoT Policy
if policy_exists "$IOT_POLICY_NAME"; then
    echo "Deleting IoT Policy..."
    aws iot delete-policy --policy-name "$IOT_POLICY_NAME"
fi

# 7. Clean up S3 bucket
echo "Cleaning up S3 bucket..."
if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
    echo "Emptying S3 bucket..."
    aws s3 rm "s3://${S3_BUCKET}" --recursive
    echo "Deleting S3 bucket..."
    aws s3api delete-bucket --bucket "$S3_BUCKET"
fi

# 6. Clean up all local files
echo "Cleaning up local files..."
rm -f device.pem.crt private.pem.key public.pem.key root.ca.pem

echo "✅ Cleanup complete! All Hello World sample resources have been removed."
echo "   Both AWS resources and local Greengrass installation have been cleaned up."
echo "   You can now run deploy_aws_sample.sh again for a fresh installation."