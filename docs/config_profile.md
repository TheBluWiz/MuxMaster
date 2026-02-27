# muxm Format Profiles

Below are the six format profiles for `muxm`, listed **from highest fidelity to widest compatibility**.  
Each profile includes **who/where it's for**, **its goal**, and **default behaviors**.

---

## 1) `dv-archival` — High Quality Dolby Vision Archival
**Who/Where:**  
For collectors or Plex users with a **Dolby Vision-capable ecosystem** (e.g., Apple TV 4K + DV TV, Shield, LG WebOS w/ Plex) who want to **preserve original quality**.  
Great for long-term storage where fidelity > compatibility.

**Goal:**  
Preserve DV + HDR10 metadata and lossless audio whenever possible. Only perform **lossless remuxes** or metadata fixes. Skip processing if the file is already ideal.

**Defaults:**
- **DV policy:** `preserve` (no re-encode unless `--dv-policy reencode` specified)
- **Container:** `mkv`
- **Video:** `-c:v copy` unless DV re-encode explicitly requested `VIDEO_COPY_IF_COMPLIANT=1`
- **Audio:** keep lossless; `--stereo-fallback=off` (toggleable) `AUDIO_LOSSLESS_PASSTHROUGH=1`, `ADD_STEREO_IF_MULTICH=0`
- **Subs:** keep all; detect/mark forced; fix language tags; no burn
- **Chapters/metadata:** keep and normalize `KEEP_CHAPTERS=1`, `STRIP_METADATA=0`
- **Skip heuristic:** `--skip-if-ideal` (enabled) — no changes if file already matches target profile `SKIP_IF_IDEAL=1`
- **Reporting:** generate JSON + human-readable report of checks/fixes `REPORT_JSON=1`

**CLI:** `muxm --profile dv-archival input.mkv`

---

## 2) `hdr10-hq` — High Quality HDR10 (No Dolby Vision)
**Who/Where:**  
For HDR10 TVs and mixed-device environments where DV causes quirks (e.g., older streaming devices, non-DV TVs, varied Plex clients).

**Goal:**  
Maximize HDR10 quality while avoiding DV playback issues. Keep HDR10 metadata intact, remove DV layers, preserve lossless audio, and add stereo fallback.

**Defaults:**
- **DV policy:** `strip` `DISABLE_DV=1`
- **Container:** `mkv`
- **Video:** HEVC re-encode if needed:  
  `-c:v libx265 -preset slower -crf 17` with HDR10 x265 params
- **Pixel format:** `yuv420p10le` `HDR_TARGET_PIXFMT=yuv420p10le`, `FORCE_CHROMA_420=1`
- **Audio:** keep lossless **and** add AAC stereo fallback (256k) `AUDIO_LOSSLESS_PASSTHROUGH=1`, `ADD_STEREO_IF_MULTICH=1`, `STEREO_BITRATE=256k`
- **Subs:** keep all; default by language; no burn
- **Chapters/metadata:** preserve

**CLI:** `muxm --profile hdr10-hq input.mkv`

---

## 3) `atv-directplay-hq` — Apple TV Direct Play (Plex) Optimized
**Who/Where:**  
Plex → **Apple TV 4K** setups, aiming for *true Direct Play* without remux/transcode.

**Goal:**  
Conform to tvOS/Plex playback constraints while keeping high quality: MP4 container, HEVC Main10 (HDR10 and optional DV P8.1), E-AC-3 audio (with Atmos JOC when present), and text-based subtitles.

**Defaults:**
- **DV policy:** `auto`  
  - Preserve DV **Profile 8.1** if present & compliant; otherwise fall back to clean **HDR10**. (Don't output P7.)
  - `DISABLE_DV=0`, `ALLOW_DV_FALLBACK=1`, `DV_CONVERT_TO_P81_IF_FAIL=1`
- **Container:** `mp4` (maximize Apple TV Direct Play)
- **Video:**  
  - Prefer copy if already compliant (`VIDEO_COPY_IF_COMPLIANT=1`); else:
    ```
    -c:v libx265 -preset slower -crf 17 -pix_fmt yuv420p10le
    ```
  - If DV kept: add `:dv-profile=8.1:dv-bl-compatible-id=1`.
- **Audio:**  
  - Transcode to E-AC-3 5.1 @ 640k (or 7.1 @ 768k): `EAC3_BITRATE_5_1=640k`, `EAC3_BITRATE_7_1=768k`  
  - AAC 2.0 @ 256k fallback: `ADD_STEREO_IF_MULTICH=1`, `STEREO_BITRATE=256k`  
  - No lossless passthrough (Apple TV can't Direct Play TrueHD): `AUDIO_LOSSLESS_PASSTHROUGH=0`
- **Subs:**  
  - **Forced:** burn into video (`SUB_BURN_FORCED=1`)  
  - **Others:** embed as `mov_text` for MP4
- **Chapters/metadata:** keep chapters; normalize language tags
- **Skip heuristic:** on `SKIP_IF_IDEAL=1`

**CLI:** `muxm --profile atv-directplay-hq input.mkv`

---

## 4) `streaming` — Modern HEVC Streaming
**Who/Where:**  
For Plex, Jellyfin, and Emby users targeting modern clients: Shield, Fire TV, Roku Ultra, smart TVs, and web browsers. Balances quality with file size.

**Goal:**  
Smaller files with broad modern-device support. HEVC CRF 20 with streaming-friendly audio bitrates. Strip DV, keep HDR10.

**Defaults:**
- **DV policy:** `strip` `DISABLE_DV=1`
- **Container:** `mp4`
- **Video:** HEVC re-encode:  
  `-c:v libx265 -preset medium -crf 20` with HDR10 x265 params
- **Pixel format:** `yuv420p10le` `HDR_TARGET_PIXFMT=yuv420p10le`, `FORCE_CHROMA_420=1`
- **Audio:** E-AC-3 surround at streaming bitrates + AAC stereo fallback  
  `EAC3_BITRATE_5_1=448k`, `EAC3_BITRATE_7_1=640k`, `ADD_STEREO_IF_MULTICH=1`, `STEREO_BITRATE=192k`, `AUDIO_LOSSLESS_PASSTHROUGH=0`
- **Subs:** soft forced, full embedded, no SDH  
  `SUB_INCLUDE_FORCED=1`, `SUB_INCLUDE_FULL=1`, `SUB_INCLUDE_SDH=0`, `SUB_BURN_FORCED=0`
- **Chapters/metadata:** keep `KEEP_CHAPTERS=1`, `STRIP_METADATA=0`

**CLI:** `muxm --profile streaming input.mkv`

---

## 5) `animation` — Anime & Cartoon Optimized
**Who/Where:**  
For anime and cartoon content where banding-free gradients, clean hard edges, and styled subtitle preservation matter. Ideal for archival-quality animation encodes.

**Goal:**  
Artifact-free animation encoding. 10-bit even for SDR to eliminate banding, animation-tuned x265 params (low psy-rd, adjusted deblock, extra b-frames), lossless audio, and MKV to preserve styled ASS/SSA subtitles.

**Defaults:**
- **DV policy:** `strip` `DISABLE_DV=1`
- **Container:** `mkv` (ASS/SSA subtitle support, lossless audio)
- **Video:** HEVC, quality-first, animation-tuned:  
  `-c:v libx265 -preset slower -crf 16` with `psy-rd=1.0:psy-rdoq=0.5:deblock=-1,-1:bframes=8`
- **Pixel format:** `yuv420p10le` (10-bit even for SDR) `SDR_USE_10BIT_IF_SRC_10BIT=1`
- **Audio:** lossless passthrough + AAC stereo fallback  
  `AUDIO_LOSSLESS_PASSTHROUGH=1`, `ADD_STEREO_IF_MULTICH=1`, `STEREO_BITRATE=192k`
- **Subs:** keep all (up to 6 tracks), never burn (preserve ASS styling)  
  `SUB_INCLUDE_FORCED=1`, `SUB_INCLUDE_FULL=1`, `SUB_INCLUDE_SDH=1`, `SUB_MAX_TRACKS=6`, `SUB_BURN_FORCED=0`
- **Chapters/metadata:** keep (OP/ED chapter markers) `KEEP_CHAPTERS=1`, `STRIP_METADATA=0`

**CLI:** `muxm --profile animation input.mkv`

---

## 6) `universal` — Universal Compatibility
**Who/Where:**  
For playback **anywhere**: old Rokus, mobile devices, web browsers, non-HDR TVs. Ideal for sharing with friends/family without worrying about playback capability.

**Goal:**  
Prioritize compatibility over fidelity. Tone-map HDR to SDR H.264, ensure AAC stereo audio, burn forced subs, and strip anything that could block playback.

**Defaults:**
- **DV policy:** `strip` `DISABLE_DV=1`
- **Container:** `mp4`
- **Video:** SDR H.264, tone-mapped from HDR if present:  
  `VIDEO_CODEC=libx264`, `TONEMAP_HDR_TO_SDR=1`, `CRF_VALUE=22`, `PRESET_VALUE=slow`
- **Audio:** AAC stereo  
  `AUDIO_FORCE_CODEC=aac`, `MAX_AUDIO_CHANNELS=2`, `STEREO_BITRATE=256k`, `ADD_STEREO_IF_MULTICH=0`
- **Subs:** burn forced; export all others as external `.srt`  
  `SUB_BURN_FORCED=1`, `SUB_EXPORT_EXTERNAL=1`, `SUB_INCLUDE_SDH=0`
- **Chapters/metadata:** strip chapters; minimal metadata  
  `KEEP_CHAPTERS=0`, `STRIP_METADATA=1`

**CLI:** `muxm --profile universal input.mkv`

---

## Configuration Flexibility

These profiles are **opinionated starting points** — every option is adjustable.

`muxm` reads configuration from multiple levels, applied in the following order  
(**lowest precedence** → **highest precedence**):

1. **Hardcoded defaults** — built into the script
2. **Global config** — system-wide `/etc/.muxmrc`
3. **User config** — `~/.muxmrc` (personal defaults across all projects)
4. **Project config** — `.muxmrc` in the current working directory
5. **Profile** — `--profile <n>` (or `PROFILE_NAME` set in a config file)
6. **CLI flags** — command-line flags (override everything above for a single run)

### Setting a Default Profile in Config

```bash
# In ~/.muxmrc
PROFILE_NAME="atv-directplay-hq"
```

CLI `--profile` always overrides a config-file `PROFILE_NAME`.

### Example Precedence

- User config sets `PROFILE_NAME="hdr10-hq"` (CRF 17, lossless audio, MKV)
- CLI run: `muxm --profile hdr10-hq --crf 20 --output-ext mp4 input.mkv`

→ Result: `hdr10-hq` profile with `CRF_VALUE=20` and `OUTPUT_EXT=mp4` (CLI overrides).

### Verifying Effective Configuration

```bash
muxm --profile atv-directplay-hq --crf 20 --print-effective-config
```

Shows every variable grouped by section, which profile is active, and its source (`cli` or `config-file`).

### Conflict Warnings

`muxm` detects contradictory flag + profile combinations and warns:

```bash
muxm --profile dv-archival --no-dv --print-effective-config
# ⚠️  Profile 'dv-archival' + --no-dv: DV archival without Dolby Vision is pointless.
```

Warnings never block execution — the user's CLI flags always win.

---

## New Variables Introduced by Profiles

These variables were added to support profile functionality. They have safe defaults that preserve pre-profile behavior when no profile is selected.

| Variable | Default | Description |
|---|---|---|
| `PROFILE_NAME` | `""` | Active profile name (set by `--profile` or `.muxmrc`) |
| `VIDEO_CODEC` | `libx265` | Video encoder: `libx265` or `libx264` |
| `VIDEO_COPY_IF_COMPLIANT` | `0` | Skip re-encode if source already matches target |
| `TONEMAP_HDR_TO_SDR` | `0` | Tone-map HDR/HLG to SDR via zscale+hable |
| `TONEMAP_FILTER` | *(zscale chain)* | FFmpeg filter string for tone-mapping |
| `AUDIO_FORCE_CODEC` | `""` | Force all audio to a specific codec (e.g., `aac`) |
| `AUDIO_LOSSLESS_PASSTHROUGH` | `0` | Allow TrueHD/DTS-HD MA/FLAC to copy through |
| `SUB_BURN_FORCED` | `0` | Burn forced subtitles into the video stream |
| `SUB_EXPORT_EXTERNAL` | `0` | Export subtitles as external `.srt` files |
| `KEEP_CHAPTERS` | `1` | Keep chapter markers in output |
| `STRIP_METADATA` | `0` | Strip non-essential metadata |
| `SKIP_IF_IDEAL` | `0` | Skip processing if source already matches profile |
| `REPORT_JSON` | `0` | Generate JSON report alongside output |

---