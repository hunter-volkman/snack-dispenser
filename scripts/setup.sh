#!/bin/bash
set -e  # Exit on any error

echo "🤖 Setting up Snack Bot Demo..."

# Function to check if running on Raspberry Pi
check_raspberry_pi() {
    if ! grep -q "Raspberry Pi" /proc/cpuinfo; then
        echo "❌ This script must be run on a Raspberry Pi"
        exit 1
    fi
}

# Function to check network connectivity
check_network() {
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        echo "❌ No internet connection"
        exit 1
    fi
}

# Install system dependencies
install_system_deps() {
    echo "📦 Installing system dependencies..."
    sudo apt-get update
    sudo apt-get install -y \
        python3-pip \
        python3-venv \
        python3-opencv \
        v4l-utils \
        git \
        cmake \
        python3-rpi.gpio \
        fswebcam
}

# Install additional utilities
install_additional_utils() {
    echo "📦 Installing additonal utilities..."
    sudo apt install -y \
        vim \
        htop \
        tmux \
        tree
}

# Set up Python virtual environment
setup_python_env() {
    echo "🐍 Setting up Python environment..."
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
}

# Test camera
test_camera() {
    echo "📸 Testing camera..."
    if ! ls /dev/video0 &> /dev/null; then
        echo "❌ No camera detected"
        exit 1
    fi
    
    # Capture test image
    fswebcam -r 1280x720 --no-banner test_capture.jpg
    if [ ! -f test_capture.jpg ]; then
        echo "❌ Failed to capture test image"
        exit 1
    fi
    echo "✅ Camera test successful"
}

# Test GPIO
test_gpio() {
    echo "🔌 Testing GPIO..."
    python3 - <<EOF
import RPi.GPIO as GPIO
GPIO.setmode(GPIO.BOARD)
GPIO.setup(12, GPIO.OUT)
GPIO.cleanup()
EOF
    if [ $? -ne 0 ]; then
        echo "❌ GPIO test failed"
        exit 1
    fi
    echo "✅ GPIO test successful"
}

<<COMMENT
# Create project structure
create_project_structure() {
    echo "📁 Creating project structure..."
    mkdir -p config/greengrass
    mkdir -p src/{vision,motor}
    mkdir -p data/{training/{empty,full},model}
    mkdir -p tests
}
COMMENT

# Main setup flow
main() {
    echo "Starting setup..."
    check_raspberry_pi
    check_network
    install_system_deps
    install_additional_utils
    # create_project_structure
    setup_python_env
    test_camera
    test_gpio
    echo "✅ Setup completed successfully!"
    echo "📝 Next steps:"
    echo "1. Run 'source venv/bin/activate' to activate the Python environment"
    echo "2. Edit config/config.yaml with your settings"
    echo "3. Run 'python src/vision/collect.py' to start collecting training data"
}

main