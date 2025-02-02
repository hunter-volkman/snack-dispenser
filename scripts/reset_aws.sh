#!/bin/bash
set -e

# ====================================================================
# reset_aws.sh
#
# WARNING: This script deletes AWS IoT and Greengrass resources created
# for the Edge Snack Dispenser demo. Use only in your test environment.
# ====================================================================

THING_NAME="EdgeSnackDispenserCoreThing"
THING_GROUP="EdgeSnackDispenserCoreThingGroup"
ROLE_NAME="GreengrassV2TokenExchangeRole"
POLICY_NAME="GreengrassV2IoTThingPolicy"
REGION="us-east-1"

echo "Resetting AWS IoT and Greengrass resources for Edge Snack Dispenser..."

echo "NOTE: Please manually delete any active Greengrass deployments if needed."

CERTARN=$(aws iot list-thing-principals --thing-name "$THING_NAME" --query 'principals[0]' --output text)
if [ "$CERTARN" != "None" ]; then
    echo "Detaching IoT policy from certificate..."
    aws iot detach-policy --policy-name "$POLICY_NAME" --target "$CERTARN"
fi

echo "Deleting IoT policy..."
aws iot delete-policy --policy-name "$POLICY_NAME" || echo "Policy deletion skipped or already deleted."

if [ "$CERTARN" != "None" ]; then
    echo "Detaching certificate from Thing..."
    aws iot detach-thing-principal --thing-name "$THING_NAME" --principal "$CERTARN" || true
    echo "Deactivating certificate..."
    aws iot update-certificate --certificate-id $(basename "$CERTARN") --new-status INACTIVE || true
    echo "Deleting certificate..."
    aws iot delete-certificate --certificate-id $(basename "$CERTARN") --force-delete || echo "Certificate deletion skipped."
fi

echo "Deleting IoT Thing Group..."
aws iot delete-thing-group --thing-group-name "$THING_GROUP" || echo "Thing Group deletion skipped."

echo "Deleting IoT Thing..."
aws iot delete-thing --thing-name "$THING_NAME" || echo "Thing deletion skipped."

echo "Listing policies attached to role $ROLE_NAME..."
ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text)
if [ -n "$ATTACHED_POLICIES" ]; then
    for policy in $ATTACHED_POLICIES; do
        echo "Detaching policy $policy from role $ROLE_NAME..."
        aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$policy"
    done
fi

echo "Deleting IAM role $ROLE_NAME..."
aws iam delete-role --role-name "$ROLE_NAME" || echo "Role deletion skipped."

echo "Reset complete. Please verify via the AWS console that all resources have been removed."
