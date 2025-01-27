import boto3
import os
import logging
from pathlib import Path
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class StorageSync:
    def __init__(self, local_base, bucket_name, prefix):
        self.local_base = Path(local_base)
        self.bucket_name = bucket_name
        self.prefix = prefix
        self.s3_client = boto3.client('s3')
    
    def sync_to_s3(self, subfolder):
        """Sync local directory to S3."""
        local_path = self.local_base / 'storage' / subfolder
        if not local_path.exists():
            logger.warning(f"Local path does not exist: {local_path}")
            return
        
        for file_path in local_path.rglob('*'):
            if file_path.is_file():
                relative_path = file_path.relative_to(local_path)
                s3_key = f"{self.prefix}{subfolder}/{relative_path}"
                
                try:
                    self.s3_client.upload_file(
                        str(file_path),
                        self.bucket_name,
                        s3_key
                    )
                    logger.info(f"Uploaded {file_path} to s3://{self.bucket_name}/{s3_key}")
                except Exception as e:
                    logger.error(f"Error uploading {file_path}: {e}")
    
    def sync_from_s3(self, subfolder):
        """Sync from S3 to local directory."""
        try:
            paginator = self.s3_client.get_paginator('list_objects_v2')
            prefix = f"{self.prefix}{subfolder}/"
            
            for page in paginator.paginate(
                Bucket=self.bucket_name,
                Prefix=prefix
            ):
                for obj in page.get('Contents', []):
                    s3_key = obj['Key']
                    relative_path = s3_key[len(prefix):]
                    local_path = self.local_base / 'storage' / subfolder / relative_path
                    
                    local_path.parent.mkdir(parents=True, exist_ok=True)
                    
                    self.s3_client.download_file(
                        self.bucket_name,
                        s3_key,
                        str(local_path)
                    )
                    logger.info(f"Downloaded s3://{self.bucket_name}/{s3_key}")
                    
        except Exception as e:
            logger.error(f"Error syncing from S3: {e}")

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description='Sync storage with S3')
    parser.add_argument('--direction', choices=['to_s3', 'from_s3'], required=True)
    parser.add_argument('--folder', choices=['training', 'inference', 'all'], required=True)
    
    args = parser.parse_args()
    
    sync = StorageSync(
        '/greengrass/v2/work/com.snackbot.vision',
        'snack-bot-data',
        'snack-bot/'
    )
    
    folders = ['training', 'inference'] if args.folder == 'all' else [args.folder]
    
    for folder in folders:
        if args.direction == 'to_s3':
            sync.sync_to_s3(folder)
        else:
            sync.sync_from_s3(folder)