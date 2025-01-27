#!/bin/bash

# Set up Greengrass directories
sudo mkdir -p /greengrass/v2
sudo chmod 755 /greengrass
sudo chmod 755 /greengrass/v2

# Download and install Greengrass
wget https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip
unzip greengrass-nucleus-latest.zip -d GreengrassInstaller

# Install Greengrass
sudo -E java -Droot="/greengrass/v2" \
  -Dlog.store=FILE \
  -jar ./GreengrassInstaller/lib/Greengrass.jar \
  --aws-region "$AWS_REGION" \
  --thing-name "SnackBotCore" \
  --thing-group-name "SnackBotGroup" \
  --component-default-user "pi:pi" \
  --setup-system-service true