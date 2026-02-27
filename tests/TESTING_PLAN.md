# MuxMaster (muxm) Testing Plan

**Version:** v1.0.0  
**Date:** 2026-02-26  
**Scope:** Comprehensive feature coverage — automated test harness + manual testing checklist

---

## Overview

muxm has grown to include 6 format profiles, 60+ CLI flags, layered configuration precedence, and pipelines for video (including DV/HDR), audio (scoring, transcoding, stereo fallback), subtitles (selection, burn-in, OCR, external export), and output (chapters, metadata, checksum, JSON reports). This plan covers every testable surface.

### Testing Artifacts

| File | Purpose |
|------|---------|
| `test_muxm.sh` | Automated test harness — generates synthetic media, runs ~160 assertions |
| This document | Manual testing procedures for features that require real media or subjective verification |

### Running the Automated Tests

```bash
# Full suite
./test_muxm.sh --muxm ./muxm

# Specific suite
./test_muxm.sh --muxm ./muxm --suite cli
./test_muxm.sh --muxm ./muxm --suite profiles
./test_muxm.sh --muxm ./muxm --suite e2e

# Verbose (shows output on failures)
./test_muxm.sh --muxm ./muxm --verbose

# Available suites: all, cli, toggles, completions, setup, config, profiles,
#                   conflicts, dryrun, video, hdr, audio, subs, output,
#                   containers, metadata, edge, e2e
```

### Prerequisites

Required: `ffmpeg`, `ffprobe`, `jq`, `bc`  
Optional: `dovi_tool`, `MP4Box`/`mp4box`, `pgsrip`/`sub2srt`, `tesseract`

---

## 1. Automated Test Coverage

The test harness (`test_muxm.sh`) generates synthetic test media — short 2-second clips with various codec/audio/subtitle combinations — and validates behavior against expected outcomes. No real movie files needed.

### 1.1 CLI Parsing & Validation (suite: `cli`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 1 | `--help` | Shows usage, lists profiles, mentions `--install-completions`, `--uninstall-completions`, `--setup`, exits 0 | ✅ |
| 2 | `--version` | Prints "MuxMaster" and "muxm" | ✅ |
| 3 | No arguments | Shows usage, exits 0 | ✅ |
| 4 | `--profile fake` | Exits 11, error message | ✅ |
| 5 | `--preset fake` | Exits 11, error message | ✅ |
| 6 | `--video-codec vp9` | Exits 11, "must be libx265 or libx264" | ✅ |
| 7 | `--output-ext webm` | Exits 11, "must be mp4, m4v, mov, or mkv" | ✅ |
| 8 | Missing source file | Exits 11, "not found" | ✅ |
| 9 | Too many positionals | Exits 11 | ✅ |
| 10 | Source = output | Exits 11, "same file" | ✅ |
| 11 | `--no-overwrite` | Refuses when output already exists | ✅ |
| 12 | `-h` alias | Exits 0 (same as `--help`) | ✅ |
| 13 | `-V` alias | Prints "MuxMaster" and "muxm" (same as `--version`) | ✅ |
| 14 | `-p` alias | `-p ultrafast` → PRESET_VALUE = ultrafast in effective config | ✅ |
| 15 | `-l` alias | `-l 5.1` → LEVEL_VALUE = 5.1 in effective config | ✅ |
| 16 | `-k` alias | `-k` → KEEP_TEMP = 1 in effective config | ✅ |
| 17 | `-K` alias | `-K` → KEEP_TEMP_ALWAYS = 1 in effective config | ✅ |

### 1.2 Toggle Flag Coverage (suite: `toggles`)

Validates that every boolean `--flag` / `--no-flag` pair correctly registers in effective config. All checks are pure config assertions — zero encode time.

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 18 | `--no-checksum` | CHECKSUM = 0 | ✅ |
| 19 | `--no-report-json` | REPORT_JSON = 0 | ✅ |
| 20 | `--no-skip-if-ideal` | SKIP_IF_IDEAL = 0 | ✅ |
| 21 | `--no-strip-metadata` | STRIP_METADATA = 0 | ✅ |
| 22 | `--no-sub-burn-forced` | SUB_BURN_FORCED = 0 | ✅ |
| 23 | `--no-sub-export-external` | SUB_EXPORT_EXTERNAL = 0 | ✅ |
| 24 | `--no-video-copy-if-compliant` | VIDEO_COPY_IF_COMPLIANT = 0 | ✅ |
| 25 | `--stereo-fallback` | ADD_STEREO_IF_MULTICH = 1 | ✅ |
| 26 | `--no-conservative-vbv` | CONSERVATIVE_VBV = 0 | ✅ |
| 27 | `--allow-dv-fallback` | ALLOW_DV_FALLBACK = 1 | ✅ |
| 28 | `--no-allow-dv-fallback` | ALLOW_DV_FALLBACK = 0 | ✅ |
| 29 | `--dv-convert-p81` | DV_CONVERT_TO_P81_IF_FAIL = 1 | ✅ |
| 30 | `--no-dv-convert-p81` | DV_CONVERT_TO_P81_IF_FAIL = 0 | ✅ |

### 1.3 Completion Installer (suite: `completions`)

Tests `--install-completions` / `--uninstall-completions` using an isolated `$HOME` to avoid touching real RC files.

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 31 | `--install-completions` banner | Shows "Completion Installer" | ✅ |
| 32 | `--install-completions` creates file | `~/.muxm/muxm-completion.bash` exists with `_muxm_completions` | ✅ |
| 33 | `--install-completions` patches `.bashrc` | Source line added | ✅ |
| 34 | `--install-completions` patches `.zshrc` | Source line added | ✅ |
| 35 | `--install-completions` idempotency | No duplicate source line in `.bashrc` on second run | ✅ |
| 36 | `--uninstall-completions` banner | Shows "Completion Uninstaller" | ✅ |
| 37 | `--uninstall-completions` removes file | Completion file deleted | ✅ |
| 38 | `--uninstall-completions` cleans `.bashrc` | Source line removed | ✅ |
| 39 | `--uninstall-completions` cleans `.zshrc` | Source line removed | ✅ |
| 40 | `--uninstall-completions` safe when nothing installed | "not found" message, no error | ✅ |

### 1.4 Setup Combined Installer (suite: `setup`)

Validates `--setup` runs all three sub-installers and standalone installer/uninstaller flags.

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 41 | `--setup` banner | Shows "Full Setup" | ✅ |
| 42 | `--setup` runs dependency installer | Output contains "Dependency Installer" | ✅ |
| 43 | `--setup` runs man page installer | Output contains "Manual Page Installer" | ✅ |
| 44 | `--setup` runs completion installer | Output contains "Completion Installer" | ✅ |
| 45 | `--setup` final summary | Shows "Setup complete" or "reporting errors" | ✅ |
| 46 | `--setup` installs completions | Completion file created | ✅ |
| 47 | `--install-dependencies` standalone | Shows banner, lists ffmpeg/ffprobe/jq | ✅ |
| 48 | `--uninstall-man` standalone | Shows banner, safe when man page not installed | ✅ |

### 1.5 Configuration Precedence (suite: `config`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 49 | `--print-effective-config` | Displays all sections | ✅ |
| 50 | Profile visible in config | PROFILE_NAME shows in output | ✅ |
| 51 | CLI overrides profile | `--crf 25` overrides profile CRF | ✅ |
| 52 | Config file `PROFILE_NAME` loaded | `.muxmrc` with `PROFILE_NAME="animation"` picked up | ✅ |
| 53 | `--create-config project streaming` | Creates `.muxmrc` with correct values | ✅ |
| 54 | `--create-config` refuses overwrite | Error on existing file | ✅ |
| 55 | `--force-create-config` overwrites | New profile written | ✅ |
| 56 | Invalid config scope | "Invalid scope" error | ✅ |
| 57 | `--create-config` all profiles | Each of dv-archival, hdr10-hq, atv-directplay-hq, universal creates valid `.muxmrc` | ✅ |
| 58 | Config variable override | `.muxmrc` with `CRF_VALUE=14` and `PRESET_VALUE="slower"` reflected in effective config | ✅ |
| 59 | Multi-layer: project overrides user | User `~/.muxmrc` CRF=22, project `.muxmrc` CRF=18 → effective CRF=18 | ✅ |
| 60 | Multi-layer: user PRESET preserved | User sets PRESET=slow, project doesn't set it → effective PRESET=slow | ✅ |
| 61 | Multi-layer: CLI overrides project | Project CRF=18, CLI `--crf 25` → effective CRF=25 | ✅ |
| 62 | Multi-layer: CLI wins full stack | User+project+CLI stack, CLI `--crf 30` wins | ✅ |
| 63 | Multi-layer: user PRESET survives full stack | User PRESET=slow preserved through project+CLI overrides of CRF | ✅ |
| 64 | User config `PROFILE_NAME` loaded | `~/.muxmrc` with `PROFILE_NAME="animation"` → animation active | ✅ |
| 65 | CLI `--profile` overrides user config | User config animation, CLI `--profile streaming` → streaming active | ✅ |

### 1.6 Profile Variable Assignment (suite: `profiles`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 66 | All 6 profiles accepted | Each shows in effective config | ✅ |
| 67 | `dv-archival` defaults | VIDEO_COPY=1, SKIP_IF_IDEAL=1, REPORT_JSON=1, LOSSLESS_PASSTHROUGH=1, MKV | ✅ |
| 68 | `hdr10-hq` defaults | DISABLE_DV=1, CRF=17, MKV | ✅ |
| 69 | `atv-directplay-hq` defaults | MP4, SUB_BURN_FORCED=1, SKIP_IF_IDEAL=1 | ✅ |
| 70 | `streaming` defaults | CRF=20, preset=medium | ✅ |
| 71 | `animation` defaults | CRF=16, MKV, LOSSLESS_PASSTHROUGH=1 | ✅ |
| 72 | `universal` defaults | libx264, TONEMAP=1, KEEP_CHAPTERS=0, STRIP_METADATA=1, MP4 | ✅ |

### 1.7 Conflict Warnings (suite: `conflicts`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 73 | `dv-archival` + `--no-dv` | ⚠️ warning emitted | ✅ |
| 74 | `dv-archival` + `--strip-metadata` | ⚠️ warning emitted | ✅ |
| 75 | `dv-archival` + `--no-keep-chapters` | ⚠️ warning emitted | ✅ |
| 76 | `dv-archival` + `--sub-burn-forced` | ⚠️ warning emitted | ✅ |
| 77 | `hdr10-hq` + `--tonemap` | ⚠️ warning emitted | ✅ |
| 78 | `hdr10-hq` + `--video-codec libx264` | ⚠️ warning emitted | ✅ |
| 79 | `atv-directplay-hq` + `--output-ext mkv` | ⚠️ warning emitted | ✅ |
| 80 | `atv-directplay-hq` + `--tonemap` | ⚠️ warning emitted | ✅ |
| 81 | `atv-directplay-hq` + `--video-codec libx264` | ⚠️ warning emitted | ✅ |
| 82 | `atv-directplay-hq` + `--audio-lossless-passthrough` | ⚠️ warning emitted | ✅ |
| 83 | `streaming` + `--output-ext mkv` | ⚠️ warning emitted | ✅ |
| 84 | `streaming` + `--audio-lossless-passthrough` | ⚠️ warning emitted | ✅ |
| 85 | `streaming` + `--video-codec libx264` | ⚠️ warning emitted | ✅ |
| 86 | `animation` + `--sub-burn-forced` | ⚠️ warning emitted | ✅ |
| 87 | `animation` + `--video-codec libx264` | ⚠️ warning emitted | ✅ |
| 88 | `animation` + `--output-ext mp4` | ⚠️ warning emitted | ✅ |
| 89 | `animation` + `--no-audio-lossless-passthrough` | ⚠️ warning emitted | ✅ |
| 90 | `universal` + `--output-ext mkv` | ⚠️ warning emitted | ✅ |
| 91 | `universal` + `--audio-lossless-passthrough` | ⚠️ warning emitted | ✅ |
| 92 | `universal` + `--video-codec libx265` | ⚠️ warning emitted | ✅ |
| 93 | Cross: `--video-copy-if-compliant` + `--tonemap` | ⚠️ warning about conflicting flags | ✅ |
| 94 | Cross: `--sub-export-external` with MKV output | ⚠️ warning emitted | ✅ |
| 95 | Cross: `--sub-burn-forced` + `--no-subtitles` | ⚠️ warning about no subs to burn | ✅ |

### 1.8 Dry-Run Mode (suite: `dryrun`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 96 | `--dry-run` with source | "DRY-RUN" announced, no output file | ✅ |
| 97 | `--dry-run` + profile | Profile announced, no files | ✅ |
| 98 | `--dry-run` + `--skip-audio` | "[Quick Test]" announced | ✅ |
| 99 | `--dry-run` + `--skip-subs` | "[Quick Test]" announced | ✅ |
| 100 | `--dry-run` + HDR source | "DRY-RUN" announced for HDR input | ✅ |

### 1.9 Video Pipeline (suite: `video`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 101 | Basic SDR → HEVC MP4 | Output exists, codec is `hevc` | ✅ |
| 102 | `--video-codec libx264` | Output codec is `h264` | ✅ |
| 103 | `--output-ext mkv` | Output format is `matroska` | ✅ |
| 104 | `--x265-params "aq-mode=3"` | Encode succeeds with custom x265 params | ✅ |
| 105 | `--threads 2` | Encode succeeds with thread limit | ✅ |
| 106 | `--video-copy-if-compliant` | HEVC source copied without re-encode | ✅ |
| 107 | `--level 5.1` config acceptance | LEVEL_VALUE = 5.1 in effective config | ✅ |
| 108 | `--level 5.1` VBV injection | Dry-run with HDR source includes vbv-maxrate/vbv-bufsize in x265 params | ✅ |

### 1.10 HDR Pipeline (suite: `hdr`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 109 | HDR10-tagged source encode | HEVC output, BT.2020 primaries and SMPTE 2084 transfer preserved | ✅ |
| 110 | `--no-tonemap` config flag | TONEMAP_HDR_TO_SDR = 0 in effective config | ✅ |
| 111 | `--tonemap` + HDR source | Tonemap filter chain (SDR-TONEMAP/zscale) present in dry-run | ✅ |
| 112 | `--profile universal` + HDR source | Tonemap filter chain present in dry-run (profile implies tonemap) | ✅ |

### 1.11 Audio Pipeline (suite: `audio`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 113 | 5.1 source → output has audio | ≥1 audio track | ✅ |
| 114 | Stereo fallback added | ≥2 audio tracks for surround source | ✅ |
| 115 | `--no-stereo-fallback` | Single audio track | ✅ |
| 116 | `--skip-audio` announced | "Audio processing disabled" in output | ✅ |
| 117 | Multi-audio auto-selection | Scoring algorithm prefers surround track | ✅ |
| 118 | `--audio-track 0` override | Specific track selected regardless of scoring | ✅ |
| 119 | `--audio-lang-pref spa` | Spanish audio track selected | ✅ |
| 120 | `--audio-force-codec aac` | Audio transcoded to AAC | ✅ |
| 121 | `--stereo-bitrate 192k` | Config shows 192k in effective config | ✅ |
| 122 | `--audio-lossless-passthrough` | AUDIO_LOSSLESS_PASSTHROUGH = 1 in config | ✅ |
| 123 | `--no-audio-lossless-passthrough` | AUDIO_LOSSLESS_PASSTHROUGH = 0 in config | ✅ |
| 124 | Commentary track deprioritized | Main feature selected over commentary (same codec/ch/lang) | ✅ |

### 1.12 Subtitle Pipeline (suite: `subs`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 125 | Multi-sub source → MKV | ≥1 subtitle tracks in output | ✅ |
| 126 | `--no-subtitles` | 0 subtitle tracks | ✅ |
| 127 | `--skip-subs` announced | "Subtitle processing disabled" in output | ✅ |
| 128 | `--sub-lang-pref jpn` | SUB_LANG_PREF = jpn in effective config | ✅ |
| 129 | `--no-sub-sdh` | SUB_INCLUDE_SDH = 0 in effective config | ✅ |
| 130 | `--sub-export-external` | Output produced; SRT sidecar(s) created | ✅ |
| 131 | `--no-ocr` | SUB_ENABLE_OCR = 0 in effective config | ✅ |
| 132 | `--ocr-lang jpn` | SUB_OCR_LANG = jpn in effective config | ✅ |

### 1.13 Output Features (suite: `output`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 133 | `--keep-chapters` | Chapters present in output | ✅ |
| 134 | `--no-keep-chapters` | Chapters stripped | ✅ |
| 135 | `--checksum` | `.sha256` sidecar created | ✅ |
| 136 | `--checksum` SHA-256 validates | Sidecar content matches output file (sha256sum -c) | ✅ |
| 137 | `--report-json` | `.report.json` sidecar created, valid JSON | ✅ |
| 138 | `--report-json` contains tool/version key | `has("tool")` or `has("muxm_version")` or `has("version")` | ✅ |
| 139 | `--report-json` contains source/input key | `has("source")` or `has("input")` or `has("src")` | ✅ |
| 140 | `--report-json` contains profile key | `has("profile")` | ✅ |
| 141 | `--report-json` contains output key | `has("output")` | ✅ |
| 142 | `--report-json` contains timestamp key | `has("timestamp")` | ✅ |
| 143 | `--skip-if-ideal` with compliant source | Recognized as compliant or produced output | ✅ |
| 144 | `--keep-temp-always` (`-K`) | Workdir preserved on successful encode | ✅ |
| 145 | `--keep-temp` (`-k`) | KEEP_TEMP registered in effective config | ✅ |

### 1.14 Container Formats (suite: `containers`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 146 | `--output-ext mov` | Output produced, container is MOV/MP4 family | ✅ |
| 147 | `--output-ext m4v` | Output produced, container is MP4 family | ✅ |

### 1.15 Metadata & Miscellaneous Flags (suite: `metadata`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 148 | `--strip-metadata` real encode | Title and comment removed from output | ✅ |
| 149 | Metadata preservation (no flag) | Title preserved in output | ✅ |
| 150 | `--ffmpeg-loglevel warning` | Accepted without error | ✅ |
| 151 | `--no-hide-banner` | Accepted without error | ✅ |
| 152 | `--ffprobe-loglevel warning` | Accepted without error | ✅ |

### 1.16 Edge Cases & Security (suite: `edge`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 153 | Empty source file | Rejected with error | ✅ |
| 154 | Filename with spaces | Handled correctly | ✅ |
| 155 | `--output-ext "mp4;"` | Rejected (injection prevention) | ✅ |
| 156 | `--ocr-tool "sub2srt;rm -rf /"` | Rejected (injection prevention) | ✅ |
| 157 | `--skip-video` | Behavior validated (can't produce output) | ✅ |
| 158 | Non-readable source file | Rejected with "not readable" error | ✅ |
| 159 | Non-writable output directory | Rejected with "not writable" error | ✅ |
| 160 | Double-dash (`--`) argument terminator | Source after `--` parsed as positional arg | ✅ |
| 161 | Auto-generated output path | Source-only invocation (no explicit output) derives filename with swapped extension | ✅ |

### 1.17 Profile End-to-End Encodes (suite: `e2e`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 162 | `streaming` full encode | Output exists, correct extension (.mp4) | ✅ |
| 163 | `animation` full encode | Output exists (MKV) | ✅ |
| 164 | `universal` full encode | Output exists, codec is H.264 | ✅ |
| 165 | `dv-archival` full encode | Output exists (.mkv), HEVC preserved, audio present | ✅ |
| 166 | `hdr10-hq` full encode | Output exists (.mkv), HEVC codec, 10-bit pixel format | ✅ |
| 167 | `atv-directplay-hq` full encode | Output exists (.mp4), HEVC codec, audio present | ✅ |

---

## 2. Manual Testing Procedures

These tests require real media files, specialized hardware, or subjective quality evaluation that cannot be automated with synthetic clips.

### 2.1 Dolby Vision Pipeline

> **Requires:** Real DV source (Profile 5, 7, or 8), `dovi_tool`, `MP4Box`

| # | Test | Steps | Expected Result |
|---|------|-------|-----------------|
| M1 | DV detection | Run `muxm --dry-run dv_source.mkv` | "Dolby Vision detected" message, DV profile/compat ID logged |
| M2 | DV preservation (`dv-archival`) | `muxm --profile dv-archival dv_source.mkv` | Output has DV signaling (`dvcC` box present). Verify with `mediainfo` or `ffprobe -show_streams` |
| M3 | DV → P8.1 conversion (`atv-directplay-hq`) | `muxm --profile atv-directplay-hq dv_p7.mkv` | DV Profile 8.1 in MP4 output. `mediainfo --full` shows DV config record |
| M4 | DV stripping (`hdr10-hq`) | `muxm --profile hdr10-hq dv_source.mkv` | No DV in output, HDR10 static metadata preserved (check MaxCLL/MDCV) |
| M5 | DV fallback on failure | Corrupt the RPU or use P5 dual-layer source without EL access | ⚠️ warning, falls back to non-DV output |
| M6 | `--no-dv` on DV source | `muxm --no-dv dv_source.mkv` | DV ignored, video treated as HDR10 or SDR |
| M7 | DV-only source + `hdr10-hq` | Source with DV but no HDR10 fallback metadata | ⚠️ warning about missing static metadata |

### 2.2 HDR/HLG Color Pipeline

> **Requires:** Real HDR10 or HLG source, HDR display for visual verification

| # | Test | Steps | Expected Result |
|---|------|-------|-----------------|
| M8 | HDR10 passthrough | `muxm --profile hdr10-hq hdr10_source.mkv` | HDR10 metadata preserved: `color_primaries=bt2020`, `transfer=smpte2084`, MaxCLL/MDCV present |
| M9 | HDR → SDR tone-mapping | `muxm --profile universal hdr10_source.mkv` | SDR output, BT.709 color, visually acceptable brightness (not washed out) |
| M10 | HLG handling | `muxm --profile streaming hlg_source.mkv` | HLG metadata preserved: `transfer=arib-std-b67` |
| M11 | Color space matching | `muxm hdr_source.mkv --print-effective-config` and inspect output | `decide_color_and_pixfmt` selects correct pixfmt and x265 color params |
| M12 | libx264 + HDR warning | `muxm --video-codec libx264 hdr10_source.mkv` | ⚠️ "H.264 cannot preserve HDR metadata — output will appear washed out" |

### 2.3 Tone-Mapping Visual Quality

> **Requires:** HDR10 source, SDR display

| # | Test | Steps | Expected Result |
|---|------|-------|-----------------|
| M13 | Hable tone-map quality | `muxm --profile universal hdr10_movie.mkv` | Highlights not clipped, shadows not crushed, skin tones natural |
| M14 | Dark scenes | Same as above with a dark-scene-heavy source | Shadow detail preserved, no banding in gradients |
| M15 | Bright highlights | Source with specular highlights | Highlights gracefully roll off, no hard clipping |

### 2.4 Audio Quality & Selection

> **Requires:** Source with multiple audio tracks in different codecs/languages

| # | Test | Steps | Expected Result |
|---|------|-------|-----------------|
| M16 | Audio scoring | Source with TrueHD 7.1 + AC3 5.1 + AAC stereo, all English | Best track selected (verify via log or `--dry-run`) |
| M17 | Language preference | `--audio-lang-pref "jpn,eng"` on multi-language source | Japanese track selected first |
| M18 | `--audio-track N` override | `muxm --audio-track 2 source.mkv` | Third audio stream selected regardless of scoring |
| M19 | Lossless passthrough | `--audio-lossless-passthrough` with TrueHD source | TrueHD copied untouched (check codec_name in output) |
| M20 | `--audio-force-codec aac` | Source with EAC3 5.1 | All audio transcoded to AAC |
| M21 | E-AC-3 bitrate accuracy | `--profile atv-directplay-hq` with 7.1 source | Output EAC3 at ~768kbps (check with `ffprobe`) |
| M22 | Stereo downmix quality | Play the stereo fallback track | Centered dialogue, reasonable dynamic range |
| M22b | Commentary detection | Source with feature + commentary tracks (same codec/ch/lang) | Main feature selected; commentary deprioritized in score log |

### 2.5 Subtitle Pipeline (Advanced)

> **Requires:** Sources with PGS, ASS/SSA, forced, and SDH subtitles

| # | Test | Steps | Expected Result |
|---|------|-------|-----------------|
| M23 | PGS → SRT OCR | MP4 output from source with PGS subs, OCR enabled | SRT subtitle track present, text is readable |
| M24 | ASS/SSA preservation | `--profile animation` with styled ASS subs | Styled subtitles preserved in MKV (typesetting, colors) |
| M25 | Forced sub burn-in | `--sub-burn-forced` with source that has forced track | Foreign dialogue visible in video, no separate forced track |
| M26 | External SRT export | `--sub-export-external` | `.srt` sidecar files created alongside output |
| M27 | SDH exclusion | `--no-sub-sdh` on source with SDH track | SDH track absent, forced and full tracks present |
| M28 | `SUB_MAX_TRACKS` limit | Source with 6+ subtitle tracks, `--profile animation` | At most 6 tracks in output |
| M29 | Forced sub detection | Source with disposition:forced on subtitle | Track detected and either burned or kept as soft sub |

### 2.6 Skip-if-Ideal

> **Requires:** File that already matches profile constraints

| # | Test | Steps | Expected Result |
|---|------|-------|-----------------|
| M30 | Ideal file skipped | Pre-encode a file to match `atv-directplay-hq`, re-run same profile with `--skip-if-ideal` | "already ideal" message, output is hardlinked/copied (near-instant) |
| M31 | Non-ideal file processed | Run `--skip-if-ideal` on mismatched source | Normal encode proceeds |
| M32 | JSON report on skip | `--profile dv-archival` on ideal source | Report JSON written with skip status |

### 2.7 Error Recovery & Cleanup

| # | Test | Steps | Expected Result |
|---|------|-------|-----------------|
| M33 | Ctrl+C during encode | Start a long encode, press Ctrl+C | "Interrupted by user", temp files cleaned, exit 130 |
| M34 | Disk full during encode | Encode to a nearly-full volume | ⚠️ disk space warning, graceful failure, temp files cleaned |
| M35 | Corrupt source file | Feed a truncated/corrupt MKV | "Failed to probe" error, exit 12 |
| M36 | `--keep-temp` on failure | Force a failure, check workdir | Workdir preserved with logs |
| M37 | `--keep-temp-always` on success | Normal successful encode | Workdir preserved after success |
| M38 | Missing ffmpeg | Rename ffmpeg temporarily | "Missing required tool: ffmpeg" |

### 2.8 Cross-Platform

| # | Test | Platform | Verify |
|---|------|----------|--------|
| M39 | macOS Homebrew ffmpeg | macOS 14+ | Encodes complete, MP4Box detected as `MP4Box` |
| M40 | Linux apt ffmpeg | Ubuntu 22+ | Encodes complete, mp4box detected as lowercase |
| M41 | BSD stat compatibility | macOS | `filesize_pretty` works, `realpath_fallback` works |
| M42 | GNU stat compatibility | Linux | Same as above |

### 2.9 Playback Verification

> **Requires:** Target playback devices

| # | Test | Device | Expected |
|---|------|--------|----------|
| M43 | `atv-directplay-hq` output | Apple TV 4K + Plex | Direct Play (no transcode in Plex dashboard) |
| M44 | `atv-directplay-hq` DV output | Apple TV 4K + DV TV | Dolby Vision activates on TV |
| M45 | `streaming` output | Roku / Fire TV / Shield | Plays without buffering, correct audio/subs |
| M46 | `universal` output | Old Roku / Browser / Phone | Plays everywhere, SDR, stereo |
| M47 | `animation` output | Desktop player (mpv/VLC) | ASS subs render with styling, lossless audio plays |
| M48 | `dv-archival` output | DV-capable client | Full fidelity preserved, lossless audio |

---

## 3. Test Media Library

For complete manual testing, maintain a set of reference files:

| File | Description | Tests Covered |
|------|-------------|---------------|
| `dv_p7_truehd71.mkv` | DV Profile 7 + TrueHD 7.1 + PGS subs | M1–M7, M16, M19, M23 |
| `dv_p81_eac3.mp4` | DV Profile 8.1 + EAC3 5.1 (already ATV-compliant) | M30–M32 |
| `hdr10_atmos.mkv` | HDR10 + Atmos TrueHD + SRT subs | M8–M12, M16, M21 |
| `hlg_aac51.mkv` | HLG + AAC 5.1 | M10 |
| `sdr_h264_ac3.mkv` | H.264 SDR + AC3 5.1 + 3 audio tracks | M16–M18, M20 |
| `anime_ass_flac.mkv` | HEVC SDR + FLAC + styled ASS subs (6 tracks) | M24, M28 |
| `forced_pgs.mkv` | HEVC + PGS forced + PGS full + PGS SDH | M23, M25, M27, M29 |
| `multilang.mkv` | Multiple audio/sub languages (eng, jpn, fre) | M17 |

---

## 4. Regression Test Checklist

Run after every code change:

```bash
# 1. Fast automated suite (< 2 min)
./test_muxm.sh --muxm ./muxm --suite all

# 2. Quick smoke test with real media (if available)
muxm --dry-run --profile atv-directplay-hq real_source.mkv
muxm --dry-run --profile universal real_source.mkv

# 3. If video pipeline changed: one real encode
muxm --profile streaming --preset ultrafast --crf 28 real_source.mkv /tmp/regression_test.mp4

# 4. If audio pipeline changed:
muxm --preset ultrafast --crf 28 multi_audio_source.mkv /tmp/audio_test.mp4
ffprobe -v error -show_streams -of json /tmp/audio_test.mp4 | jq '[.streams[] | select(.codec_type=="audio")] | length'

# 5. If config/profile changed:
muxm --profile <changed-profile> --print-effective-config
```

---

## 5. CI Integration Notes

The automated test harness is designed for CI. Key integration points:

- **Exit codes:** 0 = all pass, 1 = any failure
- **No network required:** All test media is generated locally via ffmpeg
- **No real media required:** Synthetic 2-second clips cover pipeline mechanics
- **Suite isolation:** Run individual suites for targeted checks (`--suite cli` for fast, `--suite e2e` for full encodes)
- **Runtime:** `cli` + `toggles` + `completions` + `setup` + `config` + `profiles` + `conflicts` + `dryrun` ≈ 15 seconds. Full `e2e` ≈ 60–120 seconds depending on CPU.
- **Dependencies:** `ffmpeg`, `ffprobe`, `jq`, `bc` (all commonly available in CI images)

### Example GitHub Actions Workflow

```yaml
name: muxm tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install deps
        run: sudo apt-get update && sudo apt-get install -y ffmpeg jq bc
      - name: Run fast tests
        run: ./test_muxm.sh --muxm ./muxm --suite cli
      - name: Run config tests
        run: ./test_muxm.sh --muxm ./muxm --suite config
      - name: Run profile tests
        run: ./test_muxm.sh --muxm ./muxm --suite profiles
      - name: Run full e2e
        run: ./test_muxm.sh --muxm ./muxm --suite e2e
```

---

## 6. Coverage Gap Analysis

| Area | Automated | Manual Required | Notes |
|------|-----------|-----------------|-------|
| CLI parsing | ✅ Full | — | Includes --no-overwrite, short aliases (-h, -V, -p, -l, -k, -K) |
| Toggle flags | ✅ Full | — | 13 toggle pairs validated (positive + negative) |
| Completions installer | ✅ Full | — | Install, idempotency, uninstall, safe-when-absent |
| Setup combined installer | ✅ Full | — | All three sub-installers + standalone deps/man |
| Config precedence | ✅ Full | — | Single-layer, multi-layer (user+project+CLI), all --create-config profiles |
| Profile defaults | ✅ Full | — | All 6 profiles validated |
| Conflict warnings | ✅ Full | — | 23 conflict combinations tested across all profiles + cross-flag |
| Dry-run mode | ✅ Full | — | Includes HDR source dry-run |
| Video encode (SDR) | ✅ Full | — | Includes x265-params, threads, video-copy-if-compliant, --level VBV |
| Video encode (HDR) | ⚠️ Tagged only | Real HDR quality (M8–M15) | Synthetic clips have HDR tags but no real HDR content; tonemap filter chain verified in dry-run |
| Container formats | ✅ Full | — | MOV and M4V validated |
| Metadata stripping | ✅ Full | — | Strip and preserve verified with ffprobe; --ffprobe-loglevel tested |
| Dolby Vision | ❌ None | Full DV pipeline (M1–M7) | Requires real DV source + dovi_tool + MP4Box |
| Tone-mapping quality | ❌ None | Visual evaluation (M13–M15) | Requires HDR source + human judgment |
| Audio scoring | ✅ Partial | Complex multi-track (M16–M22) | Auto-selection, track override, language pref, force-codec, commentary detection tested; subjective quality not covered |
| Audio quality | ❌ None | Listening test (M22) | Subjective |
| Subtitle pipeline | ✅ Partial | PGS OCR, burn-in, styling (M23–M29) | Config flags, external export, and track counts verified; OCR and visual burn-in require real media |
| Subtitle OCR | ❌ None | PGS → SRT (M23) | Requires pgsrip/tesseract + PGS source |
| Subtitle burn-in | ❌ None | Visual verification (M25) | Requires forced-sub source + eyes |
| ASS/SSA styling | ❌ None | Visual verification (M24) | Requires styled ASS source + eyes |
| Skip-if-ideal | ⚠️ Partial | Full roundtrip (M30–M32) | Basic compliant-source test exists; hard to generate truly "ideal" synthetic source |
| Output features | ✅ Full | — | Chapters, checksum (with validation), JSON report (6 key checks), keep-temp all tested |
| Edge cases & security | ✅ Full | — | Includes permissions, double-dash terminator, auto-generated output path |
| E2E profiles | ✅ Full | — | All 6 profiles validated with real encodes |
| Error recovery | ❌ None | SIGINT, disk full (M33–M38) | Requires manual intervention |
| Cross-platform | ❌ None | macOS + Linux (M39–M42) | Requires both platforms |
| Playback verification | ❌ None | Device testing (M43–M48) | Requires target hardware |

**Priority for expanding automation:**
1. Subtitle burn-in detection (check for video filter applied in dry-run ffmpeg command)
2. Skip-if-ideal full roundtrip (generate ideal file matching a profile, verify skip behavior)
3. Audio scoring edge cases (multi-language surround vs preferred-language stereo with real Blu-ray sources)