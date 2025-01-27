import os
import yaml
import logging
from pathlib import Path
import boto3

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def validate_local_structure(base_path):
    """Validate local directory structure."""
    required_dirs = [
        'storage/training/empty',
        'storage/training/full',
        'storage/inference',
        'storage/temp',
        'model/current',
        'model/versions'
    ]
    
    missing = []
    for dir_path in required_dirs:
        full_path = Path(base_path) / dir_path
        if not full_path.exists():
            missing.append(dir_path)
    
    return len(missing) == 0, missing

def validate_permissions(base_path):
    """Validate directory permissions."""
    issues = []
    
    for root, dirs, files in os.walk(base_path):
        for d in dirs:
            path = Path(root) / d
            if path.stat().st_mode & 0o777 != 0o755:
                issues.append(f"Directory permission issue: {path}")
    
    return len(issues) == 0, issues

def validate_s3_access(bucket, prefix):
    """Validate S3 bucket access."""
    s3 = boto3.client('s3')
    try:
        s3.list_objects_v2(
            Bucket=bucket,
            Prefix=prefix,
            MaxKeys=1
        )
        return True, None
    except Exception as e:
        return False, str(e)

def main():
    # Load config
    with open('/greengrass/v2/config/storage-config.yaml') as f:
        config = yaml.safe_load(f)
    
    base_path = config['local_storage']['base_path']
    
    print("Running storage validation...")
    
    # Check local structure
    print("\n1. Checking local directory structure...")
    structure_ok, missing_dirs = validate_local_structure(base_path)
    if structure_ok:
        print("✓ Local directory structure is valid")
    else:
        print("✗ Missing directories:")
        for dir_path in missing_dirs:
            print(f"  - {dir_path}")
    
    # Check permissions
    print("\n2. Checking permissions...")
    perms_ok, perm_issues = validate_permissions(base_path)
    if perms_ok:
        print("✓ All permissions are correct")
    else:
        print("✗ Permission issues found:")
        for issue in perm_issues:
            print(f"  - {issue}")
    
    # Check S3 access
    print("\n3. Checking S3 access...")
    s3_ok, s3_error = validate_s3_access(
        config['s3_storage']['bucket'],
        config['s3_storage']['prefix']
    )
    if s3_ok:
        print("✓ S3 access is working")
    else:
        print(f"✗ S3 access error: {s3_error}")
    
    # Overall status
    print("\nOverall Status:", end=" ")
    if all([structure_ok, perms_ok, s3_ok]):
        print("✓ All checks passed")
    else:
        print("✗ Some checks failed")

if __name__ == "__main__":
    main()