#!/bin/bash
set -e

echo "Setting up Viam Agent for Edge Snack Dispenser..."

# Download and install the Viam Agent
curl -fsSL https://get.viam.com/install | sh

# (Optional) Start the Viam Agent using a configuration file (viam.json)
viam-server --config viam.json &

echo "Viam Agent installed and started. Configure your device on the Viam portal."
