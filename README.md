# ![muxm](./assets/muxm_header_small.png) MuxMaster

**MuxMaster** – a versatile, cross-platform video repacking and encoding utility that preserves HDR, Dolby Vision, and high-quality audio while optimizing for Plex and Apple TV Direct Play. Supports smart codec handling, color space matching, error recovery, and optional stereo fallback.

## Table of Contents
- [Features](#features)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Examples](#examples)
- [Going Forward](#goingforward)
- [License](#license)
- [Contributing](#contributing)
- [Author](#author)


## ✨ Features <a id="features"></a>

- **Preserves HDR & Dolby Vision** – Detects HDR10, HLG, and Dolby Vision metadata in the source and preserves it through the encode. DV RPU layers are extracted with `dovi_tool` and re-injected into the output; if extraction fails, the pipeline falls back gracefully to a clean HDR10 or SDR encode rather than aborting.
- **Color Space Matching** – Automatically probes the source for color primaries, transfer characteristics, and matrix coefficients (BT.2020/SMPTE 2084, BT.709, HLG) and carries them through to the output pixel format and x265 color parameters. 4:2:2 and 4:4:4 chroma are downsampled to 4:2:0 for Apple TV Direct Play compatibility by default.
- **Audio Preservation** – Retains E-AC-3, AC-3, AAC, and ALAC without re-encoding when the codec is already Direct Play–compatible. Lossless or incompatible codecs (TrueHD, DTS-HD, FLAC, etc.) are transcoded to E-AC-3 (surround) or AAC (stereo) at appropriate bitrates.
- **Smart Audio Selection** – Scores every audio track on channel count, surround layout, language preference, codec rank, and bitrate, then picks the best one automatically. Override with `--audio-track` if needed.
- **Stereo Fallback** – Optionally creates a stereo AC-3 downmix alongside the primary multichannel track for compatibility with devices that can't decode surround.
- **Subtitle Handling** – Scans all subtitle streams, categorizes them as forced, full, or SDH/HI, and selects up to three tracks matching your language preference. Text-based subtitles (SRT, ASS, WebVTT) are converted to `mov_text` for MP4. PGS bitmap subtitles can be OCR'd to SRT via a configurable external tool (e.g., `sub2srt`).
- **Disk Space Preflight** – Checks available disk space on the output volume before starting and warns if free space is below a configurable threshold (default 5 GB).
- **Security Hardening** – Validates filenames for control characters, prevents source-equals-output overwrites, uses unpredictable temp file names, and validates the output extension against an allow-list to prevent injection.
- **Error Recovery** – Detects, logs, and gracefully handles mid-process failures with detailed error messages and line-number tracing.
- **Cross-Platform** – Works on macOS and most modern Linux distributions.
- **Dry-Run Mode** – Test workflows without writing files.
- **Checksum Verification** – Writes a SHA-256 checksum alongside the output file for integrity verification (`--checksum`).
- **Clean-up on Failure** – Removes incomplete temp files when an error occurs; optionally retains them for debugging (`--keep-temp`).

---

## 📦 Installation <a id="installation"></a>

```bash
# Clone the repository
git clone https://github.com/theBluWiz/muxmaster.git
cd muxmaster

# Make the script executable
chmod +x muxm

# Optionally move to a location in your PATH
sudo mv muxm /usr/local/bin/muxm
```

### Dependencies

**Required:**
- `ffmpeg` and `ffprobe`
- `dovi_tool` (Dolby Vision RPU extraction and injection)
- `jq` (JSON metadata parsing)

**Optional:**
- `sub2srt` or another OCR tool for PGS bitmap subtitle conversion (configurable via `--ocr-tool`)

---

## ⚙️ Configuration <a id="configuration"></a>

`muxm` reads configuration from a layered chain of `.muxmrc` files. Each file is a plain Bash script that reassigns the built-in default variables. Files are sourced in the following order, with later values overriding earlier ones:

| Priority | File | Purpose |
|---|---|---|
| 1 (lowest) | `/etc/.muxmrc` | System-wide defaults shared across all users |
| 2 | `~/.muxmrc` | Personal defaults for your user account |
| 3 | `./.muxmrc` (cwd) | Project- or directory-specific overrides |
| 4 (highest) | CLI arguments | Override everything for a single run |

Any variable from the defaults section of the script can be set in a `.muxmrc` file. For example:

```bash
# ~/.muxmrc — personal defaults
CRF_VALUE=17
PRESET_VALUE="slow"
ADD_STEREO_IF_MULTICH=0
SUB_LANG_PREF="eng,spa"
OUTPUT_EXT="m4v"
```

To inspect the fully merged configuration (defaults + all config files + CLI flags), run:

```bash
muxm --print-effective-config
```

---

## 🚀 Usage <a id="usage"></a>

```bash
muxm [options] <source> [target.mp4]
```

### Arguments
- `<source>` – Input media file (e.g., `movie.mkv`)
- `[target]` – Output file (optional; defaults to same name with configured extension)

### Flags
- `--dry-run` – Simulate without writing output
- `--checksum` – Write SHA-256 checksum for the final output
- `--crf N` – CRF quality value (default: 18)
- `-p, --preset NAME` – x265 encoder preset: ultrafast through placebo (default: slower)
- `--output-ext mp4|m4v|mov` – Output container (default: mp4)
- `-k, --keep-temp` – Retain working directory on failure
- `-K, --keep-temp-always` – Retain working directory even on success

See `muxm --help` for the full list of audio, subtitle, Dolby Vision, and tuning flags.

---

## 🔍 Examples <a id="examples"></a>

```bash
# Standard encode — CRF 18, stereo fallback, auto-detected color space
muxm input.mkv output.mp4

# Dry run for testing
muxm --dry-run input.mkv output.mp4

# Higher quality, no stereo downmix
muxm --crf 16 --no-stereo-fallback input.mkv output.mp4

# Force a specific audio track and disable Dolby Vision handling
muxm --audio-track 2 --no-dv input.mkv output.mp4

# Check what the merged config looks like before running
muxm --print-effective-config
```

---

## Going Forward <a id="goingforward"></a>
- **Format Presets** – Named profiles (`dv-archival`, `hdr10-hq`, `atv-directplay-hq`, `universal`) that set opinionated defaults for different playback targets. See `FORMAT_PRESETS_PLAN.md` for the implementation roadmap.
- **Batch Directory Processing** – Process all compatible files in a directory (including subdirectories) with filtering by extension or codec.
- **Parallel Processing Option** – Multi-threaded encoding when hardware resources are available, with automatic core detection.
- **Codec Expansion** – VP9, AV1, and ProRes workflows while preserving current Dolby Vision/HDR handling.
- **Logging Enhancements** – JSON log output for integration with monitoring systems or CI pipelines.
- **Interactive Mode** – Guided CLI wizard for non-technical users to configure a job without full command-line knowledge.
- **Self-Update Mechanism** – Pull the latest release from GitHub automatically.
- **Custom Naming Templates** – Output filename patterns with variables (e.g., `{title}_{codec}_{crf}`).

---

## 📄 License <a id="license"></a>

MuxMaster is freeware for personal, non-commercial use.
Any business, government, or organizational use requires a paid license.

Full license text available in [LICENSE.md](./LICENSE.md)

## 🤝 Contributing <a id="contributing"></a>

Contributions are welcome for bug reports, feature requests, and documentation improvements.
Please note that all code changes must be approved by the maintainer and comply with the license.

## 👤 Author <a id="author"></a>

Maintainer: Jamey Wicklund (theBluWiz)  
Email: [thebluwiz@thoughtspace.place](mailto:thebluwiz@thoughtspace.place)

> **Tip:** If you are a hiring manager or recruiter, this project demonstrates advanced Bash scripting, media processing workflows, error handling, and cross-platform compatibility design.
