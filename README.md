# Edge Snack Dispenser

An intelligent snack dispenser using computer vision and edge computing. Supports deployment on AWS Greengrass, Azure IoT Edge, or Viam.

## Features

- Computer vision-powered bowl state detection
- Automated snack dispensing via stepper motor
- Multi-cloud deployment options:
  - AWS Greengrass components
  - Azure IoT Edge modules
  - Viam standalone or as control plane
- Real-time monitoring and remote control

## Requirements

### Hardware
- Raspberry Pi 4 (2GB+ RAM)
- USB Camera (tested with Logitech C920)
- NEMA 17 Stepper Motor + DRV8825 Driver
- 12V Power Supply
- Snack bowl and dispenser mechanism

### Software
- Raspberry Pi OS (64-bit)
- Python 3.7+
- AWS CLI, Azure CLI, or Viam CLI (based on deployment)

## Quick Start

1. Clone and setup:
```bash
git clone https://github.com/yourusername/edge-snack-dispenser.git
cd edge-snack-dispenser
./scripts/setup.sh
```

2. Test hardware:
```bash
python3 tests/test_hardware.py
```

3. Choose deployment platform:

AWS Greengrass:
```bash
./scripts/setup_aws.sh
./scripts/deploy_component_aws.sh
```

Azure IoT Edge:
```bash
./scripts/setup_azure.sh
./scripts/deploy_module_azure.sh
```

Viam:
```bash
./scripts/setup_viam.sh
```

## Project Structure
```
edge-snack-dispenser/
├── aws/                # AWS Greengrass implementation
├── azure/              # Azure IoT Edge implementation
├── viam/               # Viam integration
├── common/             # Shared code
│   ├── hardware/       # Hardware abstraction
│   ├── vision/         # ML/vision code
│   └── config/         # Configuration
├── docs/               # Documentation
├── scripts/            # Setup & deployment
├── tests/              # Test suites
├── utils/              # Training utilities
└── data/               # Training data & models
```

## Development

### Train Vision Model
```bash
# Collect training data
python3 utils/collect.py --label empty --samples 20
python3 utils/collect.py --label full --samples 20

# Train model
python3 utils/train.py

# Verify model
python3 utils/verify.py --live
```

### Test Components
```bash
# Run test suite
python3 -m pytest tests/

# Hardware tests
python3 tests/test_hardware.py
```

### Monitoring

AWS Greengrass:
```bash
sudo tail -f /greengrass/v2/logs/com.edgesnackdispenser.core.log
```

Azure IoT Edge:
```bash
iotedge logs edgesnackdispenser
```

Viam:
- Monitor via Viam web interface

## Documentation

- [Setup Guide](docs/SETUP.md)
- [Code Documentation](docs/CODE.md)
- [AWS Greengrass Guide](docs/AWS_GREENGRASS.md)
- [Azure IoT Edge Guide](docs/AZURE.md)
- [Viam Integration](docs/VIAM.md)

## Contributing

1. Fork repository
2. Create feature branch
3. Follow code style guide
4. Submit pull request

## License

MIT License - See LICENSE file

## Support

- Report issues on GitHub
- AWS Greengrass docs: [Link]
- Azure IoT Edge docs: [Link]
- Viam docs: [Link]