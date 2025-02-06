#!/bin/bash
# fix-s3-permissions.sh
# Adds required S3 permissions to Token Exchange Role

set -e
set -o pipefail

# Configuration
ROLE_NAME="SnackDispenserTokenExchangeRole"
S3_BUCKET="edge-snack-dispenser-demo-artifacts"

echo "Adding S3 permissions to $ROLE_NAME..."

# Create S3 access policy
aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "GreengrassS3ComponentArtifactAccess" \
    --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "s3:GetObject",
                    "s3:ListBucket"
                ],
                "Resource": [
                    "arn:aws:s3:::'$S3_BUCKET'",
                    "arn:aws:s3:::'$S3_BUCKET'/*"
                ]
            }
        ]
    }'

echo "✅ S3 permissions added successfully"
echo "You can now try deploying your component again"