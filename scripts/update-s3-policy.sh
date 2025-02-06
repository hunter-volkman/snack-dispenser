#!/bin/bash
# update-s3-policy.sh
# Adds S3 permissions to the Token Exchange Role

set -e
set -o pipefail

# Configuration
ROLE_NAME="SnackDispenserTokenExchangeRole"
BUCKET_NAME="edge-snack-dispenser-demo-artifacts"

# Add S3 access policy
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
                    "arn:aws:s3:::'$BUCKET_NAME'",
                    "arn:aws:s3:::'$BUCKET_NAME'/*"
                ]
            }
        ]
    }'

echo "✅ S3 access policy added to $ROLE_NAME"
echo "The role now has access to bucket: $BUCKET_NAME"