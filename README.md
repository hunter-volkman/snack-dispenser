# Intelligent Snack Dispenser on AWS Greengrass

An intelligent snack dispenser using computer vision and edge computing. Supports deployment on Greengrass. 

The demo uses a camera and a pre-trained machine learning model to detect whether a bowl is empty, publishes state updates via MQTT to AWS IoT Core, and actuates a stepper motor to dispense snacks. It also includes utilities for data collection, model training, and hardware testing.

## Features

- **Bowl State Detection:** Uses a pre-trained model to determine if the bowl is empty.
- **Motor Actuation:** Controls a stepper motor to dispense snacks when needed.
- **MQTT Messaging:** Publishes bowl state updates to AWS IoT Core.
- **Command Subscription:** Listens for remote commands to trigger dispensing.
- **Data Collection & Model Training:** Tools for capturing training data, training a classifier, and verifying model performance.
- **Hardware & System Testing:** Scripts to validate camera capture, motor control, and overall system configuration.
- **AWS Deployment:** Provisioning and deployment scripts for AWS resources and Greengrass components.

## Repository Structure
```bash
snack-dispenser
├── components
│   ├── detector
│   │   └── bowl_state_detector.py      # Detector & motor control code
│   └── recipes
│       └── com.snackdispenser.detector.bowlstate.yaml  # Greengrass component recipe
├── config
│   └── config.yaml                     # Hardware and AWS configuration
├── scripts
│   ├── test_aws.py                     # AWS & Greengrass connectivity tests
│   ├── test_hardware.py                # Camera and motor tests
│   ├── test_install.py                 # Installation verification
│   └── test_system.py                  # System resource checks
├── src
│   ├── config
│   │   └── config.yaml                 
│   ├── detector
│   │   └── bowl_state_detector.py      
│   ├── test
│   │   └── mqtt_test.py                # MQTT test component
│   └── requirements.txt                # Python dependencies
├── utils
│   ├── collect.py                      # Training data collection tool
│   ├── train.py                        # Model training script
│   └── verify.py                       # Model verification script
├── aws-setup.sh                        # AWS resource provisioning script
├── greengrass-install.sh               # AWS Greengrass Core installation script
├── greengrass-deploy.sh                # Component packaging & deployment script
└── README.md                           # Project information, etc.
```

## Getting Stared

### Prerequisites

- **AWS Account:** With permissions for IoT, IAM, and S3.
- **Hardware:** A Linux‑based device (e.g., Raspberry Pi) with a camera and stepper motor.
- **Software:** AWS CLI, Python 3, Java (OpenJDK 17 recommended), and packages listed in `requirements.txt`.

### Setup Steps

1. **AWS Resource Provisioning:**  
Configure your settings in `aws-config.sh` and run:
```bash
sudo -E ./aws-setup.sh
```

2. **Install Greengrass Core:**
Install and configure AWS Greengrass on your device:
```bash
sudo -E ./greengrass-install.sh
```

3. **Deploy the Component:**
Package and deploy the snack dispenser component to your Greengrass core:
```bash
sudo -E ./greengrass-deploy.sh
```

4. **Test the Setup:**
Run hardware and system tests:
```python
python3 scripts/test_hardware.py
python3 scripts/test_install.py
python3 scripts/test_system.py
```

## Additional Resources

- AWS Greengrass docs: https://docs.aws.amazon.com/greengrass/
- Viam docs: https://docs.viam.com/