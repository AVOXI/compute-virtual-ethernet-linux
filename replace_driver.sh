#!/bin/bash
# A script to replace the gve driver without losing SSH access permanently.

set -e # Exit immediately if any command fails

# --- CONFIGURATION ---
INTERFACE="ens3"
NEW_DRIVER_PATH="/home/mehmetozgul/compute-virtual-ethernet-linux/build/gve.ko"
# --- END CONFIGURATION ---

echo "Starting gve driver replacement for ${INTERFACE} in 3 seconds..."
sleep 3

# Unload the old driver and load the new one
rmmod gve
insmod "${NEW_DRIVER_PATH}"

# Bring the interface back up and renew the IP address
ip link set dev "${INTERFACE}" up
dhclient -r "${INTERFACE}" && dhclient "${INTERFACE}"

echo "Driver replacement complete. Network should be back online."
