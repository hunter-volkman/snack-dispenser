#!/bin/bash
# aws-setup.sh
# Sets up all required AWS resources for Greengrass deployment
# Handles: AWS credentials, IAM roles, Token Exchange, IoT Thing, Certificates

set -e
set -o pipefail

# Configuration
THING_NAME="SnackDispenserCore"
THING_GROUP="SnackDispenserGroup"
REGION="us-east-1"
IOT_POLICY_NAME="SnackDispenserIoTPolicy"
TOKEN_EXCHANGE_ROLE_NAME="GreengrassV2TokenExchangeRole"
TOKEN_EXCHANGE_ALIAS="GreengrassV2TokenExchangeAlias"
S3_BUCKET="edge-snack-dispenser-demo-artifacts"
CERTS_DIR="certificates"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
INFO="${GREEN}[INFO]${NC}"
WARN="${YELLOW}[WARN]${NC}"
ERROR="${RED}[ERROR]${NC}"

# Functions for resource creation and checks
check_aws_credentials() {
    echo -e "${INFO} Checking AWS credentials..."
    if ! aws sts get-caller-identity &>/dev/null; then
        echo -e "${ERROR} AWS credentials not configured!"
        echo "Please run 'aws configure' with appropriate credentials."
        echo "Required permissions:"
        echo "  - iam:CreateRole"
        echo "  - iam:PutRolePolicy"
        echo "  - iam:DeleteRolePolicy"
        echo "  - iam:GetRole"
        echo "  - iot:CreateThing"
        echo "  - iot:CreatePolicy"
        echo "  - iot:CreateKeysAndCertificate"
        echo "  - s3:CreateBucket"
        echo "  - s3:PutBucketPolicy"
        echo "  - s3:PutBucketOwnershipControls"
        echo "  - s3:PutPublicAccessBlock"
        exit 1
    fi
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo -e "${INFO} Using AWS Account: ${AWS_ACCOUNT_ID}"
}

create_iam_role() {
    echo -e "${INFO} Creating Token Exchange IAM Role..."
    
    # Create role if it doesn't exist
    if ! aws iam get-role --role-name "$TOKEN_EXCHANGE_ROLE_NAME" &>/dev/null; then
        aws iam create-role \
            --role-name "$TOKEN_EXCHANGE_ROLE_NAME" \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [{
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "credentials.iot.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }]
            }'
        
        echo -e "${INFO} Attaching policies to IAM role..."
        # Attach required Greengrass policy
        aws iam attach-role-policy \
            --role-name "$TOKEN_EXCHANGE_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/GreengrassV2TokenExchangeRoleAccess"
    else
        echo -e "${WARN} IAM role already exists, checking policies..."
    fi

    # Delete existing policies to ensure clean slate
    echo -e "${INFO} Cleaning up existing policies..."
    aws iam delete-role-policy \
        --role-name "$TOKEN_EXCHANGE_ROLE_NAME" \
        --policy-name "GreengrassS3ComponentAccess" 2>/dev/null || true
    aws iam delete-role-policy \
        --role-name "$TOKEN_EXCHANGE_ROLE_NAME" \
        --policy-name "GreengrassS3FullAccess" 2>/dev/null || true
    
    # Add updated S3 access policy
    echo -e "${INFO} Adding S3 access policy..."
    aws iam put-role-policy \
        --role-name "$TOKEN_EXCHANGE_ROLE_NAME" \
        --policy-name "GreengrassS3FullAccess" \
        --policy-document "{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Effect\": \"Allow\",
                    \"Action\": [
                        \"s3:GetBucketLocation\",
                        \"s3:GetObject\",
                        \"s3:ListBucket\",
                        \"s3:ListAllMyBuckets\",
                        \"s3:GetObjectVersion\"
                    ],
                    \"Resource\": [
                        \"arn:aws:s3:::*\",
                        \"arn:aws:s3:::${S3_BUCKET}\",
                        \"arn:aws:s3:::${S3_BUCKET}/*\"
                    ]
                }
            ]
        }"
}

setup_s3_bucket() {
    echo -e "${INFO} Setting up S3 bucket..."
    
    # Create bucket if it doesn't exist
    if ! aws s3 ls "s3://${S3_BUCKET}" 2>&1 > /dev/null; then
        echo -e "${INFO} Creating new S3 bucket..."
        aws s3 mb "s3://${S3_BUCKET}" --region "$REGION"
    else
        echo -e "${WARN} S3 bucket already exists"
    fi

    # Set up bucket ownership controls
    echo -e "${INFO} Setting up bucket ownership controls..."
    aws s3api put-bucket-ownership-controls \
        --bucket "$S3_BUCKET" \
        --ownership-controls Rules=[{ObjectOwnership=BucketOwnerPreferred}]

    # Set up public access block
    echo -e "${INFO} Configuring public access block..."
    aws s3api put-public-access-block \
        --bucket "$S3_BUCKET" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

    # Update bucket policy
    echo -e "${INFO} Updating bucket policy..."
    aws s3api put-bucket-policy \
        --bucket "$S3_BUCKET" \
        --policy "{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Sid\": \"GreengrassAccess\",
                    \"Effect\": \"Allow\",
                    \"Principal\": {
                        \"AWS\": \"*\"
                    },
                    \"Action\": [
                        \"s3:GetObject\",
                        \"s3:GetBucketLocation\",
                        \"s3:ListBucket\"
                    ],
                    \"Resource\": [
                        \"arn:aws:s3:::${S3_BUCKET}\",
                        \"arn:aws:s3:::${S3_BUCKET}/*\"
                    ],
                    \"Condition\": {
                        \"StringEquals\": {
                            \"aws:PrincipalArn\": \"arn:aws:iam::${AWS_ACCOUNT_ID}:role/${TOKEN_EXCHANGE_ROLE_NAME}\"
                        }
                    }
                }
            ]
        }"
}

verify_s3_permissions() {
    echo -e "${INFO} Verifying S3 permissions..."
    
    # Test bucket access
    if ! aws s3api get-bucket-location --bucket "$S3_BUCKET" &>/dev/null; then
        echo -e "${WARN} S3 permissions not yet propagated. Waiting..."
        sleep 10
        if ! aws s3api get-bucket-location --bucket "$S3_BUCKET" &>/dev/null; then
            echo -e "${ERROR} S3 permissions verification failed. This might take a few minutes to propagate."
            echo "You can proceed with setup and retry the deployment in a few minutes."
        fi
    else
        echo -e "${INFO} S3 permissions verified successfully"
    fi
}

create_token_exchange_role_alias() {
    echo -e "${INFO} Creating Token Exchange Role Alias..."
    
    ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${TOKEN_EXCHANGE_ROLE_NAME}"
    
    if ! aws iot describe-role-alias --role-alias "$TOKEN_EXCHANGE_ALIAS" &>/dev/null; then
        aws iot create-role-alias \
            --role-alias "$TOKEN_EXCHANGE_ALIAS" \
            --role-arn "$ROLE_ARN" \
            --credential-duration-seconds 3600
    else
        echo -e "${WARN} Role alias already exists, skipping creation"
    fi
}

create_iot_policy() {
    echo -e "${INFO} Creating IoT Policy..."
    
    if ! aws iot get-policy --policy-name "$IOT_POLICY_NAME" &>/dev/null; then
        aws iot create-policy \
            --policy-name "$IOT_POLICY_NAME" \
            --policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Action": [
                            "iot:Connect",
                            "iot:Publish",
                            "iot:Subscribe",
                            "iot:Receive",
                            "greengrass:*"
                        ],
                        "Resource": "*"
                    },
                    {
                        "Effect": "Allow",
                        "Action": "iot:AssumeRoleWithCertificate",
                        "Resource": "*"
                    }
                ]
            }'
    else
        echo -e "${WARN} IoT policy already exists, skipping creation"
    fi
}

create_iot_thing() {
    echo -e "${INFO} Creating IoT Thing and Thing Group..."
    
    # Create Thing Group if it doesn't exist
    if ! aws iot describe-thing-group --thing-group-name "$THING_GROUP" &>/dev/null; then
        aws iot create-thing-group --thing-group-name "$THING_GROUP"
    fi
    
    # Create Thing if it doesn't exist
    if ! aws iot describe-thing --thing-name "$THING_NAME" &>/dev/null; then
        aws iot create-thing --thing-name "$THING_NAME"
        echo -e "${INFO} Adding thing to group..."
        aws iot add-thing-to-thing-group \
            --thing-name "$THING_NAME" \
            --thing-group-name "$THING_GROUP"
    else
        echo -e "${WARN} IoT Thing already exists, skipping creation"
    fi
}

generate_certificates() {
    echo -e "${INFO} Generating certificates..."
    
    # Create certificates directory
    mkdir -p "$CERTS_DIR"
    
    # Generate certificates
    CERT_ARN=$(aws iot create-keys-and-certificate --set-as-active \
        --certificate-pem-outfile "${CERTS_DIR}/device.pem.crt" \
        --private-key-outfile "${CERTS_DIR}/private.pem.key" \
        --public-key-outfile "${CERTS_DIR}/public.pem.key" \
        --query 'certificateArn' --output text)
    
    # Download root CA
    curl -s https://www.amazontrust.com/repository/AmazonRootCA1.pem \
        -o "${CERTS_DIR}/root.ca.pem"
    
    # Attach policy to certificate
    aws iot attach-policy --policy-name "$IOT_POLICY_NAME" --target "$CERT_ARN"
    
    # Attach certificate to thing
    aws iot attach-thing-principal --thing-name "$THING_NAME" --principal "$CERT_ARN"
    
    echo -e "${INFO} Certificates generated in ${CERTS_DIR}/"
    echo -e "${INFO} Certificate ARN: ${CERT_ARN}"
}

save_config() {
    echo -e "${INFO} Saving configuration..."
    
    CONFIG_FILE="greengrass-config.json"
    cat > "$CONFIG_FILE" << EOF
{
    "thingName": "${THING_NAME}",
    "thingGroup": "${THING_GROUP}",
    "region": "${REGION}",
    "tokenExchangeRole": "${TOKEN_EXCHANGE_ROLE_NAME}",
    "tokenExchangeAlias": "${TOKEN_EXCHANGE_ALIAS}",
    "certsDir": "${CERTS_DIR}",
    "accountId": "${AWS_ACCOUNT_ID}",
    "s3Bucket": "${S3_BUCKET}"
}
EOF
    echo -e "${INFO} Configuration saved to ${CONFIG_FILE}"
}

# Main execution
main() {
    echo "🚀 Setting up AWS resources for Greengrass..."
    
    # Check AWS credentials first
    check_aws_credentials
    
    # Create resources in order
    create_iam_role
    setup_s3_bucket
    verify_s3_permissions
    create_token_exchange_role_alias
    create_iot_policy
    create_iot_thing
    generate_certificates
    save_config
    
    echo -e "\n${GREEN}✅ AWS setup completed successfully!${NC}"
    echo -e "${INFO} Next steps:"
    echo "1. Run greengrass-install.sh to install Greengrass core"
    echo "2. Use component-deploy.sh to deploy your components"
    echo ""
    echo "Important files:"
    echo "- ${CERTS_DIR}/        : Contains all certificates"
    echo "- greengrass-config.json: Configuration for other scripts"
}

# Run main function
main