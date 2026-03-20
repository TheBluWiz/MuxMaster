# Changelog

All notable changes to MuxMaster will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com), and this project adheres to [Semantic Versioning](https://semver.org).

## [1.0.2] - 2026-03-19

Enforce HEVC Level 5.1 VBV guardrails in `atv-directplay-hq` re-encodes to prevent bitrate spikes that cause stutter on Apple TV 4K.

### Fixed

- **`atv-directplay-hq` re-encodes now capped by Level 5.1 VBV.** Previously, the copy path was guarded by `MAX_COPY_BITRATE=50000k` but the re-encode path had no bitrate ceiling — a CRF 17 encode of complex scenes could spike beyond what the Apple TV 4K hardware decoder sustains without buffering. The profile now sets `LEVEL_VALUE="5.1"`, which activates the existing conservative VBV machinery (`vbv-maxrate=40000k`, `vbv-bufsize=80000k`). Can be overridden with `--level` or `--no-conservative-vbv`.

### Changed

- `--create-config ... atv-directplay-hq` now emits `LEVEL_VALUE` and `CONSERVATIVE_VBV` as uncommented (active) variables, matching the profile's new defaults.

## [1.0.1] - 2026-03-09

Output file collisions now handled gracefully. Adds new flags `--replace-source` and `--force-replace-source`.

### Fixed

- **Source/output collision no longer fatal.** When the derived output path matches the source file (e.g., `muxm movie.mp4` where the default output extension is also `.mp4`), muxm now auto-appends a version number instead of aborting: `movie(1).mp4`, `movie(2).mp4`, etc. The version number increments until a free filename is found.

### Added

- **`--replace-source`** — Replace the original source file with the encoded output after an interactive confirmation prompt. Requires a TTY; rejected in non-interactive shells with a clear error directing the user to `--force-replace-source`.
- **`--force-replace-source`** — Same as `--replace-source` but skips the confirmation prompt. Designed for scripting and automation.
- Both flags registered in `--help`, `--print-effective-config`, tab completions, man page, and `.muxmrc` config generator.
- New `collision` test suite in `test_muxm.sh` with 17 assertions covering auto-versioning, sequential incrementing, TTY rejection, in-place replacement, and no-collision passthrough.

### Changed

- Existing tests in `test_edge` and `_test_cli_error_codes` updated to expect auto-versioning behavior instead of the previous fatal error.

## [1.0.0] - 2026-03-07

Initial public release.

### Core

- Multi-stage encoding pipeline: source inspection → profile resolution → video → audio → subtitles → final mux → verification
- Single-pass ffprobe metadata cache for all stream analysis
- Layered configuration precedence: hardcoded defaults → `/etc/.muxmrc` → `~/.muxmrc` → `./.muxmrc` → `--profile` → CLI flags
- 60+ CLI flags with `--help`, `man muxm`, and bash/zsh tab completion

### Format Profiles

- **`dv-archival`** — Lossless Dolby Vision preservation. Copy video if compliant, lossless audio passthrough, skip-if-ideal, JSON reporting
- **`hdr10-hq`** — High-quality HDR10 encoding. HEVC CRF 17, strip DV, lossless audio + stereo fallback, MKV
- **`atv-directplay-hq`** — Apple TV 4K Direct Play via Plex. MP4, HEVC Main10, DV Profile 8.1 auto-conversion, E-AC-3 + AAC stereo, forced subtitle burn-in
- **`streaming`** — Modern HEVC streaming for Plex/Jellyfin/Emby. CRF 20, E-AC-3 448k, AAC stereo, MP4
- **`animation`** — Optimized for anime and cartoons. CRF 16, keeps 10-bit for SDR sources (anti-banding), low psy-rd/psy-rdoq, lossless audio, ASS/SSA subtitle preservation, MKV
- **`universal`** — Maximum compatibility. H.264 SDR with HDR tone-mapping, AAC stereo, burned forced subs, external SRT export, MP4

### Video

- Dolby Vision detection via stream metadata and frame-level side data
- RPU extraction, profile conversion (P7 dual-layer → P8.1 single-layer), and injection via `dovi_tool`
- DV container signaling verification via `MP4Box`
- Color space detection (BT.2020 PQ, BT.2020 HLG, BT.709 SDR) with distinct HDR10, HLG, and SDR encoding paths and automatic x265 parameter selection
- HDR-to-SDR tone-mapping via zscale + hable
- Chroma subsampling normalization (4:2:2/4:4:4 → 4:2:0) for Direct Play compatibility
- Video copy-if-compliant to skip re-encoding when source already matches target, with configurable bitrate ceiling to prevent blindly copying oversized streams
- Conservative VBV guardrails per x265 level

### Audio

- Weighted scoring system for automatic track selection (language, channels, surround bonus, codec preference, commentary penalty)
- Configurable scoring weights via `.muxmrc`
- Lossless passthrough for TrueHD, DTS-HD MA, and FLAC
- Automatic AAC stereo fallback generation from surround sources
- E-AC-3 transcoding at profile-specific bitrates (5.1 and 7.1)
- Descriptive audio stream titling (e.g., "5.1 Surround (E-AC-3)")

### Subtitles

- Track categorization: forced, full, and SDH
- PGS bitmap subtitle OCR to SRT via `pgsrip` or `sub2srt`
- Forced subtitle burn-in
- External `.srt` export
- Language preference filtering
- SDH track exclusion

### Output & Reporting

- MP4, MKV, M4V, and MOV container support
- Chapter marker preservation and stripping
- Metadata stripping
- skip-if-ideal detection (avoids re-processing compliant files)
- JSON reporting with full decision/warning/stream-mapping documentation
- SHA-256 checksum generation
- Dry-run mode (`--dry-run`) for previewing the full pipeline without encoding
- Effective config display (`--print-effective-config`) showing resolved settings from all layers

### Setup & Tooling

- `--setup` for one-command first-time installation (dependencies + man page + tab completion)
- `--install-dependencies` with Homebrew and pipx detection
- `--install-man` / `--uninstall-man` for system man page management
- `--install-completions` / `--uninstall-completions` for bash/zsh tab completion
- `--create-config` / `--force-create-config` for generating pre-seeded `.muxmrc` files
- Conflict warnings for contradictory profile + flag combinations
- Spinner and progress bar for long-running operations
- Quick-test mode (`--skip-video`, `--skip-audio`, `--skip-subs`) for validating pipeline decisions without waiting for a full encode
- Disk space preflight warning before encoding begins
- Graceful signal handling (Ctrl-C / SIGTERM) with automatic temp file cleanup
- Structured exit codes for scripting and automation (10 = missing tool, 11 = bad arguments, 12 = corrupt source, 40–43 = pipeline failures)
- Comprehensive test harness (`test_muxm.sh`) with 18 test suites and ~165 assertions

[1.0.2]: https://github.com/TheBluWiz/MuxMaster/releases/tag/v1.0.2
[1.0.1]: https://github.com/TheBluWiz/MuxMaster/releases/tag/v1.0.1
[1.0.0]: https://github.com/TheBluWiz/MuxMaster/releases/tag/v1.0.0