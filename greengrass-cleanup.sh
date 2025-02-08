#!/bin/bash
# greengrass-cleanup.sh
# Completely removes AWS Greengrass core, deployed components, and associated resources

set -e
set -o pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
INFO="${GREEN}[INFO]${NC}"
WARN="${YELLOW}[WARN]${NC}"
ERROR="${RED}[ERROR]${NC}"

# Constants
GREENGRASS_ROOT="/greengrass/v2"
CONFIG_FILE="greengrass-config.json"
DEPLOYMENTS_DIR="$GREENGRASS_ROOT/deployments"
S3_BUCKET="edge-snack-dispenser-demo-artifacts"

# Check root privileges
if [ "$EUID" -ne 0 ]; then
    echo -e "${ERROR} Please run as root (sudo -E $0)"
    exit 1
fi

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${ERROR} Configuration file $CONFIG_FILE not found! Cannot proceed."
    exit 1
fi

# Load config values
THING_NAME=$(jq -r '.thingName' "$CONFIG_FILE")
REGION=$(jq -r '.region' "$CONFIG_FILE")
AWS_ACCOUNT_ID=$(jq -r '.accountId' "$CONFIG_FILE")

# Stop and remove Greengrass service
remove_service() {
    echo -e "${INFO} Stopping and removing Greengrass service..."
    
    if systemctl is-active --quiet greengrass.service; then
        systemctl stop greengrass.service
    fi

    if systemctl is-enabled --quiet greengrass.service; then
        systemctl disable greengrass.service
    fi

    if [ -f "/etc/systemd/system/greengrass.service" ]; then
        rm -f "/etc/systemd/system/greengrass.service"
        systemctl daemon-reload
    fi
}

# Remove deployed Greengrass components and configurations
remove_deployments() {
    echo -e "${INFO} Removing Greengrass components and deployments..."

    COMPONENTS=$(aws greengrassv2 list-installed-components \
        --core-device-thing-name "$THING_NAME" \
        --region "$REGION" \
        --query 'components[].componentName' \
        --output text)

    for component in $COMPONENTS; do
        echo -e "${INFO} Removing component: $component"
        aws greengrassv2 delete-component \
            --arn "arn:aws:greengrass:${REGION}:${AWS_ACCOUNT_ID}:components:$component" \
            --region "$REGION"
    done

    aws greengrassv2 delete-core-device \
        --core-device-thing-name "$THING_NAME" \
        --region "$REGION"

    if [ -d "$DEPLOYMENTS_DIR" ]; then
        rm -rf "$DEPLOYMENTS_DIR"
    fi
}

# Remove IoT Thing, certificates, and policies
remove_iot_resources() {
    echo -e "${INFO} Removing IoT Thing and associated resources..."

    CERT_ARN=$(aws iot list-thing-principals --thing-name "$THING_NAME" --query 'principals[0]' --output text)

    if [ "$CERT_ARN" != "None" ]; then
        CERT_ID=$(basename "$CERT_ARN")
        aws iot detach-thing-principal --thing-name "$THING_NAME" --principal "$CERT_ARN"
        aws iot update-certificate --certificate-id "$CERT_ID" --new-status INACTIVE
        aws iot delete-certificate --certificate-id "$CERT_ID" --force-delete
    fi

    POLICY_NAME=$(aws iot list-attached-policies --target "$CERT_ARN" --query 'policies[0].policyName' --output text)
    if [ "$POLICY_NAME" != "None" ]; then
        aws iot detach-policy --policy-name "$POLICY_NAME" --target "$CERT_ARN"
        aws iot delete-policy --policy-name "$POLICY_NAME"
    fi

    aws iot delete-thing --thing-name "$THING_NAME"
}

# Remove S3 bucket and component artifacts
remove_s3_bucket() {
    echo -e "${INFO} Removing S3 bucket and uploaded artifacts..."
    
    if aws s3 ls "s3://$S3_BUCKET" >/dev/null 2>&1; then
        aws s3 rm "s3://$S3_BUCKET" --recursive
        aws s3 rb "s3://$S3_BUCKET"
        echo -e "${INFO} S3 bucket $S3_BUCKET deleted."
    else
        echo -e "${WARN} S3 bucket $S3_BUCKET does not exist or is already deleted."
    fi
}

# Remove Greengrass directories and files
remove_greengrass_files() {
    echo -e "${INFO} Removing Greengrass directories and files..."

    if pgrep -f "greengrass" > /dev/null; then
        pkill -f "greengrass"
        sleep 5
    fi

    if [ -d "$GREENGRASS_ROOT" ]; then
        rm -rf "$GREENGRASS_ROOT"
    fi
}

# Remove system user and group
remove_system_user() {
    echo -e "${INFO} Removing system user and group..."

    if id -u ggc_user > /dev/null 2>&1; then
        userdel ggc_user
    fi

    if getent group ggc_group > /dev/null; then
        groupdel ggc_group
    fi
}

# Clean up dependencies (optional)
cleanup_dependencies() {
    echo -e "${WARN} Do you want to remove installed dependencies (Java, Python3-pip, jq, unzip)? [y/N]"
    read -r response

    if [[ "$response" =~ ^[Yy]$ ]]; then
        apt-get remove -y openjdk-17-jre-headless python3-pip jq unzip
        apt-get autoremove -y
    else
        echo -e "${INFO} Skipping dependency removal"
    fi
}

# Verify uninstallation
verify_uninstallation() {
    echo -e "${INFO} Verifying uninstallation..."
    local errors=0

    if systemctl list-unit-files | grep -q "greengrass.service"; then
        echo -e "${ERROR} Greengrass service still exists"
        errors=$((errors + 1))
    fi

    if pgrep -f "greengrass" > /dev/null; then
        echo -e "${ERROR} Greengrass processes still running"
        errors=$((errors + 1))
    fi

    if [ -d "$GREENGRASS_ROOT" ]; then
        echo -e "${ERROR} Greengrass directory still exists"
        errors=$((errors + 1))
    fi

    if aws iot describe-thing --thing-name "$THING_NAME" >/dev/null 2>&1; then
        echo -e "${ERROR} IoT Thing $THING_NAME still exists"
        errors=$((errors + 1))
    fi

    if aws s3 ls "s3://$S3_BUCKET" >/dev/null 2>&1; then
        echo -e "${ERROR} S3 bucket $S3_BUCKET still exists"
        errors=$((errors + 1))
    fi

    return $errors
}

# Main uninstallation process
main() {
    echo "\ud83e\uddf9 Uninstalling AWS Greengrass Core and components..."

    echo -e "${WARN} This will completely remove Greengrass, deployed components, and AWS IoT resources. Continue? [y/N]"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo -e "${INFO} Uninstallation cancelled"
        exit 0
    fi

    remove_service
    remove_deployments
    remove_iot_resources
    remove_s3_bucket
    remove_greengrass_files
    remove_system_user
    cleanup_dependencies

    if verify_uninstallation; then
        echo -e "\n${GREEN}\u2705 Greengrass uninstallation completed successfully!${NC}"
    else
        echo -e "\n${WARN} Uninstallation completed with warnings. Please check the messages above."
    fi

    echo -e "${INFO} System cleaned. You can now run greengrass-install.sh again if desired."
}

# Run main function
main
