#!/bin/bash
# cleanup_aws.sh - Removes all AWS resources for Edge Snack Dispenser

# Don't exit on error - continue cleanup even if some resources don't exist
set +e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
INFO="${GREEN}[INFO]${NC}"
WARN="${YELLOW}[WARN]${NC}"
ERROR="${RED}[ERROR]${NC}"

# Configuration - must match setup_aws.sh exactly
THING_NAME="EdgeSnackDispenserCore"
THING_GROUP="EdgeSnackDispenserGroup"
REGION="us-east-1"
S3_BUCKET="edge-snack-dispenser-artifacts"
ROLE_NAME="EdgeSnackDispenserRole"
COMPONENT_NAME="com.edgesnackdispenser.core"

echo -e "${INFO} Cleaning up Edge Snack Dispenser resources..."

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Stop Greengrass service first
echo -e "${INFO} Stopping Greengrass service..."
systemctl stop greengrass || true

# Cancel any active deployments
echo -e "${INFO} Canceling active deployments..."
DEPLOYMENTS=$(aws greengrassv2 list-deployments \
    --target-arn "arn:aws:iot:${REGION}:${AWS_ACCOUNT_ID}:thing/${THING_NAME}" \
    --query 'deployments[*].deploymentId' --output text || echo "")
for DEPLOYMENT_ID in $DEPLOYMENTS; do
    echo -e "${INFO} Canceling deployment: $DEPLOYMENT_ID"
    aws greengrassv2 cancel-deployment --deployment-id "$DEPLOYMENT_ID" || true
done

# Clean up S3 bucket first (to prevent dependency issues)
echo -e "${INFO} Cleaning up S3 bucket..."
if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
    echo -e "${INFO} Emptying S3 bucket..."
    aws s3 rm "s3://${S3_BUCKET}" --recursive || true
    echo -e "${INFO} Deleting S3 bucket..."
    aws s3api delete-bucket --bucket "$S3_BUCKET" || true
fi

# Clean up Greengrass components
echo -e "${INFO} Cleaning up Greengrass components..."
COMPONENT_ARN="arn:aws:greengrass:${REGION}:${AWS_ACCOUNT_ID}:components:${COMPONENT_NAME}"
VERSIONS=$(aws greengrassv2 list-component-versions --arn "$COMPONENT_ARN" --query 'componentVersions[*].componentVersion' --output text || echo "")

for VERSION in $VERSIONS; do
    echo -e "${INFO} Deleting component version: $VERSION"
    aws greengrassv2 delete-component --arn "${COMPONENT_ARN}:versions:${VERSION}" || true
done

# Clean up IoT certificates and policies
echo -e "${INFO} Processing IoT certificates and policies..."
CERT_ARNS=$(aws iot list-thing-principals --thing-name "$THING_NAME" --query 'principals[]' --output text || echo "")

for CERT_ARN in $CERT_ARNS; do
    echo -e "${INFO} Processing certificate: $CERT_ARN"
    CERT_ID=$(echo "$CERT_ARN" | awk -F/ '{print $NF}')
    
    # List and detach all policies from certificate
    ATTACHED_POLICIES=$(aws iot list-principal-policies --principal "$CERT_ARN" --query 'policies[*].policyName' --output text || echo "")
    for POLICY_NAME in $ATTACHED_POLICIES; do
        echo -e "${INFO} Detaching policy $POLICY_NAME from certificate"
        aws iot detach-policy --policy-name "$POLICY_NAME" --target "$CERT_ARN" || true
    done
    
    # Detach from thing
    aws iot detach-thing-principal --thing-name "$THING_NAME" --principal "$CERT_ARN" || true
    
    # Deactivate and delete certificate
    aws iot update-certificate --certificate-id "$CERT_ID" --new-status INACTIVE || true
    aws iot delete-certificate --certificate-id "$CERT_ID" --force || true
done

# Clean up IoT policies (both our policy and Greengrass-created policy)
echo -e "${INFO} Cleaning up IoT policies..."
for POLICY_NAME in "${THING_NAME}Policy" "GreengrassV2IoTThingPolicy"; do
    # Get all targets for the policy
    TARGETS=$(aws iot list-targets-for-policy --policy-name "$POLICY_NAME" --query 'targets[]' --output text || echo "")
    
    # Detach policy from all targets
    for TARGET in $TARGETS; do
        echo -e "${INFO} Detaching policy $POLICY_NAME from $TARGET"
        aws iot detach-policy --policy-name "$POLICY_NAME" --target "$TARGET" || true
    done
    
    # Delete the policy
    echo -e "${INFO} Deleting policy $POLICY_NAME"
    aws iot delete-policy --policy-name "$POLICY_NAME" || true
done

# Delete Thing and Thing Group
echo -e "${INFO} Deleting IoT Thing and Thing Group..."
aws iot delete-thing --thing-name "$THING_NAME" || true
aws iot delete-thing-group --thing-group-name "$THING_GROUP" || true

# Clean up role alias before IAM role
echo -e "${INFO} Cleaning up role alias..."
aws iot delete-role-alias --role-alias "GreengrassV2TokenExchangeRoleAlias" || true

# Clean up IAM role
echo -e "${INFO} Cleaning up IAM role..."
# First remove all inline policies
ROLE_POLICIES=$(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames[]' --output text || echo "")
for POLICY in $ROLE_POLICIES; do
    echo -e "${INFO} Removing inline policy: $POLICY"
    aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY" || true
done

# Then detach all managed policies
ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[*].PolicyArn' --output text || echo "")
for POLICY_ARN in $ATTACHED_POLICIES; do
    echo -e "${INFO} Detaching managed policy: $POLICY_ARN"
    aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" || true
done

# Make sure Greengrass managed policy is detached
echo -e "${INFO} Detaching Greengrass managed policy..."
aws iam detach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/GreengrassV2TokenExchangeRoleAccess" || true

# Delete the role
aws iam delete-role --role-name "$ROLE_NAME" || true

# Clean up Greengrass Core device registration
echo -e "${INFO} Cleaning up Greengrass Core device..."
aws greengrassv2 delete-core-device --core-device-thing-name "$THING_NAME" || true

# Clean up local Greengrass installation
echo -e "${INFO} Cleaning up local Greengrass installation..."
systemctl disable greengrass || true
rm -f /etc/systemd/system/greengrass.service
systemctl daemon-reload

# Remove Greengrass directories
rm -rf /greengrass
rm -rf GreengrassInstaller
rm -f greengrass-nucleus.zip

# Remove Greengrass user and group
echo -e "${INFO} Removing Greengrass user and group..."
userdel ggc_user || true
groupdel ggc_group || true

# Clean up local certificates
rm -f device.pem.crt private.pem.key public.pem.key root.ca.pem

echo -e "\n${GREEN}✅ Cleanup complete!${NC}"
echo -e "${INFO} All Edge Snack Dispenser resources have been removed."
echo "You can now run setup_aws.sh for a fresh installation."