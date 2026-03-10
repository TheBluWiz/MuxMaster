# MuxMaster Documentation

Complete documentation for MuxMaster video processing utility.

## Core Documentation

- **[README.md](../README.md)** - Main project documentation and quick start guide
- **[Hardware Acceleration Guide](hardware_acceleration.md)** - Comprehensive hardware acceleration setup and troubleshooting
- **[Hardware Acceleration Cheat Sheet](hardware_acceleration_cheatsheet.md)** - Quick reference for common hardware acceleration tasks
- **[Format Profiles](config_profile.md)** - Detailed explanation of all encoding profiles
- **[Testing Plan](TESTING_PLAN.md)** - Comprehensive testing procedures and validation

## Manual Pages

- **[muxm.1](muxm.1)** - Unix manual page (install with `man muxm`)

## Quick Links

### Getting Started
1. [Install MuxMaster](../README.md#installation)
2. [Run hardware setup](hardware_acceleration.md#setup--configuration)
3. [Choose a profile](config_profile.md)
4. [Encode your first video](../README.md#usage)

### Hardware Acceleration
- [Supported platforms](hardware_acceleration.md#supported-platforms)
- [FFmpeg requirements](hardware_acceleration.md#ffmpeg-requirements)
- [Troubleshooting](hardware_acceleration.md#troubleshooting)
- [Quick reference](hardware_acceleration_cheatsheet.md)

### Advanced Usage
- [Configuration options](../README.md#configuration)
- [Dolby Vision handling](../README.md#dolby-vision)
- [Subtitle processing](../README.md#subtitles)
- [Audio track selection](../README.md#audio-track-selection)

## Documentation Structure

```
docs/
├── README.md                     # This file
├── hardware_acceleration.md      # Full hardware acceleration guide
├── hardware_acceleration_cheatsheet.md  # Quick reference
├── config_profile.md             # Profile documentation
├── TESTING_PLAN.md              # Testing procedures
└── muxm.1                       # Unix man page
```

## Contributing to Documentation

When contributing to MuxMaster documentation:

1. **Keep examples current** - Test all commands before adding
2. **Use consistent formatting** - Follow existing markdown patterns
3. **Cross-reference appropriately** - Link between related sections
4. **Update multiple files** - When adding features, update README, guides, and man page
5. **Test on multiple platforms** - Ensure commands work on macOS and Linux

## Documentation Style Guide

- **Code blocks**: Use bash syntax highlighting
- **Tables**: Include headers and alignment
- **Links**: Use relative paths for internal links
- **Sections**: Use consistent heading levels
- **Examples**: Provide real, tested commands
- **Warnings**: Use ⚠️ emoji for important notes
- **Success indicators**: Use ✅ emoji for supported features

## Getting Help

If you need help with MuxMaster:

1. **Check this documentation** - Most questions are answered here
2. **Read the FAQ** in the main README
3. **Search existing issues** on GitHub
4. **Create a new issue** with detailed information about your problem

For hardware acceleration issues, see the [troubleshooting section](hardware_acceleration.md#troubleshooting) first.
