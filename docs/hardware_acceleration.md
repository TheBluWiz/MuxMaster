# Hardware Acceleration Guide

MuxMaster supports hardware-accelerated video encoding and decoding on NVIDIA GPUs, Intel GPUs (QuickSync), and Apple Silicon (VideoToolbox). This guide covers setup, ffmpeg requirements, limitations, and troubleshooting.

## Table of Contents

- [Supported Platforms](#supported-platforms)
- [FFmpeg Requirements](#ffmpeg-requirements)
- [Setup & Configuration](#setup--configuration)
- [Platform-Specific Details](#platform-specific-details)
- [Subtitle Limitations](#subtitle-limitations)
- [Performance Considerations](#performance-considerations)
- [Troubleshooting](#troubleshooting)

---

## Supported Platforms

| Platform | GPU Decode | GPU Encode | FFmpeg Support | Notes |
|----------|------------|------------|----------------|-------|
| **NVIDIA CUDA** | ✅ H.264, HEVC, VP8, VP9, AV1, MPEG-2, VC-1 | ✅ H.264, HEVC | `--enable-nvenc` | Full hardware pipeline |
| **Intel QuickSync** | ⚠️ Limited (CPU fallback) | ✅ H.264, HEVC | `--enable-libmfx` | GPU encode only |
| **Apple Silicon** | ✅ H.264, HEVC | ✅ H.264, HEVC | `--enable-videotoolbox` | Full hardware pipeline |

---

## FFmpeg Requirements

### Check Your FFmpeg Build

```bash
# Check ffmpeg version and build configuration
ffmpeg -version

# List available encoders
ffmpeg -encoders | grep -E "(nvenc|qsv|videotoolbox)"

# List available decoders  
ffmpeg -decoders | grep -E "(cuvid|qsv|videotoolbox)"
```

### Required FFmpeg Configuration Flags

| Platform | Required Flags | Typical Build Sources |
|----------|----------------|----------------------|
| **NVIDIA** | `--enable-nvenc --enable-cuda --enable-cuvid` | Official ffmpeg, distro packages |
| **Intel** | `--enable-libmfx` | libmfx-enabled builds |
| **Apple** | `--enable-videotoolbox` | macOS default, Homebrew |

### Recommended FFmpeg Builds

#### macOS (Apple Silicon)
```bash
# Homebrew ffmpeg (includes VideoToolbox by default)
brew install ffmpeg

# Verify VideoToolbox support
ffmpeg -encoders | grep videotoolbox
```

#### Linux (NVIDIA)
```bash
# Ubuntu/Debian - install ffmpeg with NVENC support
sudo apt install ffmpeg

# Verify NVENC support
ffmpeg -encoders | grep nvenc
```

#### Cross-Platform (Jellyfin-FFmpeg)
```bash
# Jellyfin-FFmpeg 7.x comes pre-compiled with hardware support
# Download from: https://github.com/jellyfin/jellyfin-ffmpeg/releases

# Supports all three platforms out of the box:
# - NVIDIA NVENC/CUVID
# - Intel QuickSync (libmfx)
# - Apple VideoToolbox (macOS builds)
```

---

## Setup & Configuration

### Automatic Hardware Detection

```bash
# First-time setup (recommended)
muxm --setup

# Generate config with hardware detection
muxm --create-config user

# Force recreate config (overwrites existing)
muxm --force-create-config user
```

### Manual Hardware Selection

```bash
# Override auto-detection
muxm --hwaccel nvidia movie.mkv
muxm --hwaccel intel movie.mkv  
muxm --hwaccel apple movie.mkv
muxm --hwaccel cpu movie.mkv  # Disable hardware acceleration
```

### Configuration Variables

Your `~/.muxmrc` will contain these hardware settings:

```bash
# Hardware acceleration type: nvidia|intel|apple|cpu
HWACCEL_TYPE=apple

# Enable hardware acceleration (1=enabled, 0=disabled)
HWACCEL_ENABLED=1

# Enable hardware decode when available
HWACCEL_DECODE=1

# Enable hardware encode when available
HWACCEL_ENCODE=1
```

---

## Platform-Specific Details

### NVIDIA CUDA

**Features:**
- Full hardware decode and encode pipeline
- Supports H.264 and HEVC encoding
- Hardware-accelerated decoding for most formats
- Uses `-cq` (Constant Quality) instead of `-crf`

**Encoder Mapping:**
- `libx265` → `hevc_nvenc`
- `libx264` → `h264_nvenc`

**Preset Mapping:**
- `ultrafast/superfast/veryfast` → `p1`
- `faster/fast` → `p4`
- `medium` → `p6`
- `slow/slower/veryslow` → `p7`

**Requirements:**
- NVIDIA GPU with NVENC support (Kepler or newer)
- Up-to-date NVIDIA drivers
- ffmpeg compiled with NVENC support

### Intel QuickSync

**Features:**
- GPU encoding only (CPU decode for compatibility)
- Supports H.264 and HEVC encoding
- Uses `-global_quality` instead of `-crf`

**Encoder Mapping:**
- `libx265` → `hevc_qsv`
- `libx264` → `h264_qsv`

**Limitations:**
- GPU decode disabled due to device initialization issues
- Falls back to CPU decoding automatically

**Requirements:**
- Intel CPU with QuickSync support (Sandy Bridge or newer)
- ffmpeg compiled with libmfx support

### Apple Silicon (VideoToolbox)

**Features:**
- Full hardware decode and encode pipeline
- Supports H.264 and HEVC encoding
- Uses bitrate-based encoding instead of CRF

**Encoder Mapping:**
- `libx265` → `hevc_videotoolbox`
- `libx264` → `h264_videotoolbox`

**Bitrate Mapping (CRF → approximate):**
- CRF 14-16 → 8000k
- CRF 17-19 → 5000k  
- CRF 20-22 → 3000k
- CRF 23-25 → 2000k

**Special Parameters:**
- `-allow_sw 1` for software fallback
- No preset support (uses system defaults)

**Requirements:**
- Apple Silicon Mac (M1/M2/M3) or Intel Mac with T2
- ffmpeg 7+ with VideoToolbox support
- macOS 10.15+ for full feature support

---

## Subtitle Limitations

### Hardware Encode vs Subtitle Processing

**Important:** Hardware encoders have limitations when combined with certain subtitle operations:

| Operation | NVIDIA NVENC | Intel QuickSync | Apple VideoToolbox |
|-----------|--------------|-----------------|-------------------|
| **Burn-in subtitles** | ✅ Supported | ✅ Supported | ✅ Supported |
| **External subtitle export** | ✅ Supported | ✅ Supported | ✅ Supported |
| **Complex filter chains** | ⚠️ May fallback to CPU | ⚠️ May fallback to CPU | ⚠️ May fallback to CPU |

### Subtitle Burn-in Considerations

When burning subtitles into video with hardware acceleration:

1. **Performance**: Hardware encoders handle subtitle burn-in efficiently
2. **Quality**: No quality degradation compared to software encoding
3. **Compatibility**: All platforms support subtitle burn-in during hardware encode

### OCR and Bitmap Subtitles

**PGS/VobSub → SRT OCR:**
- Hardware encoding works seamlessly with OCR
- OCR processing happens before encoding pipeline
- No performance impact on hardware encoder selection

**Recommended workflow:**
```bash
# Enable OCR with hardware acceleration
muxm --hwaccel auto --sub-ocr movie.mkv
```

---

## Performance Considerations

### Expected Performance Gains

| Platform | Encode Speedup | Decode Speedup | Typical Use Case |
|----------|----------------|----------------|------------------|
| **NVIDIA RTX 3080** | 3-5x faster | 2-4x faster | High-quality encoding |
| **Intel i7-12700K** | 2-3x faster | CPU fallback | Balanced performance |
| **Apple M2 Pro** | 2-4x faster | 2-3x faster | Power-efficient encoding |

### Memory Usage

- **NVIDIA**: Additional 500MB-1GB VRAM usage
- **Intel**: Minimal additional memory usage
- **Apple**: Efficient memory usage with unified memory

### Quality vs Speed

Hardware encoders prioritize speed over maximum quality:
- **NVENC**: Excellent quality, slightly larger files than libx265
- **QuickSync**: Good quality, efficient encoding
- **VideoToolbox**: Good quality, Apple-optimized

---

## Troubleshooting

### Common Issues

#### "Hardware encoder not found"
```bash
# Check if encoder is available
ffmpeg -encoders | grep -E "(nvenc|qsv|videotoolbox)"

# Re-run hardware detection
muxm --setup
```

#### "GPU decode failed"
- **NVIDIA**: Update NVIDIA drivers
- **Intel**: This is expected - falls back to CPU decode
- **Apple**: Update macOS and ffmpeg

#### "Encoder initialization failed"
```bash
# Test encoder manually
ffmpeg -f lavfi -i testsrc=duration=5 -c:v hevc_nvenc -f null -
ffmpeg -f lavfi -i testsrc=duration=5 -c:v hevc_qsv -f null -
ffmpeg -f lavfi -i testsrc=duration=5 -c:v hevc_videotoolbox -f null -
```

### Fallback Behavior

MuxMaster automatically falls back to CPU encoding when:
- Hardware encoder initialization fails
- Unsupported codec/parameters requested
- Hardware encoder encounters errors

**Fallback is automatic and transparent** - no action needed.

### Debug Information

```bash
# Show current hardware detection
muxm --show-hardware-info

# Check log files for encoder selection
# Look for lines like:
# "→ GPU decode enabled (NVIDIA CUDA) for encode"
# "Selected encoder: hevc_nvenc"
```

### Performance Tuning

For optimal performance:
1. **Use latest ffmpeg builds** with hardware support
2. **Keep GPU drivers updated** (NVIDIA)
3. **Ensure sufficient VRAM** for high-resolution content
4. **Monitor temperatures** during long encodes

---

## Advanced Configuration

### Custom Encoder Parameters

For advanced users, hardware encoder parameters can be customized:

```bash
# NVIDIA specific tuning
HWACCEL_NVENC_PRESET=p6
HWACCEL_NVENC_RC=cbr
HWACCEL_NVENC_BVBUF=50000k

# Intel QuickSync tuning  
HWACCEL_QSV_PRESET=medium
HWACCEL_QSV_GLOBAL_QUALITY=20

# Apple VideoToolbox tuning
HWACCEL_VT_BITRATE=5000k
HWACCEL_VT_ALLOW_SW=1
```

### Multi-GPU Systems

```bash
# Select specific GPU (NVIDIA)
export CUDA_VISIBLE_DEVICES=0
muxm movie.mkv

# Or use GPU selection in config
HWACCEL_GPU_ID=0
```

---

## Conclusion

Hardware acceleration in MuxMaster provides significant performance improvements with minimal configuration. The automatic detection and fallback mechanisms ensure reliable operation across different hardware configurations.

For best results:
1. Use ffmpeg builds with comprehensive hardware support
2. Keep your system and drivers updated  
3. Monitor performance during initial usage
4. Use `--show-hardware-info` to verify configuration

If you encounter issues, check the troubleshooting section or create an issue on the MuxMaster GitHub repository.
