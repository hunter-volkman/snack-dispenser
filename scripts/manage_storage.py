import os
import shutil
import logging
from pathlib import Path
from datetime import datetime, timedelta
import yaml

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class StorageManager:
    def __init__(self, config_path):
        with open(config_path) as f:
            self.config = yaml.safe_load(f)
        
        self.base_path = Path(self.config['local_storage']['base_path'])
    
    def cleanup_old_files(self):
        """Remove old files based on retention policy."""
        retention = self.config['retention']
        
        # Clean inference images
        self._cleanup_by_age(
            self.base_path / 'storage/inference',
            retention['inference_images_days']
        )
        
        # Clean training images if enabled
        if self.config.get('cleanup_training', False):
            self._cleanup_by_age(
                self.base_path / 'storage/training',
                retention['training_images_days']
            )
        
        # Clean temp files
        self._cleanup_by_age(
            self.base_path / 'storage/temp',
            0,
            retention['temp_files_hours']
        )
        
        # Clean old model versions
        self._cleanup_model_versions(
            retention['model_versions_count']
        )
    
    def _cleanup_by_age(self, path, days, hours=0):
        """Remove files older than specified age."""
        if not path.exists():
            return
            
        cutoff = datetime.now() - timedelta(days=days, hours=hours)
        
        for item in path.rglob('*'):
            if item.is_file():
                mtime = datetime.fromtimestamp(item.stat().st_mtime)
                if mtime < cutoff:
                    item.unlink()
                    logger.info(f"Removed old file: {item}")
    
    def _cleanup_model_versions(self, keep_versions):
        """Keep only specified number of model versions."""
        versions_path = self.base_path / 'model/versions'
        if not versions_path.exists():
            return
        
        versions = sorted(
            [d for d in versions_path.iterdir() if d.is_dir()],
            key=lambda x: x.stat().st_mtime,
            reverse=True
        )
        
        for old_version in versions[keep_versions:]:
            shutil.rmtree(old_version)
            logger.info(f"Removed old model version: {old_version}")
    
    def check_storage(self):
        """Check storage usage."""
        usage = {
            'total_size_gb': 0,
            'by_category': {}
        }
        
        for category in ['training', 'inference', 'temp', 'model']:
            path = self.base_path / ('storage' if category != 'model' else '') / category
            if path.exists():
                size = sum(f.stat().st_size for f in path.rglob('*') if f.is_file())
                usage['by_category'][category] = size / (1024 ** 3)  # Convert to GB
                usage['total_size_gb'] += usage['by_category'][category]
        
        return usage

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description='Manage storage')
    parser.add_argument('--cleanup', action='store_true', help='Clean up old files')
    parser.add_argument('--check', action='store_true', help='Check storage usage')
    
    args = parser.parse_args()
    
    manager = StorageManager('/greengrass/v2/config/storage-config.yaml')
    
    if args.cleanup:
        manager.cleanup_old_files()
    
    if args.check:
        usage = manager.check_storage()
        print("\nStorage Usage:")
        print(f"Total: {usage['total_size_gb']:.2f} GB")
        print("\nBy Category:")
        for category, size in usage['by_category'].items():
            print(f"{category}: {size:.2f} GB")