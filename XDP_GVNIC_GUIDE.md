# GVnic Driver XDP Native Support - Installation and Usage Guide

## Overview

This is a modified version of Google's gvnic (Google Virtual Ethernet) driver that enables native XDP (eXpress Data Path) support. The original driver had queue format compatibility issues that prevented XDP modules from loading. This modified version resolves those issues by intelligently selecting the correct queue format for XDP compatibility.

## What Was Fixed

### Problem
The original gvnic driver had two main issues preventing XDP from working:

1. **Queue Format Priority**: The driver prioritized newer queue formats (DQO_RDA, DQO_QPL, GQI_RDA) over GQI_QPL, but XDP only works with GQI_QPL format
2. **Poor Error Messages**: When XDP failed, the driver provided unhelpful error messages without guidance on how to fix the issue

### Solution
Our modifications include:

1. **Smart Queue Format Selection**: Added `force_gqi_qpl` parameter (default: enabled) to prioritize GQI_QPL format for XDP compatibility
2. **Enhanced Error Messages**: Clear, actionable error messages that explain what went wrong and how to fix it
3. **Automatic XDP Support**: XDP now works out-of-the-box without manual configuration

## Installation Guide

### Prerequisites

- Linux system with kernel headers installed
- Root/sudo access
- Coccinelle installed (for building from source)
- Active SSH connection (for remote installation)

### Step 1: Prepare for Installation

```bash
# Check current driver version
ethtool -i ens3 # Replace ens3 with your interface name

# Check current network interface
ip route get 8.8.8.8
```

### Step 2: Install the Modified Driver

#### Option A: Safe Remote Installation (Recommended for SSH)

Use the provided safety script that automatically handles driver replacement:

```bash
# Make the script executable
chmod +x replace_driver.sh

# Run the safe replacement script
sudo ./replace_driver.sh
```

The script will:
- Give you a 3-second warning
- Unload the old driver
- Load the new driver
- Restart the network interface
- Renew DHCP lease

#### Option B: Manual Installation

```bash
# Backup current driver (optional)
modinfo gve > gve_original_info.txt

# Unload current driver and load new one (⚠️ Will temporarily disconnect network)
sudo rmmod gve && sudo insmod build/gve.ko

# Restart network interface
sudo ip link set dev ens3 up
sudo dhclient -r ens3 && sudo dhclient ens3
```

### Step 3: Verify Installation

```bash
# Check driver version and parameters
modinfo gve | grep -E "(version|force_gqi_qpl)"

# Check that XDP-compatible queue format is selected
dmesg | tail -10 | grep "queue format"

# Should show: "Driver is running with GQI QPL queue format (forced for XDP compatibility)"
```

## Usage Guide

### Basic XDP Testing

1. **Verify XDP Support**:
```bash
# Check if XDP features are enabled
cat /sys/class/net/ens3/xdp_features
```

2. **Load a Simple XDP Program**:
```bash
# Example: Load XDP drop program (be careful - this drops all packets!)
# ip link set dev ens3 xdp obj your_xdp_program.o sec main

# For testing, you can use xdp-loader or similar tools
```

3. **Check XDP Status**:
```bash
# View XDP program information
ip link show ens3 | grep xdp
```

### Advanced Configuration

#### Disable XDP Compatibility Mode

If you don't need XDP and want to use the driver's default queue format selection:

```bash
# Unload driver
sudo rmmod gve

# Reload with XDP compatibility disabled
sudo insmod build/gve.ko force_gqi_qpl=0
```

#### Check Queue Format Details

```bash
# View detailed driver messages
dmesg | grep gve | tail -20
```

## Troubleshooting

### XDP Program Won't Load

**Error**: `XDP is not supported in queue format X`

**Solution**: 
1. Check if `force_gqi_qpl` is enabled:
   ```bash
   cat /sys/module/gve/parameters/force_gqi_qpl
   ```
2. If it shows `N`, reload the driver:
   ```bash
   sudo rmmod gve && sudo insmod build/gve.ko force_gqi_qpl=1
   ```

### Network Connection Lost After Installation

**If using SSH and connection is lost**:

1. Wait 30 seconds for automatic recovery
2. Try reconnecting - the safety script should have restored connectivity
3. If still disconnected, use the console/serial access to investigate

**Recovery commands** (via console):
```bash
# Check interface status
ip link show

# Manually restart networking
sudo systemctl restart networking
# OR
sudo ifdown ens3 && sudo ifup ens3

# Check driver status
lsmod | grep gve
dmesg | tail -20
```

### Driver Won't Load

**Error**: `insmod: ERROR: could not insert module`

**Common causes and solutions**:

1. **Module verification error**:
   ```bash
   # Check if secure boot is enabled
   mokutil --sb-state
   
   # If enabled, you may need to sign the module or disable secure boot
   ```

2. **Dependency issues**:
   ```bash
   # Check module dependencies
   modinfo build/gve.ko | grep depends
   
   # Ensure required modules are loaded
   depmod -a
   ```

3. **Conflicting driver**:
   ```bash
   # Ensure old driver is completely unloaded
   sudo rmmod gve
   lsmod | grep gve  # Should show no results
   ```

### Performance Issues

If you experience network performance degradation:

1. **Check queue format**:
   ```bash
   dmesg | grep "queue format"
   ```

2. **Disable XDP compatibility if not needed**:
   ```bash
   sudo rmmod gve && sudo insmod build/gve.ko force_gqi_qpl=0
   ```

3. **Monitor network performance**:
   ```bash
   # Test bandwidth
   iperf3 -c speedtest.server.com
   
   # Check interface statistics
   ethtool -S ens3
   ```

## Technical Details

### Module Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `force_gqi_qpl` | bool | true | Force GQI QPL queue format for XDP compatibility |

### Queue Format Compatibility

| Format | XDP Support | Performance | Use Case |
|--------|-------------|-------------|----------|
| GQI_QPL | ✅ Yes | Good | XDP applications, standard networking |
| GQI_RDA | ❌ No | Better | High-performance networking (no XDP) |
| DQO_RDA | ❌ No | Best | Latest features, highest performance (no XDP) |
| DQO_QPL | ❌ No | Better | DQO with page pools (no XDP) |

### Changes Made to Original Driver

1. **Added module parameter**: `force_gqi_qpl` with default value `true`
2. **Modified queue selection logic** in `gve_adminq_describe_device()`
3. **Enhanced error messages** in `verify_xdp_configuration()`
4. **Maintained backward compatibility** - can be disabled if needed

## Reverting to Original Driver

If you need to revert to the original driver:

```bash
# Remove the modified driver
sudo rmmod gve

# Reinstall original driver (if available in package manager)
sudo apt update && sudo apt install --reinstall linux-modules-extra-$(uname -r)

# OR reload the inbox driver
sudo modprobe gve

# Verify reversion
modinfo gve | grep version
```

## Building from Source

If you need to rebuild the driver:

```bash
# Install dependencies
sudo apt update
sudo apt install -y build-essential linux-headers-$(uname -r) coccinelle

# Clean and rebuild
rm -rf build
./build_src.sh --target=oot
make -C /lib/modules/`uname -r`/build M=$(pwd)/build modules

# Verify build
ls -la build/gve.ko
modinfo build/gve.ko
```

## Version Information

- **Original Driver Version**: 1.0.0 (inbox)
- **Modified Driver Version**: 1.4.5.1-0-64ddd39-64ddd39-oot
- **Modification**: XDP Native Support
- **Kernel Compatibility**: 6.1.0+ (tested on 6.1.0-37-cloud-amd64)

## Support and Contributing

This is a community modification to enable XDP support in gvnic. For:

- **Original gvnic issues**: Contact Google Cloud Support
- **XDP-specific issues**: Check this modified driver documentation
- **General XDP questions**: Refer to XDP documentation and community resources

## Security Considerations

- This driver modifies kernel-level networking code
- Only install from trusted sources
- Test in non-production environments first
- Consider signing the module if secure boot is enabled

## License

This modified driver maintains the same license as the original Google gvnic driver (Dual MIT/GPL).

---

**Last Updated**: August 2024  
**Tested On**: Debian 12, Kernel 6.1.0-37-cloud-amd64  
**Status**: Production Ready