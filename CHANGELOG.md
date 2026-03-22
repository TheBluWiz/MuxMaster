# Changelog

All notable changes to MuxMaster will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com), and this project adheres to [Semantic Versioning](https://semver.org).

## [Unreleased]

Multi-track audio and subtitles for `dv-archival`: the profile now keeps all audio and subtitle tracks from the source instead of scoring and selecting one. Commentary/descriptive audio tracks are dropped by default. All surviving tracks are stream-copied (never transcoded). Configurable via `.muxmrc`.

### Added

- **Multi-track audio pipeline** (`AUDIO_MULTI_TRACK=1`) — New audio mode that keeps all matching audio tracks instead of selecting a single best track. Audio streams are mapped directly from source with `-c:a copy` (no intermediate extraction, no transcoding, no temp files). Controlled by two new config variables:
  - `AUDIO_MULTI_TRACK` — `1` = keep all tracks that pass filters, `0` = single-track scoring (default, unchanged for all other profiles).
  - `AUDIO_KEEP_COMMENTARY` — `1` = keep commentary/descriptive tracks, `0` = drop them. Uses the existing `_audio_is_commentary()` heuristic.
- **Multi-track subtitle pipeline** (`SUB_MULTI_TRACK=1`) — New subtitle mode that keeps all matching subtitle tracks instead of selecting one per type (forced/full/SDH). Subtitle streams are mapped directly from source with `-c:s copy` (no OCR, no format conversion, no intermediate files). Controlled by one new config variable:
  - `SUB_MULTI_TRACK` — `1` = keep all tracks that pass filters, `0` = single-track per-type selection (default, unchanged for all other profiles).
  - Uses existing `SUB_INCLUDE_FORCED`, `SUB_INCLUDE_FULL`, `SUB_INCLUDE_SDH` as type filters and `SUB_LANG_PREF` as language filter. `SUB_MAX_TRACKS` is respected as a cap.
  - Bitmap subtitles (PGS, VobSub) that cannot be muxed into the target container are silently skipped. MKV handles all formats.
- **`dv-archival` profile updated** — Now sets `AUDIO_MULTI_TRACK=1`, `AUDIO_KEEP_COMMENTARY=0`, and `SUB_MULTI_TRACK=1`. Language filtering uses the existing `AUDIO_LANG_PREF` and `SUB_LANG_PREF` variables: when empty (the dv-archival default), all languages pass; when set (e.g., `eng,jpn`), only matching tracks are kept.
- **Graceful demotion** — If `--audio-track` or `--audio-force-codec` is set alongside `AUDIO_MULTI_TRACK=1`, multi-track audio mode is automatically demoted to single-track with an informational note. If `--sub-burn-forced` is set alongside `SUB_MULTI_TRACK=1`, multi-track subtitle mode is demoted to single-track. The explicit CLI flag always wins.
- **Conflict warnings** (Section 13) for `dv-archival` + `--audio-track`, `--audio-force-codec`, `--stereo-fallback`, `--sub-burn-forced`, and `--sub-export-external` when multi-track modes are active.
- **`skip-if-ideal` updated** — When `AUDIO_MULTI_TRACK=1` or `SUB_MULTI_TRACK=1`, the ideal check verifies that every source audio/subtitle track would survive the respective filter. If any would be dropped, the source is not ideal and remuxing proceeds.
- **Per-stream gating in skip-if-ideal remux** — `check_skip_if_ideal` now produces validated stream keep-lists (`SII_AUDIO_INDICES`, `SII_SUB_INDICES`) that the metadata remux uses to build explicit `-map 0:v:0 -map 0:a:N -map 0:s:N` flags instead of `-map 0`. Multi-track profiles delegate to `_build_audio_keep_list` / `_build_subtitle_keep_list`. Single-track profiles filter every stream against container compatibility, preventing incompatible codecs (e.g., TrueHD or PGS in MP4) from reaching the mux — even if a future profile change removes the implicit container gate.
- **`_sii_audio_is_container_safe()` helper** — Checks whether an audio codec can be muxed into the target container. MKV passes all codecs; MP4/MOV rejects TrueHD, DTS/DCA, and raw PCM. Mirrors the existing `_is_text_sub_codec` pattern for subtitles.
- **`dv-archival` profile now enables `CHECKSUM=1` by default** — SHA-256 integrity verification is a natural part of the archival workflow and was a missing default. Can be suppressed with `--no-checksum`.
- **Shared source input in `mux_final`** — `VIDEO_COPY_FROM_SOURCE`, `AUDIO_COPY_FROM_SOURCE`, `SUB_COPY_FROM_SOURCE`, and direct subtitle mapping now share a single `-i "$SRC_ABS"` ffmpeg input via `_src_input_idx`, eliminating duplicate source file inputs.
- New man page subsections "Multi-Track Audio (Archival)" and "Multi-Track Subtitles (Archival)" under AUDIO OPTIONS and SUBTITLE OPTIONS, documenting filter behavior, config variables, and demotion rules.
- `AUDIO_MULTI_TRACK`, `AUDIO_KEEP_COMMENTARY`, and `SUB_MULTI_TRACK` added to `--print-effective-config`, `--create-config` template, and man page CONFIGURATION variable groups.

### Fixed

- **Skip-if-ideal metadata remux silently dropped streams.** The ffmpeg copy-remux used to stamp audio titles and profile comments had no `-map` flag, causing ffmpeg's default stream selection to keep only one stream per type. On a 39-stream source (video + TrueHD + AC-3 + PGS + 35 SRT tracks), `dv-archival` output retained only 3 streams — the AC-3 compatibility track, PGS SDH subtitle, and all non-first-selected SRT tracks were silently lost. The remux now uses explicit per-stream maps built from the validated keep-lists populated by `check_skip_if_ideal`.
- **Audio title metadata misaligned when streams are filtered.** The skip-if-ideal remux referenced source audio indices for `-metadata:s:a:N` tags, but when streams are filtered out, output indices shift. Tags now use a sequential output counter, matching the proven pattern in `mux_final`.
- **No visual feedback during skip-if-ideal remux.** The ffmpeg copy-remux, `cp` fallback, and SHA-256 checksum all ran in the foreground with no spinner, causing the CLI to appear hung for 10–30+ seconds on multi-GB files. All three now run in the background with `spinner` progress indicators.
- **FD 3 closed before checksum in `on_exit`.** The raw-terminal file descriptor used by `spinner` was closed at the top of `on_exit`, before `write_checksum` could use it. The checksum spinner would write to a closed FD. FD 3 close is now deferred to after the checksum in both the success and failure paths.

### Changed

- `dv-archival` profile description updated in man page, usage text, and `--help` output to reflect multi-track audio and subtitle behavior.

## [1.0.2] - 2026-03-20

Enforce HEVC Level 5.1 VBV guardrails in `atv-directplay-hq` re-encodes to prevent bitrate spikes that cause stutter on Apple TV 4K. Fix crash when subtitle or audio stream titles contain literal pipe characters. Add ASS/SSA subtitle format preservation for MKV containers. Eliminate redundant multi-GB file copies in the video pipeline. Fix fatal ffmpeg muxer failure when stream-copying TrueHD or ALAC audio via lossless passthrough. Fix misleading "No Dolby Vision detected" log message when DV detection is skipped by a profile.

### Added

- **`--sub-preserve-format` / `--no-sub-preserve-format`** — New CLI flag pair controlling whether text-based subtitles (ASS/SSA) are kept in their native format or converted to plain-text SRT. When enabled and the output container is MKV, ASS/SSA subtitles are stream-copied with full positioning, fonts, and typesetting intact. Ignored for MP4/MOV containers (which cannot carry ASS). Controllable via the `SUB_PRESERVE_TEXT_FORMAT` config variable in `.muxmrc`.
- **`animation` profile now preserves ASS/SSA subtitles by default.** The profile sets `SUB_PRESERVE_TEXT_FORMAT=1`, fulfilling its documented promise of preserving styled ASS/SSA subtitles in MKV output. Previously, ASS subtitles were unconditionally converted to SRT regardless of profile or container, losing all positioning, styling, and typesetting data.
- New conflict warning when `animation` profile is combined with `--no-sub-preserve-format`, alerting that ASS/SSA styling will be lost.
- `SUB_PRESERVE_TEXT_FORMAT` added to `--print-effective-config`, `--create-config` template, man page, and tab completions.
- New `ass_subs.mkv` test fixture and 10 new test assertions across `test_profiles`, `test_conflicts`, `test_dryrun`, `test_subs`, and `test_profile_e2e` suites validating ASS preservation, SRT conversion fallback, CLI override, and MP4 container limitation.
- `probe_sub` helper added to `test_muxm.sh` for subtitle stream field inspection.
- **`_audio_copy_ext()` helper** — Maps ffprobe codec names to file extensions that ffmpeg can actually mux when stream-copying intermediate audio. Covers `truehd→.thd`, `alac→.m4a`, `pcm_s*→.wav`, `dca→.dts`; all other codecs pass through unchanged.
- `SYNC` cross-reference comments on `audio_is_direct_play_copyable()`, `audio_is_lossless()`, and `_audio_copy_ext()` documenting that these three codec lists must stay in sync — any codec added to either copy-eligible gate must have a valid mapping in `_audio_copy_ext()`.
- 11 new unit test assertions for `_audio_copy_ext` covering all 5 mapped codecs and 6 passthrough codecs.
- **`--dv` CLI flag** — Re-enables Dolby Vision handling after a profile disables it. Follows the existing `--flag` / `--no-flag` convention alongside `--no-dv`. Allows users to combine animation-tuned x265 parameters with DV preservation on live-action sources (e.g., `muxm --profile animation --dv Movie.mkv`). Added to man page, tab completions, and usage text.
- **`_source_has_dv_metadata()` helper** — Lightweight check for DOVI configuration records in the already-populated metadata cache. Used to emit actionable warnings when DV detection is skipped on a source that actually contains Dolby Vision.

### Fixed

- **`atv-directplay-hq` re-encodes now capped by Level 5.1 VBV.** Previously, the copy path was guarded by `MAX_COPY_BITRATE=50000k` but the re-encode path had no bitrate ceiling — a CRF 17 encode of complex scenes could spike beyond what the Apple TV 4K hardware decoder sustains without buffering. The profile now sets `LEVEL_VALUE="5.1"`, which activates the existing conservative VBV machinery (`vbv-maxrate=40000k`, `vbv-bufsize=80000k`). Can be overridden with `--level` or `--no-conservative-vbv`.
- **Pipe characters in stream titles no longer break field parsing.** Subtitle titles such as `"Original | English"` or `"Original | English | (SDH)"` contain literal `|` which corrupted the pipe-delimited output of `_sub_stream_info` and the verify-block audio jq call. The `forced` variable would receive fragments like `" English|0"` instead of `0`, causing an arithmetic evaluation crash under `nounset`. Switched all internal field delimiters from `|` to `\t` (tab) across 4 jq producer functions, 10 consumer `read`/`cut`/parameter-expansion sites, and their fallback defaults. Tab is safe because it effectively never appears in media metadata. The audio pipeline (`_audio_stream_info`, `_score_audio_stream`, and their consumers) was not actively broken — the free-text `title` field happened to be last, absorbing extra pipes — but was migrated for consistency to prevent silent breakage if fields are ever reordered.
- **ASS/SSA subtitles no longer silently converted to SRT.** The subtitle pipeline unconditionally funneled all text-based subtitles through SRT conversion via `_prepare_sub_to_srt`, destroying ASS positioning, fonts, and typesetting — even when the output container (MKV) natively supports ASS. The `--no-ocr` flag only gated PGS bitmap OCR, not text-format conversion. The function has been renamed to `_prepare_subtitle` and now checks `SUB_PRESERVE_TEXT_FORMAT` and the output container format before deciding whether to convert or stream-copy. The final mux stage (`mux_final`) has been updated from a blanket `-c:s srt` to per-stream codec assignment, so ASS and SRT tracks can coexist in the same output.
- **Lossless audio passthrough no longer fails for TrueHD and ALAC codecs.** The audio pipeline's copy path wrote the intermediate file as `audio_primary.${codec}` using the raw ffprobe codec name as the extension. ffmpeg has no muxer registered for `.truehd` or `.alac`, causing a fatal "Unable to choose an output format" error before any data was written. This broke `--profile animation` (which enables `AUDIO_LOSSLESS_PASSTHROUGH=1`) for any source with a TrueHD Atmos track, and `--audio-lossless-passthrough` or `--profile dv-archival` for sources with ALAC audio. The same class of bug also affected `pcm_s16le`/`pcm_s24le`/`pcm_s32le` (no `.pcm_*` muxer) and `dca` (ffprobe name vs ffmpeg's `.dts` muxer). A new `_audio_copy_ext()` helper now maps each codec to a valid ffmpeg muxer extension. The transcode path was not affected (it already reassigns the extension from the target codec).
- **Misleading "No Dolby Vision detected" message when DV is disabled by a profile.** Profiles that set `DISABLE_DV=1` (e.g., `animation`, `streaming`, `universal`) caused `detect_dv()` to bail out before probing, then the caller logged "No Dolby Vision detected" — identical to the message shown when a source genuinely lacks DV. For sources that do contain Dolby Vision (e.g., a Netflix 4K HDR rip with DV Profile 7), this was confusing and gave no indication that DV was being intentionally skipped. `detect_dv()` now returns a distinct exit code (2) when detection is skipped due to `DISABLE_DV`. The caller uses the new `_source_has_dv_metadata()` helper to check whether the source actually has DV, and emits one of two messages: a warning with `--dv` override guidance when DV is present but disabled, or a neutral note when the source has no DV and detection was simply unnecessary.

### Changed

- `--create-config ... atv-directplay-hq` now emits `LEVEL_VALUE` and `CONSERVATIVE_VBV` as uncommented (active) variables, matching the profile's new defaults.
- **Video pipeline no longer copies multi-GB intermediates on non-DV and DV-fallback paths.** Six `cp -f` operations that duplicated the encoded video from `V_BASE` to `V_MIXED` (or `V_INJECTED` to `V_MIXED`) have been replaced with variable reassignment. Downstream consumers (`mux_final`, DV container verification, DV pre-wrap) only read `V_MIXED` and never write to it, so an alias is functionally identical to a file copy. For a typical 2-hour 4K HEVC encode at CRF 17–18, this eliminates 8–25 GB of redundant disk I/O, saves 10–30 seconds of wall-clock time, and halves peak intermediate disk usage. The only user-visible change is that `--keep-temp-always` workdirs will no longer contain a separate `video_mixed` file on non-DV runs.

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