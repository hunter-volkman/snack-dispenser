#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Update system
apt-get update && apt-get upgrade -y

# Install basic dependencies
apt-get install -y \
  git \
  python3 \
  python3-pip \
  python3-venv \
  python3-opencv \
  default-jdk
