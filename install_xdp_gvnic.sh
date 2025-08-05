#!/bin/bash
# 
# GVnic XDP Driver Installation Script
# This script builds and installs the modified gvnic driver with XDP support
#

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INTERFACE=${1:-$(ip route get 8.8.8.8 | grep -oP 'dev \K\w+')}
BACKUP_DIR="/tmp/gve_backup_$(date +%Y%m%d_%H%M%S)"

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE} GVnic XDP Driver Installation Script${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_requirements() {
    print_status "Checking requirements..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Check if coccinelle is installed
    if ! command -v spatch &> /dev/null; then
        print_warning "Coccinelle not found. Installing..."
        apt update && apt install -y coccinelle
    fi
    
    # Check if kernel headers are available
    if [[ ! -d "/lib/modules/$(uname -r)/build" ]]; then
        print_error "Kernel headers not found. Please install linux-headers-$(uname -r)"
        exit 1
    fi
    
    # Check network interface
    if ! ip link show "$INTERFACE" &> /dev/null; then
        print_error "Network interface $INTERFACE not found"
        print_status "Available interfaces:"
        ip link show | grep -E '^[0-9]+:' | cut -d: -f2 | tr -d ' '
        exit 1
    fi
    
    print_status "Requirements check passed ✓"
}

backup_current_driver() {
    print_status "Creating backup of current driver..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup driver info
    modinfo gve > "$BACKUP_DIR/original_driver_info.txt" 2>/dev/null || true
    
    # Backup network configuration
    ip addr show "$INTERFACE" > "$BACKUP_DIR/interface_config.txt"
    ip route show > "$BACKUP_DIR/routes.txt"
    
    print_status "Backup created at: $BACKUP_DIR"
}

build_driver() {
    print_status "Building modified gvnic driver..."
    
    # Clean previous build
    if [[ -d "build" ]]; then
        rm -rf build
    fi
    
    # Build with compatibility patches
    ./build_src.sh --target=oot
    
    # Compile the driver
    make -C /lib/modules/$(uname -r)/build M=$(pwd)/build modules
    
    # Verify build
    if [[ ! -f "build/gve.ko" ]]; then
        print_error "Driver build failed - gve.ko not found"
        exit 1
    fi
    
    # Check module info
    local version=$(modinfo build/gve.ko | grep "^version:" | cut -d: -f2 | tr -d ' ')
    local xdp_param=$(modinfo build/gve.ko | grep force_gqi_qpl | cut -d: -f2)
    
    print_status "Driver built successfully ✓"
    print_status "Version: $version"
    print_status "XDP Parameter: $xdp_param"
}

install_driver() {
    print_status "Installing modified driver..."
    
    # Show current driver info
    print_status "Current driver:"
    ethtool -i "$INTERFACE" | grep -E "(driver|version)"
    
    print_warning "Network will be briefly interrupted during driver replacement..."
    print_warning "Starting in 5 seconds... Press Ctrl+C to cancel"
    sleep 5
    
    # Remove old driver
    print_status "Unloading current driver..."
    rmmod gve || true
    
    # Install new driver
    print_status "Loading modified driver..."
    insmod build/gve.ko
    
    # Restart network interface
    print_status "Restarting network interface..."
    ip link set dev "$INTERFACE" down
    ip link set dev "$INTERFACE" up
    
    # Renew DHCP lease
    print_status "Renewing DHCP lease..."
    dhclient -r "$INTERFACE" 2>/dev/null || true
    dhclient "$INTERFACE"
    
    print_status "Driver installation completed ✓"
}

verify_installation() {
    print_status "Verifying installation..."
    
    # Check driver is loaded
    if ! lsmod | grep -q gve; then
        print_error "Driver not loaded"
        return 1
    fi
    
    # Check interface is up
    if ! ip link show "$INTERFACE" | grep -q "UP"; then
        print_error "Interface is not up"
        return 1
    fi
    
    # Check connectivity
    if ! ping -c 1 -W 5 8.8.8.8 &> /dev/null; then
        print_warning "No internet connectivity - this may be normal"
    else
        print_status "Internet connectivity verified ✓"
    fi
    
    # Show driver details
    echo
    print_status "Installation verification:"
    echo -e "${BLUE}Driver Version:${NC}"
    modinfo gve | grep -E "(version|description)"
    
    echo -e "${BLUE}XDP Parameter:${NC}"
    modinfo gve | grep force_gqi_qpl
    
    echo -e "${BLUE}Queue Format:${NC}"
    dmesg | grep "queue format" | tail -1
    
    echo -e "${BLUE}Interface Status:${NC}"
    ip addr show "$INTERFACE" | head -5
    
    print_status "Verification completed ✓"
}

show_usage() {
    echo "Usage: $0 [interface_name]"
    echo
    echo "This script will:"
    echo "  1. Check requirements and dependencies"
    echo "  2. Backup current driver configuration"  
    echo "  3. Build the modified gvnic driver with XDP support"
    echo "  4. Safely install the new driver"
    echo "  5. Verify the installation"
    echo
    echo "Arguments:"
    echo "  interface_name    Network interface to configure (auto-detected if not provided)"
    echo
    echo "Examples:"
    echo "  sudo $0              # Auto-detect interface"
    echo "  sudo $0 ens3         # Use specific interface"
    echo
}

main() {
    # Handle help
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_usage
        exit 0
    fi
    
    print_header
    
    print_status "Target interface: $INTERFACE"
    echo
    
    # Execute installation steps
    check_requirements
    backup_current_driver
    build_driver
    install_driver
    verify_installation
    
    echo
    print_status "🎉 Installation completed successfully!"
    echo
    print_status "Next steps:"
    echo "  • Test XDP functionality with your XDP programs"
    echo "  • Check XDP_GVNIC_GUIDE.md for usage examples"
    echo "  • Backup location: $BACKUP_DIR"
    echo
    print_status "To disable XDP compatibility (if needed):"
    echo "  sudo rmmod gve && sudo insmod build/gve.ko force_gqi_qpl=0"
    echo
}

# Trap Ctrl+C
trap 'print_warning "\nInstallation cancelled by user"; exit 1' INT

# Run main function
main "$@"