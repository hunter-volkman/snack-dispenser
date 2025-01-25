# Snack Bot - AWS Greengrass Demo

A demo project showing how to build an automated snack dispenser using AWS Greengrass, computer vision, and a Raspberry Pi. The system monitors a bowl using computer vision and automatically dispenses food when it's empty.

## Project Overview

```
snack-bot/
├── src/                        # Source code
│   ├── vision/                 # Vision processing components
│   ├── motor/                  # Motor control components
│   └── utils/                  # Shared utilities
├── scripts/                    # Setup and deployment scripts
├── config/                     # Configuration files
├── recipes/                    # Greengrass component recipes
├── tests/                      # Test suites
└── docs/                       # Documentation
```

## Key Features

- Computer vision-based bowl state detection
- Automated food dispensing via stepper motor
- AWS Greengrass component architecture
- S3 integration for model and image storage
- Local image processing at the edge

## Hardware Requirements

- Raspberry Pi 4 (2GB+ RAM recommended)
- USB Webcam (tested with Logitech C920)
- NEMA 17 Stepper Motor with DRV8825 Driver
- Power supply for motor
- Snack bowl and dispenser mechanism

## Quick Start

1. Set up AWS environment:
```bash
# Configure AWS credentials
aws configure

# Create required resources
./scripts/setup_aws.sh
```

2. Install Greengrass on Raspberry Pi:
```bash
# Run base installation
./scripts/setup_greengrass.sh

# Configure components
./scripts/configure_components.sh
```

3. Deploy components:
```bash
# Package and deploy
./scripts/deploy.sh
```

## Development Process

1. **Model Training**
   ```bash
   # Collect training data
   python src/vision/data_collector.py --label empty --samples 50
   python src/vision/data_collector.py --label full --samples 50

   # Train model
   python src/vision/model_trainer.py
   ```

2. **Component Testing**
   ```bash
   # Test vision component
   python src/vision/vision_processor.py --test

   # Test motor component
   python src/motor/motor_controller.py --test
   ```

3. **Deployment**
   ```bash
   # Create deployment package
   ./scripts/prepare_deployment.sh

   # Deploy to device
   ./scripts/deploy.sh
   ```

## Monitoring and Debugging

View component logs:
```bash
sudo tail -f /greengrass/v2/logs/com.peanutbot.vision.log
sudo tail -f /greengrass/v2/logs/com.peanutbot.motor.log
```

Check component status:
```bash
sudo greengrass-cli component list
```

## AWS Services Used

- AWS IoT Core: Device connectivity
- AWS Greengrass: Edge runtime
- Amazon S3: Storage
- IAM: Access management
- CloudWatch: Logging and monitoring

## Project Structure Details

- `src/vision/`: Computer vision and ML components
- `src/motor/`: Motor control and hardware interface
- `src/utils/`: Shared utilities and helpers
- `scripts/`: Automation and deployment scripts
- `config/`: AWS and component configurations
- `recipes/`: Greengrass component recipes
- `tests/`: Unit and integration tests
- `docs/`: Additional documentation

## Local Development

1. Set up Python environment:
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

2. Configure local settings:
```bash
cp config/local-config.template.yaml config/local-config.yaml
# Edit config/local-config.yaml with your settings
```