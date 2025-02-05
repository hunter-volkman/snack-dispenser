#!/bin/bash

# ====================================================================
# reset_aws.sh
#
# WARNING: This script deletes AWS IoT and Greengrass resources created
# for the Edge Snack Dispenser demo. Use only in your test environment.
# ====================================================================

# Don't exit on error - continue cleanup even if some resources don't exist
set +e

# AWS resource names
THING_NAME="EdgeSnackDispenserCoreThing"
THING_GROUP="EdgeSnackDispenserCoreThingGroup"
ROLE_NAME="GreengrassV2TokenExchangeRole"
POLICY_NAME="GreengrassV2IoTThingPolicy"
COMPONENT_NAME="com.edgesnackdispenser.core"
REGION="us-east-1"

echo "Resetting AWS IoT and Greengrass resources for Edge Snack Dispenser..."
echo "NOTE: Please manually delete any active Greengrass deployments if needed."

# Function to check if an IoT Thing exists
thing_exists() {
    aws iot describe-thing --thing-name "$1" > /dev/null 2>&1
    return $?
}

# Function to check if an IoT Policy exists
policy_exists() {
    aws iot get-policy --policy-name "$1" > /dev/null 2>&1
    return $?
}

# Function to check if an IAM Role exists
role_exists() {
    aws iam get-role --role-name "$1" > /dev/null 2>&1
    return $?
}

# -------------------------------------------
# Step 1: Clean up IoT Certificates
# -------------------------------------------
if thing_exists "$THING_NAME"; then
    echo "Found IoT Thing: $THING_NAME. Cleaning up..."

    # Get attached certificates
    PRINCIPALS=$(aws iot list-thing-principals --thing-name "$THING_NAME" --query 'principals' --output text)

    if [[ -n "$PRINCIPALS" ]]; then
        for CERT_ARN in $PRINCIPALS; do
            echo "Processing certificate: $CERT_ARN"

            # Detach IoT Policy if it exists
            if policy_exists "$POLICY_NAME"; then
                echo "Detaching IoT policy from certificate..."
                aws iot detach-policy --policy-name "$POLICY_NAME" --target "$CERT_ARN"
            fi

            # Detach certificate from IoT Thing
            echo "Detaching certificate from Thing..."
            aws iot detach-thing-principal --thing-name "$THING_NAME" --principal "$CERT_ARN"

            # Extract Certificate ID
            CERT_ID=$(basename "$CERT_ARN")

            # Deactivate and delete certificate
            echo "Deactivating certificate..."
            aws iot update-certificate --certificate-id "$CERT_ID" --new-status INACTIVE
            
            echo "Deleting certificate..."
            aws iot delete-certificate --certificate-id "$CERT_ID" --force
        done
    else
        echo "No certificates found for IoT Thing: $THING_NAME."
    fi

    # Delete IoT Thing
    echo "Deleting IoT Thing..."
    aws iot delete-thing --thing-name "$THING_NAME"
else
    echo "IoT Thing $THING_NAME not found, skipping..."
fi

# -------------------------------------------
# Step 2: Delete IoT Policy
# -------------------------------------------
if policy_exists "$POLICY_NAME"; then
    echo "Deleting IoT policy..."
    aws iot delete-policy --policy-name "$POLICY_NAME"
else
    echo "IoT Policy $POLICY_NAME not found, skipping..."
fi

# -------------------------------------------
# Step 3: Delete IoT Thing Group
# -------------------------------------------
if aws iot describe-thing-group --thing-group-name "$THING_GROUP" > /dev/null 2>&1; then
    echo "Deleting IoT Thing Group..."
    aws iot delete-thing-group --thing-group-name "$THING_GROUP"
else
    echo "Thing Group $THING_GROUP not found, skipping..."
fi

# -------------------------------------------
# Step 4: Clean up IAM Role
# -------------------------------------------
if role_exists "$ROLE_NAME"; then
    echo "Found IAM Role: $ROLE_NAME. Cleaning up..."

    # Detach managed policies
    ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text)
    if [[ -n "$ATTACHED_POLICIES" ]]; then
        for POLICY_ARN in $ATTACHED_POLICIES; do
            echo "Detaching policy $POLICY_ARN..."
            aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN"
        done
    fi

    # Delete inline policies
    INLINE_POLICIES=$(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames[]' --output text)
    if [[ -n "$INLINE_POLICIES" ]]; then
        for POLICY in $INLINE_POLICIES; do
            echo "Deleting inline policy $POLICY..."
            aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY"
        done
    fi

    # Delete IAM Role
    echo "Deleting IAM role..."
    aws iam delete-role --role-name "$ROLE_NAME"
else
    echo "IAM Role $ROLE_NAME not found, skipping..."
fi

# -------------------------------------------
# Step 5: Clean up Greengrass Component
# -------------------------------------------
echo "Checking for Greengrass components..."
COMPONENT_VERSIONS=$(aws greengrassv2 list-component-versions --arn "arn:aws:greengrass:$REGION:$(aws sts get-caller-identity --query Account --output text):components:$COMPONENT_NAME" --query 'componentVersions[].arn' --output text)

if [[ -n "$COMPONENT_VERSIONS" ]]; then
    for COMPONENT_ARN in $COMPONENT_VERSIONS; do
        echo "Deleting Greengrass component: $COMPONENT_ARN"
        aws greengrassv2 delete-component --arn "$COMPONENT_ARN"
    done
else
    echo "No Greengrass components found for $COMPONENT_NAME."
fi

# -------------------------------------------
# Step 6: Clean up Local Greengrass Directories
# -------------------------------------------
if [[ -d "/greengrass" ]]; then
    echo "Cleaning up local Greengrass directories..."
    sudo rm -rf /greengrass
fi

echo "✅ Reset complete! All Edge Snack Dispenser resources have been cleaned up."
