# MuxMaster (muxm) Testing Plan

**Version:** v1.2.0
**Date:** 2026-03-29
**Scope:** Comprehensive feature coverage — automated test harness + manual testing checklist

---

## Overview

muxm has grown to include 6 format profiles, 70+ CLI flags, layered configuration precedence, and pipelines for video (including DV/HDR), audio (scoring, multi-track, transcoding, stereo fallback), subtitles (selection, burn-in, OCR, multi-track, external export), and output (chapters, metadata, checksum, JSON reports, source replacement). This plan covers every testable surface.

### Testing Artifacts

| File | Purpose |
|------|---------|
| `test_muxm.sh` | Automated test harness v2.0 — generates synthetic media, runs ~600 assertions across 19 suites |
| This document | Manual testing procedures for features that require real media or subjective verification; identifies ~100 additional test cases for new features |

### Running the Automated Tests

```bash
# Full suite (from project root)
./test_muxm.sh --muxm ./muxm

# Specific suite
./test_muxm.sh --muxm ./muxm --suite cli
./test_muxm.sh --muxm ./muxm --suite profiles
./test_muxm.sh --muxm ./muxm --suite e2e

# Verbose (shows output on failures)
./test_muxm.sh --muxm ./muxm --verbose

# Available suites: all, cli, toggles, unit, completions, setup, config, profiles,
#                   conflicts, collision, dryrun, video, hdr, audio, subs, output,
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
| 17a | VALID_PROFILES ↔ `--help` | Every profile in VALID_PROFILES constant appears in `--help` output | ✅ |
| 17b | VALID_PROFILES ↔ completions | Every profile in VALID_PROFILES appears in installed completion script | ✅ |

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
| 31 | `--audio-titles` | INCLUDE_AUDIO_TITLES = 1 | ✅ |
| 32 | `--no-audio-titles` | INCLUDE_AUDIO_TITLES = 0 | ✅ |
| 32a | `--sdr-force-10bit` | SDR_FORCE_10BIT = 1 | ✅ |
| 32b | `--no-sdr-force-10bit` | SDR_FORCE_10BIT = 0 | ✅ |
| 32e | `--sub-preserve-format` | SUB_PRESERVE_TEXT_FORMAT = 1 | ✅ |
| 32f | `--no-sub-preserve-format` | SUB_PRESERVE_TEXT_FORMAT = 0 | ✅ |
| 32g | `--dv` (enable) | DISABLE_DV = 0 | ✅ |
| 32h | `--no-dv` (disable) | DISABLE_DV = 1 | ✅ |
| 32i | `--tonemap` | TONEMAP_HDR_TO_SDR = 1 | ✅ |
| 32j | `--no-tonemap` | TONEMAP_HDR_TO_SDR = 0 | ✅ |
| 32k | `--skip-if-ideal` | SKIP_IF_IDEAL = 1 | ✅ |
| 32l | `--report-json` | REPORT_JSON = 1 | ✅ |
| 32m | `--checksum` | CHECKSUM = 1 | ✅ |
| 32n | `--strip-metadata` | STRIP_METADATA = 1 | ✅ |
| 32o | `--keep-chapters` | KEEP_CHAPTERS = 1 | ✅ |
| 32p | `--sub-burn-forced` | SUB_BURN_FORCED = 1 | ✅ |
| 32q | `--sub-export-external` | SUB_EXPORT_EXTERNAL = 1 | ✅ |
| 32r | `--video-copy-if-compliant` | VIDEO_COPY_IF_COMPLIANT = 1 | ✅ |
| 32s | `--replace-source` | REPLACE_SOURCE = 1 in effective config (requires TTY) | ⚠️ manual only — requires TTY |
| 32t | `--force-replace-source` | FORCE_REPLACE_SOURCE = 1 in effective config | ✅ |
| 32u | `--ext-subs` / `--no-ext-subs` | EXT_SUB_ENABLED = 1 / 0 | ✅ |
| 32v | `--sub-sole-ext-fallback` / `--no-sub-sole-ext-fallback` | SUB_SOLE_EXT_FALLBACK = 1 / 0 | ✅ |
| 32w | `--conservative-vbv` | CONSERVATIVE_VBV = 1 | ✅ |
| 32x | `--profile-comment` / `--no-profile-comment` | PROFILE_COMMENT = 1 / 0 | ✅ |
| 32y | `--no-sub-sdh` | SUB_INCLUDE_SDH = 0 | ✅ |
| 32z | `--no-keep-chapters` | KEEP_CHAPTERS = 0 | ✅ |

### 1.3 Completion Installer (suite: `completions`)

Tests `--install-completions` / `--uninstall-completions` using an isolated `$HOME` to avoid touching real RC files.

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 33 | `--install-completions` banner | Shows "Completion Installer" | ✅ |
| 34 | `--install-completions` creates file | `~/.muxm/muxm-completion.bash` exists with `_muxm_completions` | ✅ |
| 35 | `--install-completions` patches `.bashrc` | Source line added | ✅ |
| 36 | `--install-completions` patches `.zshrc` | Source line added | ✅ |
| 37 | `--install-completions` idempotency | No duplicate source line in `.bashrc` on second run | ✅ |
| 38 | `--uninstall-completions` banner | Shows "Completion Uninstaller" | ✅ |
| 39 | `--uninstall-completions` removes file | Completion file deleted | ✅ |
| 40 | `--uninstall-completions` cleans `.bashrc` | Source line removed | ✅ |
| 41 | `--uninstall-completions` cleans `.zshrc` | Source line removed | ✅ |
| 42 | `--uninstall-completions` safe when nothing installed | "not found" message, no error | ✅ |

### 1.4 Setup Combined Installer (suite: `setup`)

Validates `--setup` runs all three sub-installers and standalone installer/uninstaller flags.

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 43 | `--setup` banner | Shows "Full Setup" | ✅ |
| 44 | `--setup` runs dependency installer | Output contains "Dependency Installer" | ✅ |
| 45 | `--setup` runs man page installer | Output contains "Manual Page Installer" | ✅ |
| 46 | `--setup` runs completion installer | Output contains "Completion Installer" | ✅ |
| 47 | `--setup` final summary | Shows "Setup complete" or "reporting errors" | ✅ |
| 48 | `--setup` installs completions | Completion file created | ✅ |
| 49 | `--install-dependencies` standalone | Shows banner, lists ffmpeg/ffprobe/jq | ✅ |
| 50 | `--uninstall-man` standalone | Shows banner, safe when man page not installed | ✅ |

### 1.5 Configuration Precedence (suite: `config`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 51 | `--print-effective-config` | Displays all sections | ✅ |
| 52 | Profile visible in config | PROFILE_NAME shows in output | ✅ |
| 53 | CLI overrides profile | `--crf 25` overrides profile CRF | ✅ |
| 54 | Config file `PROFILE_NAME` loaded | `.muxmrc` with `PROFILE_NAME="animation"` picked up | ✅ |
| 55 | `--create-config project streaming` | Creates `.muxmrc` with correct values | ✅ |
| 56 | `--create-config` refuses overwrite | Error on existing file | ✅ |
| 57 | `--force-create-config` overwrites | New profile written | ✅ |
| 58 | Invalid config scope | "Invalid scope" error | ✅ |
| 59 | `--create-config` all profiles | Each of dv-archival, hdr10-hq, atv-directplay-hq, universal creates valid `.muxmrc` | ✅ |
| 60 | Config variable override | `.muxmrc` with `CRF_VALUE=14` and `PRESET_VALUE="slower"` reflected in effective config | ✅ |
| 61 | Multi-layer: project overrides user | User `~/.muxmrc` CRF=22, project `.muxmrc` CRF=18 → effective CRF=18 | ✅ |
| 62 | Multi-layer: user PRESET preserved | User sets PRESET=slow, project doesn't set it → effective PRESET=slow | ✅ |
| 63 | Multi-layer: CLI overrides project | Project CRF=18, CLI `--crf 25` → effective CRF=25 | ✅ |
| 64 | Multi-layer: CLI wins full stack | User+project+CLI stack, CLI `--crf 30` wins | ✅ |
| 65 | Multi-layer: user PRESET survives full stack | User PRESET=slow preserved through project+CLI overrides of CRF | ✅ |
| 66 | User config `PROFILE_NAME` loaded | `~/.muxmrc` with `PROFILE_NAME="animation"` → animation active | ✅ |
| 67 | CLI `--profile` overrides user config | User config animation, CLI `--profile streaming` → streaming active | ✅ |
| 68 | Invalid `FFMPEG_LOGLEVEL` in config | `.muxmrc` with `FFMPEG_LOGLEVEL=bogus` → exit 11, error names variable | ✅ |
| 69 | Invalid `FFPROBE_LOGLEVEL` in config | `.muxmrc` with `FFPROBE_LOGLEVEL=nonsense` → exit 11, error names variable | ✅ |
| 70 | Deprecated `AUDIO_SCORE_LANG_BONUS_ENG` migration | Warning emitted, value propagated to `AUDIO_SCORE_LANG_BONUS` | ✅ |
| 71 | `--ocr-tool` sets config | `--ocr-tool pgsrip` → SUB_OCR_TOOL = pgsrip in effective config | ✅ |

### 1.6 Profile Variable Assignment (suite: `profiles`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 72 | All 6 profiles accepted | Each shows in effective config | ✅ |
| 73 | `dv-archival` defaults | VIDEO_COPY=1, SKIP_IF_IDEAL=1, REPORT_JSON=1, LOSSLESS_PASSTHROUGH=1, MKV | ✅ |
| 74 | `hdr10-hq` defaults | DISABLE_DV=1, CRF=17, MKV | ✅ |
| 75 | `atv-directplay-hq` defaults | MP4, SUB_BURN_FORCED=1, SKIP_IF_IDEAL=1 | ✅ |
| 76 | `streaming` defaults | CRF=20, preset=medium | ✅ |
| 77 | `animation` defaults | CRF=16, MKV, LOSSLESS_PASSTHROUGH=1 | ✅ |
| 78 | `universal` defaults | libx264, TONEMAP=1, KEEP_CHAPTERS=0, STRIP_METADATA=1, MP4 | ✅ |

### 1.7 Conflict Warnings (suite: `conflicts`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 79 | `dv-archival` + `--no-dv` | ⚠️ warning emitted | ✅ |
| 80 | `dv-archival` + `--strip-metadata` | ⚠️ warning emitted | ✅ |
| 81 | `dv-archival` + `--no-keep-chapters` | ⚠️ warning emitted | ✅ |
| 82 | `dv-archival` + `--sub-burn-forced` | ⚠️ warning emitted | ✅ |
| 83 | `hdr10-hq` + `--tonemap` | ⚠️ warning emitted | ✅ |
| 84 | `hdr10-hq` + `--video-codec libx264` | ⚠️ warning emitted | ✅ |
| 85 | `atv-directplay-hq` + `--output-ext mkv` | ⚠️ warning emitted | ✅ |
| 86 | `atv-directplay-hq` + `--tonemap` | ⚠️ warning emitted | ✅ |
| 87 | `atv-directplay-hq` + `--video-codec libx264` | ⚠️ warning emitted | ✅ |
| 88 | `atv-directplay-hq` + `--audio-lossless-passthrough` | ⚠️ warning emitted | ✅ |
| 89 | `streaming` + `--output-ext mkv` | ⚠️ warning emitted | ✅ |
| 90 | `streaming` + `--audio-lossless-passthrough` | ⚠️ warning emitted | ✅ |
| 91 | `streaming` + `--video-codec libx264` | ⚠️ warning emitted | ✅ |
| 92 | `animation` + `--sub-burn-forced` | ⚠️ warning emitted | ✅ |
| 93 | `animation` + `--video-codec libx264` | ⚠️ warning emitted | ✅ |
| 94 | `animation` + `--output-ext mp4` | ⚠️ warning emitted | ✅ |
| 95 | `animation` + `--no-audio-lossless-passthrough` | ⚠️ warning emitted | ✅ |
| 96 | `universal` + `--output-ext mkv` | ⚠️ warning emitted | ✅ |
| 97 | `universal` + `--audio-lossless-passthrough` | ⚠️ warning emitted | ✅ |
| 98 | `universal` + `--video-codec libx265` | ⚠️ warning emitted | ✅ |
| 99 | Cross: `--video-copy-if-compliant` + `--tonemap` | ⚠️ warning about conflicting flags | ✅ |
| 100 | Cross: `--sub-export-external` with MKV output | ⚠️ warning emitted | ✅ |
| 101 | Cross: `--sub-burn-forced` + `--no-subtitles` | ⚠️ warning about no subs to burn | ✅ |
| 101a | `dv-archival` + `--crf N` (non-default) | ⚠️ warning CRF is ignored for copy-only | ✅ |
| 101b | `dv-archival` + `--audio-track N` (multi-track conflict) | ⚠️ warning multi-track vs single-track | ✅ |
| 101c | `dv-archival` + `--audio-force-codec aac` (multi-track conflict) | ⚠️ warning multi-track vs transcode | ✅ |
| 101d | `dv-archival` + `--stereo-fallback` (multi-track conflict) | ⚠️ warning stereo fallback redundant | ✅ |
| 101e | `dv-archival` + `--sub-export-external` (multi-track sub conflict) | ⚠️ warning external export ignored | ✅ |
| 101f | `hdr10-hq` + `--dv` (DV re-enabled) | ⚠️ warning DV layers may cause issues | ✅ |
| 101g | `atv-directplay-hq` + `--output-ext mov` | ⚠️ warning MOV unusual for ATV | ✅ |
| 101h | `streaming` + `--output-ext mov` | ⚠️ warning MOV unusual for streaming | ✅ |
| 101i | `animation` + `--output-ext mov` | ⚠️ warning MOV can't carry ASS/PGS | ✅ |
| 101j | `animation` + `--no-sub-preserve-format` | ⚠️ warning ASS→SRT loses styling | ✅ |
| 101k | `animation` + `--no-audio-lossless-passthrough` | ⚠️ warning lossless transcoded | ✅ |
| 101l | `universal` + `--output-ext mov` | ⚠️ warning MOV unusual for max-compat | ✅ |
| 101m | `universal` + `--dv` (DV enabled with SDR) | ⚠️ warning DV contradictory for universal | ✅ |
| 101n | Cross: `--profile streaming --tonemap` + `--video-codec libx265` | ⚠️ SDR in HEVC is unusual (requires an active profile to trigger) | ✅ |
| 101o | Cross: `--sub-burn-forced` + `--no-subtitles` | ⚠️ SUB_BURN_FORCED with no subs | ✅ |

### 1.8 Collision Handling (suite: `collision`)

Validates filename collision auto-versioning and source replacement flags. Uses an `.mp4` source whose derived output path collides with the source.

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 101p | Auto-version on collision | Source `.mp4` → derived output collides → collision note printed, output renamed to `movie(1).mp4` | ✅ |
| 101q | Auto-version increment | `movie(1).mp4` exists → next encode produces `movie(2).mp4` | ✅ |
| 101r | Auto-version further increment | `movie(1)` and `movie(2)` exist → produces `movie(3).mp4` | ✅ |
| 101s | No collision when extensions differ | `.mkv` source → `.mp4` output, no collision note | ✅ |
| 101t | `--replace-source` non-TTY rejection | stdin is not a TTY → exits 11, error mentions TTY and suggests `--force-replace-source` | ✅ |
| 101u | `--force-replace-source` | Source file replaced atomically, no versioned files created | ✅ |
| 101v | `--replace-source` in `--help` | `--help` output mentions `--replace-source` and `--force-replace-source` | ✅ |
| 101w | `--force-replace-source` in effective config | `FORCE_REPLACE_SOURCE = 1` shown in `--print-effective-config` | ✅ |
| 101x | Explicit output path: no collision | Source and explicit output differ → no auto-versioning triggered | ✅ |

### 1.9 Dry-Run Mode (suite: `dryrun`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 102 | `--dry-run` with source | "DRY-RUN" announced, no output file | ✅ |
| 103 | `--dry-run` + profile | Profile announced, no files | ✅ |
| 104 | `--dry-run` + `--skip-audio` | "[Quick Test]" announced | ✅ |
| 105 | `--dry-run` + `--skip-subs` | "[Quick Test]" announced | ✅ |
| 106 | `--dry-run` + HDR source | "DRY-RUN" announced for HDR input | ✅ |

### 1.10 Video Pipeline (suite: `video`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 107 | Basic SDR → HEVC MP4 | Output exists, codec is `hevc` | ✅ |
| 108 | `--video-codec libx264` | Output codec is `h264` | ✅ |
| 109 | `--output-ext mkv` | Output format is `matroska` | ✅ |
| 110 | `--x265-params "aq-mode=3"` | Encode succeeds with custom x265 params | ✅ |
| 111 | `--threads 2` | Encode succeeds with thread limit | ✅ |
| 112 | `--video-copy-if-compliant` | HEVC source copied without re-encode | ✅ |
| 113 | `--level 5.1` config acceptance | LEVEL_VALUE = 5.1 in effective config | ✅ |
| 114 | `--level 5.1` VBV injection | Dry-run with HDR source includes vbv-maxrate/vbv-bufsize in x265 params | ✅ |

### 1.11 HDR Pipeline (suite: `hdr`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 115 | HDR10-tagged source encode | HEVC output, BT.2020 primaries and SMPTE 2084 transfer preserved | ✅ |
| 116 | `--no-tonemap` config flag | TONEMAP_HDR_TO_SDR = 0 in effective config | ✅ |
| 117 | `--tonemap` + HDR source | Tonemap filter chain (SDR-TONEMAP/zscale) present in dry-run | ✅ |
| 118 | `--profile universal` + HDR source | Tonemap filter chain present in dry-run (profile implies tonemap) | ✅ |

### 1.12 Audio Pipeline (suite: `audio`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 119 | 5.1 source → output has audio | ≥1 audio track | ✅ |
| 120 | Stereo fallback added | ≥2 audio tracks for surround source | ✅ |
| 121 | `--no-stereo-fallback` | Single audio track | ✅ |
| 122 | `--skip-audio` announced | "Audio processing disabled" in output | ✅ |
| 123 | Multi-audio auto-selection | Scoring algorithm prefers surround track | ✅ |
| 124 | `--audio-track 0` override | Specific track selected regardless of scoring | ✅ |
| 125 | `--audio-lang-pref spa` | Spanish audio track selected | ✅ |
| 126 | `--audio-force-codec aac` | Audio transcoded to AAC | ✅ |
| 127 | `--stereo-bitrate 192k` | Config shows 192k in effective config | ✅ |
| 128 | `--audio-lossless-passthrough` | AUDIO_LOSSLESS_PASSTHROUGH = 1 in config | ✅ |
| 129 | `--no-audio-lossless-passthrough` | AUDIO_LOSSLESS_PASSTHROUGH = 0 in config | ✅ |
| 130 | Commentary track deprioritized | Main feature selected over commentary (same codec/ch/lang) | ✅ |
| 131 | `--audio-titles` encode | Output audio stream has descriptive title tag | ✅ |
| 132 | `--no-audio-titles` encode | No descriptive codec title in output audio stream | ✅ |

### 1.13 Subtitle Pipeline (suite: `subs`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 133 | Multi-sub source → MKV | ≥1 subtitle tracks in output | ✅ |
| 134 | `--no-subtitles` | 0 subtitle tracks | ✅ |
| 135 | `--skip-subs` announced | "Subtitle processing disabled" in output | ✅ |
| 136 | `--sub-lang-pref jpn` | SUB_LANG_PREF = jpn in effective config | ✅ |
| 137 | `--no-sub-sdh` | SUB_INCLUDE_SDH = 0 in effective config | ✅ |
| 138 | `--sub-export-external` | Output produced; SRT sidecar(s) created | ✅ |
| 139 | `--no-ocr` | SUB_ENABLE_OCR = 0 in effective config | ✅ |
| 140 | `--ocr-lang jpn` | SUB_OCR_LANG = jpn in effective config | ✅ |
| 141 | `SUB_MAX_TRACKS=1` via config file | Output limited to ≤1 subtitle track | ✅ |
| 142 | `--sub-lang-pref spa` with multilang source | Output subtitle track is Spanish | ✅ |

### 1.14 Output Features (suite: `output`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 143 | `--keep-chapters` | Chapters present in output | ✅ |
| 144 | `--no-keep-chapters` | Chapters stripped | ✅ |
| 145 | `--checksum` | `.sha256` sidecar created | ✅ |
| 146 | `--checksum` SHA-256 validates | Sidecar content matches output file (sha256sum -c) | ✅ |
| 147 | `--report-json` | `.report.json` sidecar created, valid JSON | ✅ |
| 148 | `--report-json` contains tool/version key | `has("tool")` or `has("muxm_version")` or `has("version")` | ✅ |
| 149 | `--report-json` contains source/input key | `has("source")` or `has("input")` or `has("src")` | ✅ |
| 150 | `--report-json` contains profile key | `has("profile")` | ✅ |
| 151 | `--report-json` contains output key | `has("output")` | ✅ |
| 152 | `--report-json` contains timestamp key | `has("timestamp")` | ✅ |
| 153 | `--report-json` content validation | Profile name, tool name, source, output, timestamp present in JSON | ✅ |
| 154 | `--skip-if-ideal` with compliant source | Recognized as compliant or produced output | ✅ |
| 155 | `--keep-temp-always` (`-K`) | Workdir preserved on successful encode | ✅ |
| 156 | `--keep-temp` (`-k`) | KEEP_TEMP registered in effective config | ✅ |
| 156c | `--max-copy-bitrate 50000k` config | MAX_COPY_BITRATE = 50000k in effective config | ✅ (via toggles suite) |
| 156d | `--force-replace-source` | Source file replaced atomically with output | ✅ (via collision suite) |
| 156e | Source collision auto-versioning | Source = output (no replace flag) → output renamed to `file(1).ext` | ✅ (via collision suite) |
| 156f | `--replace-source` non-TTY rejection | Exits 11 when stdin is not a TTY | ✅ (via collision suite) |

### 1.15 Container Formats (suite: `containers`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 157 | `--output-ext mov` | Output produced, container is MOV/MP4 family | ✅ |
| 158 | `--output-ext m4v` | Output produced, container is MP4 family | ✅ |

### 1.16 Metadata & Miscellaneous Flags (suite: `metadata`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 159 | `--strip-metadata` real encode | Title and comment removed from output | ✅ |
| 160 | Metadata preservation (no flag) | Title preserved in output | ✅ |
| 161 | `--ffmpeg-loglevel warning` | Accepted without error | ✅ |
| 162 | `--no-hide-banner` | Accepted without error | ✅ |
| 163 | `--ffprobe-loglevel warning` | Accepted without error | ✅ |
| 163a | `--output-ext mkv` full encode | Output produced, MKV container | ✅ (via video suite) |
| 163c | `DISK_FREE_WARN_GB` warning | Encode on nearly-full volume emits disk space warning | ❌ |

### 1.17 Edge Cases & Security (suite: `edge`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 164 | Empty source file | Rejected with error | ✅ |
| 165 | Filename with spaces | Handled correctly | ✅ |
| 166 | Control character in filename | Tab in source filename → exit 11, "control characters" error | ✅ |
| 167 | Source/output collision (explicit) | Same file as source and output → exit 11, "same file" error | ✅ |
| 168 | Invalid `--output-ext webm` (enhanced) | Exit 11 + error message names OUTPUT_EXT | ✅ |
| 169 | Invalid `--video-codec vp9` (enhanced) | Exit 11 + error message mentions invalid codec | ✅ |
| 170 | `--no-overwrite` (enhanced) | Exit 11 + error message mentions "already exists" | ✅ |
| 171 | `--output-ext "mp4;"` | Rejected (injection prevention) | ✅ |
| 172 | `--ocr-tool "sub2srt;rm -rf /"` | Rejected (injection prevention) | ✅ |
| 173 | `--skip-video` | Behavior validated (can't produce output) | ✅ |
| 174 | Non-readable source file | Rejected with "not readable" error | ✅ |
| 175 | Non-writable output directory | Rejected with "not writable" error | ✅ |
| 176 | Double-dash (`--`) argument terminator | Source after `--` parsed as positional arg | ✅ |
| 177 | Double-dash stops option parsing | Hyphen-prefixed filename after `--` does not trigger "Unknown option" | ✅ |
| 178 | Auto-generated output path | Source-only invocation (no explicit output) derives filename with swapped extension | ✅ |
| 178a | Non-writable output directory | Rejected with "not writable" error | ✅ |
| 178b | `--ocr-tool` injection (shell metachar) | `--ocr-tool "sub2srt;rm -rf /"` → OCR disabled, security warning | ✅ |
| 178c | Output control char in filename | Output path with control chars → exit 11, "control characters" error | ❌ |
| 178d | `--replace-source` non-interactive | `echo n | muxm --replace-source ...` → exits 11 (stdin not TTY) | ❌ |
| 178e | `--max-copy-bitrate` with non-k format | Edge: empty string, missing k suffix, "0k" | ❌ |
| 178f | Source collision auto-version loop | Source = output with existing `(1)` file → output becomes `(2)` | ❌ |

### 1.18 Profile End-to-End Encodes (suite: `e2e`)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 179 | `streaming` full encode | Output exists, correct extension (.mp4) | ✅ |
| 180 | `animation` full encode | Output exists (MKV) | ✅ |
| 181 | `universal` full encode | Output exists, codec is H.264 | ✅ |
| 182 | `dv-archival` full encode | Output exists (.mkv), HEVC preserved, audio present | ✅ |
| 183 | `hdr10-hq` full encode | Output exists (.mkv), HEVC codec, 10-bit pixel format | ✅ |
| 184 | `atv-directplay-hq` full encode | Output exists (.mp4), HEVC codec, audio present | ✅ |

### 1.19 Pure-Function Unit Tests (suite: `unit`)

Direct tests for deterministic helper functions extracted from muxm and run in isolation. Validates edge cases not exercised by encode pipelines.

#### Audio Helpers

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 185 | `_channel_label(1,short)` | Returns "mono" | ✅ |
| 186 | `_channel_label(2,short)` | Returns "stereo" | ✅ |
| 187 | `_channel_label(6,short)` | Returns "5.1" | ✅ |
| 188 | `_channel_label(8,short)` | Returns "7.1" | ✅ |
| 189 | `_channel_label(4,short)` | Returns "4ch" | ✅ |
| 190 | `_channel_label(6,long)` | Returns "5.1 Surround" | ✅ |
| 191 | `_channel_label(1,long)` | Returns "Mono" | ✅ |
| 192 | `_audio_descriptive_title(eac3,6)` | Returns "5.1 Surround (E-AC-3)" | ✅ |
| 193 | `_audio_descriptive_title(aac,2)` | Returns "Stereo (AAC)" | ✅ |
| 194 | `_audio_descriptive_title(truehd,8)` | Returns "7.1 Surround (TrueHD)" | ✅ |
| 195 | `_audio_descriptive_title(pcm_s16le,2)` | Returns "Stereo (PCM)" | ✅ |
| 196 | `_audio_codec_rank(eac3)` | Returns 2 | ✅ |
| 197 | `_audio_codec_rank(ac3)` | Returns 3 | ✅ |
| 198 | `_audio_codec_rank(truehd)` | Returns 0 | ✅ |
| 199 | `_audio_codec_rank(aac)` | Returns 4 | ✅ |
| 200 | `_audio_codec_rank(unknown)` | Returns 10 (fallback) | ✅ |
| 201 | `_audio_is_commentary` | Matches: "Director's Commentary", "Audio Description", "Comentario del director". Rejects: "Main Feature", "" | ✅ |
| 202 | `audio_is_direct_play_copyable` | aac, alac, ac3, eac3 → copyable. truehd, dts, flac, opus → not copyable | ✅ |
| 203 | `audio_is_lossless` | truehd, dts, dca, flac, alac, pcm_s16le, pcm_s24le, pcm_s32le → lossless. aac, eac3, ac3, opus → lossy | ✅ |
| 204 | `audio_transcode_target` | 8ch → eac3 768k, 6ch → eac3 640k, 2ch → aac, 1ch → aac | ✅ |
| 205 | `_audio_lang_matches` | Matches eng/spa in "eng,spa" pref. Rejects fra, und, "". Single-pref match works | ✅ |
| 206 | `audio_lossless_muxable` | truehd+matroska ✅, flac+matroska ✅, alac+mp4 ✅, flac+mp4 ✅, truehd+mp4 ❌, dts+mp4 ❌, alac+mov ✅, truehd+mov ❌ | ✅ |

#### Subtitle Helpers

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 207 | `_is_forced_title` | Matches: "Forced", "Signs & Songs", "Foreign Parts Only". Rejects: "English", "" | ✅ |
| 208 | `_is_sdh_title` | Matches: "English SDH", "English (CC)", "Hearing Impaired", "HI". Rejects: "English", "history", "" | ✅ |
| 209 | `_is_text_sub_codec` | Text: subrip, ass, mov_text, webvtt. Bitmap: hdmv_pgs_subtitle, dvd_subtitle | ✅ |

#### Validation Helpers

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 210 | `is_valid_loglevel` | quiet, error, warning, info, verbose, debug, trace → valid. "bogus", "" → invalid | ✅ |
| 211 | `is_valid_preset` | ultrafast, medium, slow, slower, veryslow, placebo, fast → valid. "bogus", "" → invalid | ✅ |
| 212 | `_is_valid_profile` | All 6 profiles → valid. "nonexistent", "" → invalid | ✅ |
| 213 | `_valid_profiles_display` | Returns comma-separated list containing "streaming" and "universal" | ✅ |

#### File Size Utility

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 214 | `filesize_pretty(nonexistent)` | Returns "not found" | ✅ |
| 215 | `filesize_pretty(0 bytes)` | Returns "0 bytes" | ✅ |
| 216 | `filesize_pretty(512 bytes)` | Returns "512 bytes" | ✅ |
| 217 | `filesize_pretty(1 KB)` | Contains "KB" | ✅ |
| 218 | `filesize_pretty(~1.5 MB)` | Contains "MB" | ✅ |

#### Audio Copy Extension Mapping

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 218a | `_audio_copy_ext(truehd)` | Returns "thd" | ✅ |
| 218b | `_audio_copy_ext(alac)` | Returns "m4a" | ✅ |
| 218c | `_audio_copy_ext(pcm_s24le)` | Returns "wav" | ✅ |
| 218d | `_audio_copy_ext(dca)` | Returns "dts" | ✅ |
| 218e | `_audio_copy_ext(ac3)` | Returns "ac3" (passthrough) | ✅ |
| 218f | `_audio_copy_ext(aac)` | Returns "aac" (passthrough) | ✅ |

#### Codec Channel Limits

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 218g | `_codec_max_channels(eac3)` | Returns 6 | ✅ |
| 218h | `_codec_max_channels(ac3)` | Returns 6 | ✅ |
| 218i | `_codec_max_channels(aac)` | Returns 48 | ✅ |
| 218j | `_codec_max_channels(unknown)` | Returns 64 (fallback) | ✅ |

#### Container Compatibility (skip-if-ideal)

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 218k | `_sii_audio_is_container_safe` | truehd+mp4 ❌, dts+mp4 ❌, pcm_s16le+mp4 ❌, aac+mp4 ✅, eac3+mp4 ✅, truehd+matroska ✅ | ✅ |

#### Path Resolution

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 218o | `realpath_fallback` with relative path | Returns absolute path | ✅ |
| 218p | `realpath_fallback` with non-existent file | Returns valid absolute path (dir resolved + base appended) | ✅ |

#### VBV Level Mapping

| # | Test | Assertion | Auto |
|---|------|-----------|------|
| 218q | `apply_level_vbv 4.1` | x265-params includes vbv-maxrate=10000k and vbv-bufsize=20000k | ✅ |
| 218r | `apply_level_vbv 5.0` | x265-params includes vbv-maxrate=25000k and vbv-bufsize=50000k | ✅ |
| 218s | `apply_level_vbv 5.1` | x265-params includes vbv-maxrate=40000k and vbv-bufsize=80000k | ✅ |
| 218t | `apply_level_vbv 5.2` | x265-params includes vbv-maxrate=60000k and vbv-bufsize=120000k | ✅ |
| 218u | `apply_level_vbv` unknown level | level-idc appended but no vbv-maxrate | ✅ |
| 218v | `apply_level_vbv` with CONSERVATIVE_VBV=0 | No vbv-maxrate injected; level-idc still appended | ✅ |

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

### 2.10 Multi-Track Audio (dv-archival)

> **Requires:** Source with 3+ audio tracks in mixed languages/codecs

| # | Test | Steps | Expected Result |
|---|------|-------|-----------------|
| M49 | Multi-track all kept | `muxm --profile dv-archival multilang_audio.mkv` | All audio tracks from source present in output (stream-copied, no transcode) |
| M50 | Language filtering | Set `AUDIO_LANG_PREF="eng,jpn"` in `.muxmrc`, run `dv-archival` on 3-lang source | Only eng and jpn tracks kept; other languages dropped with log message |
| M51 | Commentary filtering | Source with main + commentary tracks, `AUDIO_KEEP_COMMENTARY=0` (default) | Commentary track dropped, main feature kept |
| M52 | Commentary kept | `AUDIO_KEEP_COMMENTARY=1` in `.muxmrc`, same source | Both main and commentary tracks present in output |
| M53 | Multi-track titles | `--audio-titles` with multi-track source | Each track has descriptive title (e.g., "5.1 Surround (TrueHD)") |

### 2.11 Multi-Track Subtitles (dv-archival / animation)

> **Requires:** Source with 4+ subtitle tracks (mixed forced/full/SDH, mixed languages)

| # | Test | Steps | Expected Result |
|---|------|-------|-----------------|
| M54 | Multi-track all kept | `muxm --profile animation anime_6subs.mkv` | All 6 subtitle tracks present in output (stream-copied) |
| M55 | Language filtering | `SUB_LANG_PREF="eng,jpn"` in `.muxmrc`, run on multi-lang sub source | Only eng and jpn subtitle tracks kept |
| M56 | `SUB_MAX_TRACKS` cap | Source with 8 subs, `SUB_MAX_TRACKS=4` | At most 4 subtitle tracks in output |
| M57 | SDH exclusion in multi-track | `SUB_INCLUDE_SDH=0` with multi-track subs | SDH tracks dropped, forced and full kept |
| M58 | PGS bitmap preservation | `--profile animation` with PGS bitmap subs in MKV | PGS subs stream-copied intact (not OCR'd) |

### 2.12 Source Replacement

> **Requires:** Expendable test file (will be overwritten)

| # | Test | Steps | Expected Result |
|---|------|-------|-----------------|
| M59 | `--replace-source` interactive | `muxm --replace-source --preset ultrafast test.mkv`, answer "y" | Original file replaced atomically; output at same path |
| M60 | `--replace-source` declined | Same as above, answer "n" | "Aborted" message, source untouched |
| M61 | `--force-replace-source` | `muxm --force-replace-source --preset ultrafast test.mkv` | No prompt; original replaced atomically |
| M62 | `--replace-source` non-TTY | `echo y \| muxm --replace-source test.mkv` | Exits 11 with "requires interactive terminal" error |
| M63 | Auto-versioning | `muxm test.mp4` where source is already `.mp4` | Output renamed to `test(1).mp4` with note about collision |

### 2.13 DV Container Verification

> **Requires:** Real DV source, `dovi_tool`, `MP4Box`

| # | Test | Steps | Expected Result |
|---|------|-------|-----------------|
| M64 | dvcC box verified | `muxm --profile atv-directplay-hq dv_source.mkv` | "DOVI configuration record confirmed" in output |
| M65 | mp4box fallback | Remove mp4box from PATH, encode DV to MP4 | ffmpeg-direct fallback attempted; warning if dvcC missing |
| M66 | DV pre-wrap with mp4box | Normal DV encode to MP4 with mp4box available | "DV pre-wrap succeeded (mp4box)" in output |
| M67 | RPU frame count verification | DV encode with matching frame counts | "RPU frame count verified" in output |
| M68 | RPU frame count mismatch | DV source with framerate change | ⚠️ "RPU frame count mismatch" warning |
| M69 | DV P5 dual-layer handling | Profile 5 source | ⚠️ appropriate warning about dual-layer; converts to P8.1 or falls back |
| M70 | DV compat_id HLG mismatch | P7 DV with HLG compat_id=4, encode to MP4 | ⚠️ warning about HLG→PQ compat_id change |

### 2.14 SDR 10-Bit Forcing & Pixel Format

> **Requires:** SDR 8-bit source, SDR 10-bit source

| # | Test | Steps | Expected Result |
|---|------|-------|-----------------|
| M71 | `--sdr-force-10bit` on 8-bit | SDR 8-bit source + `--sdr-force-10bit` | Output is 10-bit (yuv420p10le) even though source is 8-bit |
| M72 | `SDR_USE_10BIT_IF_SRC_10BIT` | SDR 10-bit source (default config) | Output preserves 10-bit pixel format |
| M73 | `--no-sdr-force-10bit` | SDR 8-bit source + `--no-sdr-force-10bit` | Output is 8-bit (yuv420p) matching source |
| M74 | `--profile animation` 10-bit | SDR 8-bit anime source | Output is 10-bit (animation profile forces 10-bit for gradient quality) |

### 2.15 Max Copy Bitrate

> **Requires:** High-bitrate source (e.g., Blu-ray remux >50 Mbps)

| # | Test | Steps | Expected Result |
|---|------|-------|-----------------|
| M75 | Copy rejected (high bitrate) | `--video-copy-if-compliant --max-copy-bitrate 30000k` on 60 Mbps source | Re-encodes (bitrate exceeds ceiling) |
| M76 | Copy accepted (low bitrate) | `--video-copy-if-compliant --max-copy-bitrate 80000k` on 40 Mbps source | Stream-copied (bitrate within limit) |
| M77 | Bitrate fallback estimation | Source where ffprobe `bit_rate` field is unavailable (some MKV) | Fallback to file_size*8/duration; logged in workdir |

### 2.16 Operational Features

| # | Test | Steps | Expected Result |
|---|------|-------|-----------------|
| M78 | Disk space warning | Encode to a volume with < 5 GB free | ⚠️ "Less than ~5GB free" warning at start |
| M79 | `DISK_FREE_WARN_GB` custom | Set `DISK_FREE_WARN_GB=20` in `.muxmrc`, encode with 10 GB free | ⚠️ warning triggers at higher threshold |
| M80 | `DEBUG=1` mode | `DEBUG=1 muxm --profile streaming --preset ultrafast test.mkv` | `set -x` trace output visible; encode completes; temp files preserved |
| M81 | macOS hidden flag cleared | Encode on macOS (APFS) | Output file is not hidden in Finder (chflags nohidden) |
| M82 | Duration detection tiers | MKV without standard duration field (relies on Matroska tags) | Progress bar shows percentage (duration detected from tier 3: Matroska DURATION tag) |

---

## 3. Test Media Library

For complete manual testing, maintain a set of reference files:

| File | Description | Tests Covered |
|------|-------------|---------------|
| `dv_p7_truehd71.mkv` | DV Profile 7 + TrueHD 7.1 + PGS subs | M1–M7, M16, M19, M23, M64–M67 |
| `dv_p5_duallayer.mkv` | DV Profile 5 (dual-layer) | M69 |
| `dv_p7_hlg.mkv` | DV Profile 7 with HLG compat_id=4 | M70 |
| `dv_p81_eac3.mp4` | DV Profile 8.1 + EAC3 5.1 (already ATV-compliant) | M30–M32 |
| `hdr10_atmos.mkv` | HDR10 + Atmos TrueHD + SRT subs | M8–M12, M16, M21 |
| `hlg_aac51.mkv` | HLG + AAC 5.1 | M10 |
| `sdr_h264_ac3.mkv` | H.264 SDR + AC3 5.1 + 3 audio tracks | M16–M18, M20 |
| `sdr_8bit.mkv` | H.264 SDR 8-bit + AAC | M71, M73 |
| `sdr_10bit.mkv` | HEVC SDR 10-bit + AAC | M72 |
| `anime_ass_flac.mkv` | HEVC SDR + FLAC + styled ASS subs (6 tracks) | M24, M28, M54, M58, M74 |
| `forced_pgs.mkv` | HEVC + PGS forced + PGS full + PGS SDH | M23, M25, M27, M29 |
| `multilang.mkv` | Multiple audio/sub languages (eng, jpn, fre) | M17, M50, M55 |
| `multilang_audio_commentary.mkv` | 4 audio tracks: eng main, eng commentary, jpn, fre | M49–M53 |
| `multi_subs_8tracks.mkv` | 8 subtitle tracks (mixed lang/type) | M56, M57 |
| `high_bitrate_remux.mkv` | HEVC 60+ Mbps Blu-ray remux | M75–M77 |

---

## 4. Regression Test Checklist

Run after every code change:

```bash
# 1. Fast automated suite (< 2 min)
./test_muxm.sh --muxm ./muxm --suite all

# 2. Quick smoke test with real media (if available)
muxm --dry-run --profile atv-directplay-hq real_source.mkv
muxm --dry-run --profile universal real_source.mkv
muxm --dry-run --profile dv-archival real_source.mkv

# 3. If video pipeline changed: one real encode
muxm --profile streaming --preset ultrafast --crf 28 real_source.mkv /tmp/regression_test.mp4

# 4. If audio pipeline changed:
muxm --preset ultrafast --crf 28 multi_audio_source.mkv /tmp/audio_test.mp4
ffprobe -v error -show_streams -of json /tmp/audio_test.mp4 | jq '[.streams[] | select(.codec_type=="audio")] | length'

# 5. If multi-track audio/sub changed (dv-archival / animation):
muxm --profile dv-archival multi_audio_source.mkv /tmp/archival_test.mkv
ffprobe -v error -show_streams -of json /tmp/archival_test.mkv | jq '[.streams[] | select(.codec_type=="audio")] | length'
muxm --profile animation anime_source.mkv /tmp/anime_test.mkv
ffprobe -v error -show_streams -of json /tmp/anime_test.mkv | jq '[.streams[] | select(.codec_type=="subtitle")] | length'

# 6. If config/profile changed:
muxm --profile <changed-profile> --print-effective-config

# 7. If source replacement changed:
cp test.mkv /tmp/replace_test.mkv
muxm --force-replace-source --preset ultrafast --crf 28 /tmp/replace_test.mkv
```

---

## 5. CI Integration Notes

The automated test harness is designed for CI. Key integration points:

- **Exit codes:** 0 = all pass, 1 = any failure
- **No network required:** All test media is generated locally via ffmpeg
- **No real media required:** Synthetic 2-second clips cover pipeline mechanics
- **Suite isolation:** Run individual suites for targeted checks (`--suite cli` for fast, `--suite e2e` for full encodes)
- **Runtime:** `cli` + `toggles` + `unit` + `completions` + `setup` + `config` + `profiles` + `conflicts` + `dryrun` ≈ 15 seconds. Full `e2e` ≈ 60–120 seconds depending on CPU.
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
      - name: Run all tests
        run: ./test_muxm.sh --muxm ./muxm --suite all
      - name: Locale regression (LANG=C)
        run: LANG=C LC_ALL=C ./test_muxm.sh --muxm ./muxm --suite all
```

### Locale Regression Testing

All locale-sensitive operations in `muxm` have been audited (see comment block in
Section 1 of the script). The script is locale-safe by design:

| Category | Count | Status | Notes |
|----------|-------|--------|-------|
| `_lower()` via `tr` | 1 | ✅ Guarded | `LC_ALL=C` prefix already present |
| `${var,,}` (Bash builtin) | 19 | ✅ Safe | Locale-independent for ASCII input |
| `grep -i` with ASCII patterns | 20 | ✅ Safe | Patterns are pure ASCII (DOVI, dolby, etc.) |
| `=~` with `[0-9]` ranges | 21 | ✅ Safe | POSIX-defined, locale-independent |
| `=~` with `[a-zA-Z0-9]` | 1 | ✅ Safe | OCR tool sanitization (reject-list; conservative direction) |
| `sort` | 0 | ✅ N/A | — |
| `printf` locale formatting | 0 | ✅ N/A | — |

**Running the locale test:**

```bash
# Full suite under C locale (should produce identical results to default locale)
LANG=C LC_ALL=C ./test_muxm.sh --muxm ./muxm --suite all

# Quick smoke test (fast suites only)
LANG=C LC_ALL=C ./test_muxm.sh --muxm ./muxm --suite cli
```

If any tests fail under `LANG=C` that pass under the default locale, investigate
whether the failing `tr`/`grep`/`sed`/`sort` call needs a `LC_ALL=C` prefix.

---

## 6. Coverage Gap Analysis

| Area | Automated | Manual Required | Notes |
|------|-----------|-----------------|-------|
| CLI parsing | ✅ Full | — | Includes --no-overwrite, short aliases (-h, -V, -p, -l, -k, -K), control char rejection, enhanced error messages |
| Toggle flags | ⚠️ Partial | — | 15 toggle pairs validated; 20+ toggles missing (sdr-force-10bit, sub-preserve-format, dv, tonemap, replace-source, and positive sides of existing negatives) |
| Pure-function unit tests | ⚠️ Partial | — | Audio helpers, subtitle helpers, validation helpers, filesize utility tested; missing: `_audio_copy_ext`, `_codec_max_channels`, `_sii_audio_is_container_safe`, `realpath_fallback`, `apply_level_vbv` per-level, VBV level mapping |
| Completions installer | ✅ Full | — | Install, idempotency, uninstall, safe-when-absent |
| Setup combined installer | ✅ Full | — | All three sub-installers + standalone deps/man |
| Config precedence | ✅ Full | — | Single-layer, multi-layer (user+project+CLI), all --create-config profiles, loglevel validation, deprecated variable migration |
| Profile defaults | ✅ Full | — | All 6 profiles validated |
| Conflict warnings | ⚠️ Partial | — | 23 combinations tested; ~15 missing (dv-archival multi-track conflicts, MOV container warnings, hdr10-hq+DV re-enabled, animation+no-sub-preserve-format, universal+DV, cross: tonemap+libx265) |
| Dry-run mode | ✅ Full | — | Includes HDR source dry-run |
| Video encode (SDR) | ✅ Full | — | Includes x265-params, threads, video-copy-if-compliant, --level VBV |
| Video encode (HDR) | ⚠️ Tagged only | Real HDR quality (M8–M15) | Synthetic clips have HDR tags but no real HDR content; tonemap filter chain verified in dry-run |
| Container formats | ✅ Full | — | MOV, M4V, and MKV validated |
| Metadata stripping | ✅ Full | — | Strip and preserve verified with ffprobe; --ffprobe-loglevel tested |
| Audio titles | ✅ Full | — | --audio-titles and --no-audio-titles both tested with real encodes |
| Subtitle track limiting | ✅ Full | — | SUB_MAX_TRACKS=1 via config file and --sub-lang-pref multilang tested |
| SDR 10-bit forcing | ❌ None | Visual/probe (M71–M74) | --sdr-force-10bit and SDR_USE_10BIT_IF_SRC_10BIT untested |
| Max copy bitrate | ❌ None | Bitrate-gated copy (M75–M77) | --max-copy-bitrate ceiling logic untested |
| Multi-track audio (dv-archival) | ❌ None | Multi-track filter (M49–M53) | AUDIO_MULTI_TRACK, AUDIO_KEEP_COMMENTARY, language filtering untested |
| Multi-track subtitles (archival/animation) | ❌ None | Multi-track filter (M54–M58) | SUB_MULTI_TRACK, language filtering, SUB_MAX_TRACKS cap untested |
| Source replacement & collision | ✅ Full | Interactive prompt (M59–M60) | Auto-versioning, --force-replace-source, non-TTY rejection, --help/config registration all tested; interactive --replace-source confirmation requires TTY |
| Dolby Vision | ❌ None | Full DV pipeline (M1–M7, M64–M70) | Requires real DV source + dovi_tool + MP4Box |
| DV container verification | ❌ None | dvcC box checks (M64–M68) | verify_dv_container_record, pre-wrap, mp4box fallback untested |
| DV P7/P5→P8.1 conversion | ❌ None | Profile conversion (M69–M70) | dovi_tool convert pipeline untested |
| HDR10 static metadata check | ❌ None | M7 | _check_hdr10_static_metadata untested |
| Tone-mapping quality | ❌ None | Visual evaluation (M13–M15) | Requires HDR source + human judgment |
| Audio scoring | ✅ Partial | Complex multi-track (M16–M22) | Auto-selection, track override, language pref, force-codec, commentary detection tested; subjective quality not covered |
| Audio quality | ❌ None | Listening test (M22) | Subjective |
| Subtitle pipeline | ✅ Partial | PGS OCR, burn-in, styling (M23–M29) | Config flags, external export, track counts, and lang selection verified; OCR and visual burn-in require real media |
| Subtitle OCR | ❌ None | PGS → SRT (M23) | Requires pgsrip/tesseract + PGS source |
| Subtitle burn-in | ❌ None | Visual verification (M25) | Requires forced-sub source + eyes |
| ASS/SSA styling | ❌ None | Visual verification (M24) | Requires styled ASS source + eyes |
| Skip-if-ideal | ⚠️ Partial | Full roundtrip (M30–M32) | Basic compliant-source test exists; multi-track audio/sub filtering in ideal-check untested |
| Output features | ✅ Full | — | Chapters, checksum (with validation), JSON report (content + key checks), keep-temp all tested |
| Edge cases & security | ✅ Full | — | Includes permissions, control chars, collision prevention, double-dash terminator, auto-generated output path, injection prevention |
| E2E profiles | ✅ Full | — | All 6 profiles validated with real encodes |
| VALID_PROFILES drift | ✅ Full | — | Cross-reference test verifies --help and installed completions match canonical constant |
| Locale regression | ✅ Full | — | Static audit complete; CI step: `LANG=C LC_ALL=C ./test_muxm.sh` |
| Duration detection | ❌ None | M82 | Three-tier duration lookup (_get_source_duration_secs) untested |
| Progress bar / spinner | ❌ None | Visual | ffmpeg_progress_bar, spinner, run_with_spinner — UI functions |
| Disk space preflight | ❌ None | M78–M79 | DISK_FREE_WARN_GB threshold and warning untested |
| macOS APFS hidden flag | ❌ None | M81 | chflags nohidden after atomic move untested |
| Error recovery | ❌ None | SIGINT, disk full (M33–M38) | Requires manual intervention |
| Cross-platform | ❌ None | macOS + Linux (M39–M42) | Requires both platforms |
| Playback verification | ❌ None | Device testing (M43–M48) | Requires target hardware |

### Untested Areas — Candidates for New Tests

The following areas are present in muxm but have no or incomplete automated test coverage. Items are ranked by risk (impact of a silent regression):

**Critical Priority (new features with zero coverage):**

1. **Toggle flag completeness** — 20+ toggles lack the positive or negative counterpart in the toggle suite. Adding `--sdr-force-10bit`, `--no-sdr-force-10bit`, `--sub-preserve-format`, `--no-sub-preserve-format`, `--dv`, `--no-dv`, `--tonemap`, `--no-tonemap`, `--skip-if-ideal`, `--report-json`, `--checksum`, `--strip-metadata`, `--keep-chapters`, `--sub-burn-forced`, `--sub-export-external`, `--video-copy-if-compliant`, `--replace-source`, and `--force-replace-source` would make the toggle suite truly exhaustive.

2. **Multi-track audio filtering (dv-archival)** — `_build_audio_keep_list()`, `run_audio_pipeline_multi()`, `AUDIO_MULTI_TRACK`, `AUDIO_KEEP_COMMENTARY`, and language-based filtering have no automated coverage. A synthetic multi-audio fixture could enable automated filter verification.

3. **Multi-track subtitle filtering (dv-archival/animation)** — `_build_subtitle_keep_list()`, `SUB_MULTI_TRACK`, language/type filtering, and `SUB_MAX_TRACKS` cap in multi-track mode have no automated coverage.

4. **Conflict warnings: remaining ~15 combinations** — dv-archival multi-track conflicts (--audio-track, --audio-force-codec, --stereo-fallback, --sub-export-external), MOV container warnings for all profiles, hdr10-hq + DV re-enabled, animation + --no-sub-preserve-format, universal + --dv, and cross-profile tonemap+libx265 are all untested.

**High Priority:**

5. **`_audio_copy_ext()` unit tests** — Maps codec names to ffmpeg-compatible file extensions for intermediate copy files. truehd→thd, alac→m4a, pcm→wav, dca→dts. Incorrect mapping causes "Unable to choose output format" errors.

6. **`_codec_max_channels()` unit tests** — Returns encoder channel limits (eac3→6, ac3→6). If this returns wrong values, ffmpeg fatally errors with "channel layout not supported."

7. **`_sii_audio_is_container_safe()` unit tests** — Container compatibility gate for skip-if-ideal remux. truehd+mp4→reject, aac+mp4→accept. Wrong results cause mux failures on the "ideal" fast path.

8. **`apply_level_vbv()` per-level unit tests** — VBV parameter injection for levels 4.1, 5.0, 5.1, 5.2. Currently only 5.1 tested via a real encode; a unit test confirming exact maxrate/bufsize values for each level would be deterministic.

9. **`--install-man` standalone** — Only tested indirectly via `--setup`. A standalone invocation test would catch regressions in the man page generator.

10. **`--create-config user` and `--create-config system` scopes** — Only the `project` scope is explicitly tested. The `user` scope writes to `~/.muxmrc` (testable with isolated HOME).

**Medium Priority:**

11. **`select_best_audio()` scoring integration** — Unit tests cover individual scoring helpers but not the top-level function that combines them. A unit test with mock multi-track probe output would verify the complete scoring pipeline.

12. **`decide_color_and_pixfmt()` unit tests** — Determines HDR color metadata and pixel format. Currently only tested indirectly via HDR encode outputs.

13. **`check_skip_if_ideal()` multi-track path** — The skip-if-ideal function has a multi-track audio/subtitle code path that is untested (requires ideal multi-track source).

14. **`build_subtitle_plan()` unit tests** — Complex subtitle selection (forced detection, SDH filtering, language preference, max-tracks limiting).

15. **`realpath_fallback()` unit tests** — Cross-platform path resolution. A direct test with symlinks, relative paths, and non-existent files would improve portability confidence.

16. **`_validate_media_file()` unit tests** — Beyond empty-file and non-readable tests, validate behavior with video-only, audio-only, and other unusual layouts.

17. **`DEBUG=1` mode** — Running a fast suite with `DEBUG=1` as a smoke test would catch cases where debug tracing breaks parsing or output.

18. **`AUDIO_CODEC_PREFERENCE` custom ordering** — A config-file override of `AUDIO_CODEC_PREFERENCE` is not tested to verify user-customized rankings propagate correctly.

19. **`--preset` validation boundary** — CLI parser rejection of `--preset bogus` with proper error message could use an explicit test.

20. **`ffmpeg_has_muxer()` unit tests** — Container format support detection with known-good and known-bad muxer names.

21. **`_get_source_duration_secs()` three-tier lookup** — Duration detection from stream, format, and Matroska tags. A synthetic MKV with only Matroska DURATION tags would test tier 3 specifically.

22. **`_check_hdr10_static_metadata()` unit tests** — Detection of mastering display and content light level data. Currently only exercised via real DV sources.

**Lower Priority:**

23. **Multi-pass config layering with profile conflicts** — Test where user config sets a profile, project config overrides a conflicting variable, and CLI adds another conflict. Verify all expected warnings.

24. **Bash version guard** — Verify running under bash 3.2 produces the expected error message and exit.

25. **Progress bar / spinner functions** — `ffmpeg_progress_bar()`, `run_with_spinner()`, and `spinner()` are UI functions. Smoke-test coverage (verify no error when called) would help.

26. **Disk space preflight (`disk_free_warn`)** — Difficult to automate (requires a nearly-full volume) but could be mocked.

27. **macOS APFS hidden flag** — `chflags nohidden` after atomic move. Only testable on macOS with APFS.

28. **`_detect_mp4box()` cross-platform** — Detect MP4Box (macOS) vs mp4box (Linux). Could be tested by mocking PATH.

---

## 7. Synthetic Test Media Fixtures

The test harness generates these fixtures automatically:

| Fixture | Type | Contents | Suites Using It |
|---------|------|----------|-----------------|
| `basic_sdr_subs.mkv` | Core | H.264 + AAC stereo + SRT subtitle | cli, dryrun, video, edge, output, metadata, e2e |
| `hevc_sdr_51.mkv` | Extended | HEVC 10-bit + AC3 5.1 | video, audio, e2e |
| `hevc_hdr10_tagged.mkv` | Extended | HEVC 10-bit + HDR10-like color tags + EAC3 | hdr, dryrun, e2e |
| `multi_audio.mkv` | Extended | H.264 + 3 audio tracks (stereo AAC, 5.1 EAC3, stereo commentary) | audio |
| `multi_audio_commentary.mkv` | Extended | H.264 + 2 × 5.1 EAC3 eng (commentary vs main feature) | audio |
| `multi_subs.mkv` | Extended | H.264 + 3 subtitle tracks (forced, full, SDH) | subs, e2e |
| `multi_subs_multilang.mkv` | Extended | H.264 + 3 subtitle tracks (eng, spa, fra) | subs |
| `multi_lang_audio.mkv` | Extended | H.264 + 2 audio tracks (eng AAC, spa AAC) | audio |
| `with_chapters.mkv` | Extended | H.264 + AAC + 2 chapters | output |
| `compliant.mp4` | Extended | HEVC 10-bit + EAC3 in MP4 (for skip-if-ideal) | output |
| `rich_metadata.mkv` | Extended | H.264 + AAC + title/comment/encoder tags | metadata |

### Candidate fixtures for new test coverage

These fixtures do not yet exist in the test harness but would enable automated testing of currently-manual-only features:

| Fixture | Contents | Tests It Would Enable |
|---------|----------|----------------------|
| `multi_audio_4track.mkv` | H.264 + 4 audio tracks (eng main, eng commentary, jpn, fre) | Multi-track audio filtering, AUDIO_KEEP_COMMENTARY, language filter |
| `multi_subs_6track.mkv` | H.264 + 6 subtitle tracks (eng forced, eng full, eng SDH, jpn full, fra full, spa full) | Multi-track subtitle filtering, SUB_MAX_TRACKS cap, language filter |
| `sdr_8bit.mkv` | H.264 8-bit SDR + AAC | SDR_FORCE_10BIT, SDR_USE_10BIT_IF_SRC_10BIT pixel format testing |
| `collision_source.mp4` | HEVC + AAC in MP4 | Source/output collision auto-versioning |
| `lossless_audio.mkv` | HEVC + TrueHD 7.1 + FLAC stereo | Audio copy extension mapping, lossless muxability, container safety |