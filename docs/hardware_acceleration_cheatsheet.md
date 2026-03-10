# Hardware Acceleration Cheat Sheet

Quick reference for MuxMaster hardware acceleration setup and usage.

## One-Command Setup

```bash
# Detect hardware and create config
muxm --setup

# Or create config manually
muxm --create-config user
```

## Verify Hardware Support

```bash
# Check what hardware MuxMaster detected
muxm --show-hardware-info

# Verify ffmpeg has hardware encoders
ffmpeg -encoders | grep -E "(nvenc|qsv|videotoolbox)"
```

## Common Commands

```bash
# Use auto-detected hardware
muxm movie.mkv

# Force specific hardware
muxm --hwaccel nvidia movie.mkv
muxm --hwaccel intel movie.mkv
muxm --hwaccel apple movie.mkv

# Disable hardware acceleration
muxm --hwaccel cpu movie.mkv

# GPU decode only, CPU encode
muxm --hwaccel-decode --no-hwaccel-encode movie.mkv
```

## FFmpeg Requirements

### macOS (Apple Silicon)
```bash
# Homebrew includes VideoToolbox by default
brew install ffmpeg
```

### Linux (NVIDIA)
```bash
# Most distros include NVENC support
sudo apt install ffmpeg
# or
sudo dnf install ffmpeg
```

### Cross-Platform (All Hardware)
```bash
# Jellyfin-FFmpeg 7 has everything pre-compiled
wget https://github.com/jellyfin/jellyfin-ffmpeg/releases/download/v7.0.1-1/jellyfin-ffmpeg_7.0.1-1_amd64.deb
sudo dpkg -i jellyfin-ffmpeg_7.0.1-1_amd64.deb
```

## Platform-Specific Notes

### NVIDIA CUDA
- ✅ Full GPU decode + encode
- Uses `-cq` instead of `-crf`
- Requires RTX/GTX with NVENC support

### Intel QuickSync
- ✅ GPU encode only
- ⚠️ CPU decode (expected behavior)
- Uses `-global_quality` instead of `-crf`

### Apple Silicon
- ✅ Full GPU decode + encode
- Uses bitrate instead of CRF
- Requires ffmpeg with VideoToolbox

## Subtitle Compatibility

| Operation | NVIDIA | Intel | Apple |
|-----------|---------|-------|-------|
| Burn-in | ✅ | ✅ | ✅ |
| OCR | ✅ | ✅ | ✅ |
| Export | ✅ | ✅ | ✅ |

## Troubleshooting

### Hardware not detected?
```bash
# Re-run detection
muxm --setup

# Check ffmpeg manually
ffmpeg -encoders | grep videotoolbox
```

### Encoder fails?
```bash
# Test encoder directly
ffmpeg -f lavfi -i testsrc=duration=5 -c:v hevc_nvenc -f null -

# MuxMaster will fallback to CPU automatically
```

## Performance Expectations

| Hardware | Speedup | Quality |
|----------|---------|---------|
| NVIDIA RTX 3080 | 3-5x | Excellent |
| Intel i7-12700K | 2-3x | Good |
| Apple M2 Pro | 2-4x | Good |

## Config File Example

```bash
# ~/.muxmrc
HWACCEL_TYPE=nvidia
HWACCEL_ENABLED=1
HWACCEL_DECODE=1
HWACCEL_ENCODE=1
```

## Pro Tips

1. **Use Jellyfin-FFmpeg** for best compatibility
2. **Update GPU drivers** (NVIDIA)
3. **Monitor VRAM usage** for 4K+ content
4. **Hardware works with all profiles** - no special configuration needed
