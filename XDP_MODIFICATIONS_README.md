# GVnic Driver - XDP Native Support Modifications

## Quick Summary

This repository contains a modified version of Google's gvnic driver that **enables native XDP (eXpress Data Path) support**.

### 🚀 Key Changes

- ✅ **XDP Works Out-of-the-Box**: No manual configuration needed
- ✅ **Smart Queue Format Selection**: Automatically uses XDP-compatible format when needed  
- ✅ **Better Error Messages**: Clear guidance when XDP issues occur
- ✅ **Backward Compatible**: Can be disabled with `force_gqi_qpl=0`

### ⚡ Quick Install

```bash
# Build the driver
./build_src.sh --target=oot
make -C /lib/modules/`uname -r`/build M=$(pwd)/build modules

# Safe installation (for SSH users)
sudo ./replace_driver.sh
```

### 🔧 Module Parameter

| Parameter | Default | Description |
|-----------|---------|-------------|
| `force_gqi_qpl` | `true` | Force GQI QPL format for XDP compatibility |

```bash
# Check current setting
cat /sys/module/gve/parameters/force_gqi_qpl

# Disable XDP compatibility (if not needed)
sudo rmmod gve && sudo insmod build/gve.ko force_gqi_qpl=0
```

### 🎯 What This Fixes

**Before**: XDP programs would fail with:
```
XDP is not supported in mode X
```

**After**: XDP programs load successfully:
```
Driver is running with GQI QPL queue format (forced for XDP compatibility)
```

### 📋 Modified Files

- `google/gve/gve_main.c` - Added module parameter and version info
- `google/gve/gve_adminq.c` - Modified queue format selection logic  
- `build/gve_main.c` - Built version with modifications
- `build/gve_adminq.c` - Built version with modifications
- `build/gve.h` - Added extern declaration for parameter
- `replace_driver.sh` - Safe installation script
- `XDP_GVNIC_GUIDE.md` - **📖 Complete installation and usage guide**

### 📖 Full Documentation

**👉 See [XDP_GVNIC_GUIDE.md](XDP_GVNIC_GUIDE.md) for complete installation and usage instructions.**

### 🔍 Technical Details

- **Queue Format Compatibility**: Only GQI_QPL format supports XDP
- **Original Priority**: DQO_RDA → DQO_QPL → GQI_RDA → GQI_QPL
- **Modified Priority**: GQI_QPL (when `force_gqi_qpl=true`) → Original Priority
- **Performance Impact**: Minimal - GQI_QPL is still a high-performance format

### ✅ Verification

```bash
# Check driver is loaded with XDP support
modinfo gve | grep force_gqi_qpl
# Output: parm: force_gqi_qpl:Force GQI QPL queue format for XDP compatibility (default: true) (bool)

# Verify queue format
dmesg | grep "queue format" | tail -1
# Output: Driver is running with GQI QPL queue format (forced for XDP compatibility)
```

### 🆘 Need Help?

1. **Installation Issues**: See [Installation Guide](XDP_GVNIC_GUIDE.md#installation-guide)
2. **XDP Not Working**: See [Troubleshooting](XDP_GVNIC_GUIDE.md#troubleshooting)  
3. **Network Issues**: Use `./replace_driver.sh` for safe recovery

---

**🎉 Ready to use XDP with gvnic? Start with the [Complete Guide](XDP_GVNIC_GUIDE.md)!**