# Changelog

All notable changes to MuxMaster will be documented in this file.

## [1.0.0] — 2026-03-02

Initial public release.

### Core

- Multi-stage encoding pipeline: source inspection → profile resolution → video → audio → subtitles → final mux → verification
- Single-pass ffprobe metadata cache for all stream analysis
- Layered configuration precedence: hardcoded defaults → `/etc/.muxmrc` → `~/.muxmrc` → `./.muxmrc` → `--profile` → CLI flags
- 60+ CLI flags with `--help`, `man muxm`, and bash/zsh tab completion

### Format Profiles

- **`dv-archival`** — Lossless Dolby Vision preservation. Copy video, lossless audio passthrough, skip-if-ideal, JSON reporting
- **`hdr10-hq`** — High-quality HDR10 encoding. HEVC CRF 17, strip DV, lossless audio + stereo fallback, MKV
- **`atv-directplay-hq`** — Apple TV 4K Direct Play via Plex. MP4, HEVC Main10, DV Profile 8.1 auto-conversion, E-AC-3 + AAC stereo, forced subtitle burn-in
- **`streaming`** — Modern HEVC streaming for Plex/Jellyfin/Emby. CRF 20, E-AC-3 448k, AAC stereo, MP4
- **`animation`** — Anime and cartoon optimized. CRF 16, 10-bit even for SDR, low psy-rd/psy-rdoq, lossless audio, ASS/SSA subtitle preservation, MKV
- **`universal`** — Maximum compatibility. H.264 SDR with HDR tone-mapping, AAC stereo, burned forced subs, external SRT export, MP4

### Video

- Dolby Vision detection via stream metadata and frame-level side data
- RPU extraction, profile conversion (P7 dual-layer → P8.1 single-layer), and injection via `dovi_tool`
- DV container signaling verification via `MP4Box`
- Color space detection (BT.2020 PQ, BT.2020 HLG, BT.709 SDR) with automatic x265 parameter selection
- HDR-to-SDR tone-mapping via zscale + hable
- Video copy-if-compliant to skip re-encoding when source already matches target
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
- Skip-if-ideal detection (avoids re-processing compliant files)
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
- Comprehensive test harness (`test_muxm.sh`) with 18 test suites and ~160 assertions