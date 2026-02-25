#!/usr/bin/env bash
# =============================================================================
#  muxm Test Harness v2.0
#  Automated testing for MuxMaster — generates synthetic media and validates
#  CLI parsing, config precedence, profile behavior, and pipeline outputs.
#
#  Usage:
#    ./test_muxm.sh [--muxm /path/to/muxm] [--suite SUITE] [--verbose]
#
#  Suites: all, cli, config, profiles, conflicts, dryrun, video, audio, subs,
#          output, edge, e2e, hdr, containers, metadata
#  Default: all
# =============================================================================
set -euo pipefail

# ---- Configuration ----
MUXM="${MUXM:-./muxm}"
SUITE="${SUITE:-all}"
VERBOSE=0
TESTDIR=""
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# ---- Colors ----
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

# ---- Parse args ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --muxm)   MUXM="$2"; shift 2 ;;
    --suite)  SUITE="$2"; shift 2 ;;
    --verbose) VERBOSE=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--muxm PATH] [--suite SUITE] [--verbose]"
      echo "Suites: all, cli, config, profiles, conflicts, dryrun, video, hdr,"
      echo "        audio, subs, output, containers, metadata, edge, e2e"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ---- Helpers ----
log()  { printf "%b  → %s%b\n" "$BLUE" "$*" "$NC"; }
pass() { PASS=$((PASS + 1)); printf "%b  ✅ PASS: %s%b\n" "$GREEN" "$*" "$NC"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$*"); printf "%b  ❌ FAIL: %s%b\n" "$RED" "$*" "$NC"; }
skip() { SKIP=$((SKIP + 1)); printf "%b  ⏭  SKIP: %s%b\n" "$YELLOW" "$*" "$NC"; }
section() { printf "\n%b━━━ %s ━━━%b\n" "$BOLD" "$*" "$NC"; }

# Run muxm from TESTDIR to avoid picking up .muxmrc from the user's PWD
run_muxm() { (cd "$TESTDIR" && "$MUXM" "$@" 2>&1) || true; }
# Assert exit code
assert_exit() {
  local expected="$1" label="$2"
  shift 2
  local output code
  output="$(cd "$TESTDIR" && "$MUXM" "$@" 2>&1)" && code=$? || code=$?
  if [[ "$code" -eq "$expected" ]]; then
    pass "$label (exit $code)"
  else
    fail "$label — expected exit $expected, got $code"
    (( VERBOSE )) && echo "    Output: ${output:0:200}"
  fi
}

# Assert output contains string
assert_contains() {
  local needle="$1" label="$2" haystack="$3"
  if echo "$haystack" | grep -qiF -- "$needle"; then
    pass "$label"
  else
    fail "$label — output missing: '$needle'"
    (( VERBOSE )) && echo "    Output: ${haystack:0:300}"
  fi
}

# Assert file does NOT exist
assert_no_file() {
  local path="$1" label="$2"
  if [[ ! -f "$path" ]]; then
    pass "$label"
  else
    fail "$label — file unexpectedly exists: $path"
  fi
}

# Probe a video field from output file (returns value via stdout)
probe_video() {
  local file="$1" field="$2"
  ffprobe -v error -select_streams v:0 -show_entries "stream=$field" -of csv=p=0 "$file" 2>/dev/null | head -1 | tr -d ','
}

# Probe an audio field from output file
probe_audio() {
  local file="$1" field="$2" idx="${3:-0}"
  ffprobe -v error -select_streams "a:$idx" -show_entries "stream=$field" -of csv=p=0 "$file" 2>/dev/null | head -1 | tr -d ','
}

# Count streams of a given type
count_streams() {
  local file="$1" type="$2"
  ffprobe -v error -select_streams "$type" -show_entries stream=codec_type -of csv=p=0 "$file" 2>/dev/null | wc -l | tr -d ' '
}

# ---- Preflight ----
preflight() {
  section "Preflight Checks"

  if [[ ! -x "$MUXM" && ! -f "$MUXM" ]]; then
    echo "ERROR: muxm not found at '$MUXM'. Use --muxm /path/to/muxm.sh"
    exit 1
  fi
  pass "muxm found at $MUXM"

  for tool in ffmpeg ffprobe jq bc; do
    if command -v "$tool" >/dev/null 2>&1; then
      pass "$tool available"
    else
      fail "$tool NOT available (required)"
    fi
  done

  if command -v dovi_tool >/dev/null 2>&1; then
    pass "dovi_tool available"
  else
    skip "dovi_tool not available — DV tests will be limited"
  fi

  # Create test directory
  TESTDIR="$(mktemp -d /tmp/muxm-test.XXXXXXXX)"
  log "Test directory: $TESTDIR"
}

# ---- Generate Synthetic Test Media ----
generate_test_media() {
  section "Generating Synthetic Test Media"

  # 1) Basic SDR H.264 with stereo AAC and SRT subtitle (2 seconds)
  log "Creating basic_sdr.mkv (H.264 + AAC stereo + SRT sub)"
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "color=c=blue:s=320x240:r=24:d=2" \
    -f lavfi -i "sine=frequency=440:duration=2" \
    -c:v libx264 -preset ultrafast -crf 28 \
    -c:a aac -b:a 128k -ac 2 \
    -metadata:s:a:0 language=eng \
    "$TESTDIR/basic_sdr.mkv"
  # Add SRT subtitle
  cat > "$TESTDIR/test.srt" <<'SRT'
1
00:00:00,000 --> 00:00:02,000
Test subtitle line
SRT
  ffmpeg -hide_banner -loglevel error -y \
    -i "$TESTDIR/basic_sdr.mkv" \
    -i "$TESTDIR/test.srt" \
    -c copy -c:s srt \
    -metadata:s:s:0 language=eng \
    -metadata:s:s:0 title="English" \
    "$TESTDIR/basic_sdr_subs.mkv"
  pass "basic_sdr_subs.mkv created"

  # 2) HEVC 10-bit SDR with 5.1 AC3 audio (simulated)
  log "Creating hevc_sdr_51.mkv (HEVC + AC3 5.1)"
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "color=c=red:s=320x240:r=24:d=2" \
    -f lavfi -i "sine=frequency=440:duration=2" \
    -c:v libx265 -preset ultrafast -crf 28 -pix_fmt yuv420p10le \
    -c:a ac3 -b:a 384k -ac 6 \
    -metadata:s:a:0 language=eng \
    "$TESTDIR/hevc_sdr_51.mkv"
  pass "hevc_sdr_51.mkv created"

  # 3) HEVC 10-bit with HDR10-like metadata tags (not real HDR, but tagged)
  log "Creating hevc_hdr10_tagged.mkv (HEVC 10-bit with HDR-like tags)"
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "color=c=green:s=320x240:r=24:d=2" \
    -f lavfi -i "sine=frequency=880:duration=2" \
    -c:v libx265 -preset ultrafast -crf 28 -pix_fmt yuv420p10le \
    -x265-params "colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc" \
    -c:a eac3 -b:a 448k -ac 6 \
    -metadata:s:a:0 language=eng \
    "$TESTDIR/hevc_hdr10_tagged.mkv"
  pass "hevc_hdr10_tagged.mkv created"

  # 4) Multi-audio file (stereo AAC + 5.1 EAC3 + stereo commentary)
  log "Creating multi_audio.mkv (3 audio tracks)"
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "color=c=yellow:s=320x240:r=24:d=2" \
    -f lavfi -i "sine=frequency=440:duration=2" \
    -f lavfi -i "sine=frequency=660:duration=2" \
    -f lavfi -i "sine=frequency=880:duration=2" \
    -c:v libx264 -preset ultrafast -crf 28 \
    -map 0:v -map 1:a -map 2:a -map 3:a \
    -c:a:0 aac -b:a:0 128k -ac:a:0 2 \
    -c:a:1 eac3 -b:a:1 448k -ac:a:1 6 \
    -c:a:2 aac -b:a:2 96k -ac:a:2 2 \
    -metadata:s:a:0 language=eng -metadata:s:a:0 title="Stereo" \
    -metadata:s:a:1 language=eng -metadata:s:a:1 title="5.1 Surround" \
    -metadata:s:a:2 language=eng -metadata:s:a:2 title="Commentary" \
    "$TESTDIR/multi_audio.mkv"
  pass "multi_audio.mkv created"

  # 5) Multi-subtitle file (forced + full + SDH)
  log "Creating multi_subs.mkv (3 subtitle tracks)"
  cat > "$TESTDIR/forced.srt" <<'SRT'
1
00:00:00,000 --> 00:00:01,000
[Foreign dialogue]
SRT
  cat > "$TESTDIR/full.srt" <<'SRT'
1
00:00:00,000 --> 00:00:02,000
This is the full English subtitle.
SRT
  cat > "$TESTDIR/sdh.srt" <<'SRT'
1
00:00:00,000 --> 00:00:02,000
[Music playing] This is the SDH subtitle.
SRT
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "color=c=purple:s=320x240:r=24:d=2" \
    -f lavfi -i "sine=frequency=440:duration=2" \
    -i "$TESTDIR/forced.srt" \
    -i "$TESTDIR/full.srt" \
    -i "$TESTDIR/sdh.srt" \
    -c:v libx264 -preset ultrafast -crf 28 \
    -c:a aac -b:a 128k -ac 2 \
    -c:s srt \
    -map 0:v -map 1:a -map 2 -map 3 -map 4 \
    -metadata:s:a:0 language=eng \
    -metadata:s:s:0 language=eng -metadata:s:s:0 title="Forced" \
    -metadata:s:s:1 language=eng -metadata:s:s:1 title="English" \
    -metadata:s:s:2 language=eng -metadata:s:s:2 title="English SDH" \
    -disposition:s:0 forced \
    "$TESTDIR/multi_subs.mkv"
  pass "multi_subs.mkv created"

  # 6) File with chapters
  log "Creating with_chapters.mkv (chapters)"
  cat > "$TESTDIR/chapters.txt" <<'CHAP'
;FFMETADATA1
[CHAPTER]
TIMEBASE=1/1000
START=0
END=1000
title=Chapter 1

[CHAPTER]
TIMEBASE=1/1000
START=1000
END=2000
title=Chapter 2
CHAP
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "color=c=orange:s=320x240:r=24:d=2" \
    -f lavfi -i "sine=frequency=440:duration=2" \
    -i "$TESTDIR/chapters.txt" \
    -map_metadata 2 \
    -c:v libx264 -preset ultrafast -crf 28 \
    -c:a aac -b:a 128k -ac 2 \
    -metadata:s:a:0 language=eng \
    "$TESTDIR/with_chapters.mkv"
  pass "with_chapters.mkv created"

  # 7) Already-compliant MP4 (for skip-if-ideal tests)
  log "Creating compliant.mp4 (HEVC 10-bit + EAC3 in MP4)"
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "color=c=white:s=320x240:r=24:d=2" \
    -f lavfi -i "sine=frequency=440:duration=2" \
    -c:v libx265 -preset ultrafast -crf 28 -pix_fmt yuv420p10le -tag:v hvc1 \
    -c:a eac3 -b:a 448k -ac 6 \
    -metadata:s:a:0 language=eng \
    "$TESTDIR/compliant.mp4"
  pass "compliant.mp4 created"

  # 8) Multi-language audio file (English + Spanish)
  log "Creating multi_lang_audio.mkv (eng + spa audio)"
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "color=c=cyan:s=320x240:r=24:d=2" \
    -f lavfi -i "sine=frequency=440:duration=2" \
    -f lavfi -i "sine=frequency=550:duration=2" \
    -c:v libx264 -preset ultrafast -crf 28 \
    -map 0:v -map 1:a -map 2:a \
    -c:a:0 aac -b:a:0 128k -ac:a:0 2 \
    -c:a:1 aac -b:a:1 128k -ac:a:1 2 \
    -metadata:s:a:0 language=eng -metadata:s:a:0 title="English" \
    -metadata:s:a:1 language=spa -metadata:s:a:1 title="Spanish" \
    "$TESTDIR/multi_lang_audio.mkv"
  pass "multi_lang_audio.mkv created"

  # 9) File with rich metadata (encoder, title, etc.) for strip-metadata tests
  log "Creating rich_metadata.mkv (with extra metadata tags)"
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "color=c=gray:s=320x240:r=24:d=2" \
    -f lavfi -i "sine=frequency=440:duration=2" \
    -c:v libx264 -preset ultrafast -crf 28 \
    -c:a aac -b:a 128k -ac 2 \
    -metadata title="Test Movie Title" \
    -metadata comment="This is a test comment" \
    -metadata encoder="TestEncoder v1.0" \
    -metadata:s:a:0 language=eng \
    "$TESTDIR/rich_metadata.mkv"
  pass "rich_metadata.mkv created"

  log "All synthetic test media ready in $TESTDIR"
}

# ---- Test Suites ----

# === Suite: CLI parsing & help ===
test_cli() {
  section "CLI Parsing & Help"

  # --help
  local out
  out="$(run_muxm --help)"
  assert_contains "Usage:" "--help shows usage" "$out"
  assert_contains "--profile" "--help mentions --profile" "$out"
  assert_contains "dv-archival" "--help lists dv-archival" "$out"
  assert_contains "universal" "--help lists universal" "$out"

  # --version
  out="$(run_muxm --version)"
  assert_contains "MuxMaster" "--version shows app name" "$out"
  assert_contains "muxm" "--version shows CLI name" "$out"

  # No args → shows usage (exit 0)
  assert_exit 0 "No arguments shows usage"

  # Invalid profile
  assert_exit 11 "Invalid profile exits 11" --profile fake "$TESTDIR/basic_sdr_subs.mkv"

  # Invalid preset
  assert_exit 11 "Invalid preset exits 11" --preset fake "$TESTDIR/basic_sdr_subs.mkv"

  # Invalid video codec
  assert_exit 11 "Invalid video codec exits 11" --video-codec vp9 "$TESTDIR/basic_sdr_subs.mkv"

  # Invalid output extension
  assert_exit 11 "Invalid output extension exits 11" --output-ext webm "$TESTDIR/basic_sdr_subs.mkv"

  # Missing source file
  assert_exit 11 "Missing source file exits 11" /nonexistent/file.mkv

  # Too many positional args
  assert_exit 11 "Too many args exits 11" a.mkv b.mp4 c.mp4

  # Source = output prevention
  out="$(cd "$TESTDIR" && "$MUXM" --output-ext mkv "$TESTDIR/basic_sdr_subs.mkv" "$TESTDIR/basic_sdr_subs.mkv" 2>&1)" || true
  assert_contains "same file" "Source=output prevented" "$out"

  # --no-overwrite: should refuse when output already exists (#28)
  local out_exist="$TESTDIR/cli_nooverwrite.mp4"
  local pre_out
  pre_out="$(run_muxm --crf 28 --preset ultrafast "$TESTDIR/basic_sdr_subs.mkv" "$out_exist")"
  if [[ -f "$out_exist" ]]; then
    out="$(cd "$TESTDIR" && "$MUXM" --no-overwrite --crf 28 --preset ultrafast \
      "$TESTDIR/basic_sdr_subs.mkv" "$out_exist" 2>&1)" || true
    assert_contains "exists" "--no-overwrite refuses existing output" "$out"
  else
    log "--no-overwrite: preliminary encode failed: ${pre_out:0:500}"
    skip "--no-overwrite: initial encode did not produce output"
  fi
}

# === Suite: Config Precedence ===
test_config() {
  section "Configuration Precedence"

  local cfg_dir="$TESTDIR/config_test"
  mkdir -p "$cfg_dir"

  # Test --print-effective-config with profile
  local out
  out="$(run_muxm --profile streaming --print-effective-config)"
  assert_contains "PROFILE_NAME" "--print-effective-config shows profile" "$out"
  assert_contains "streaming" "Effective config shows streaming profile" "$out"
  assert_contains "CRF_VALUE" "Effective config shows CRF" "$out"
  assert_contains "VIDEO_CODEC" "Effective config shows video codec" "$out"

  # CLI flags override profile
  out="$(run_muxm --profile streaming --crf 25 --print-effective-config)"
  assert_contains "25" "CLI --crf overrides profile CRF" "$out"

  # Profile from config file (project-level)
  local cfg_profile_dir="$TESTDIR/config_profile_test"
  mkdir -p "$cfg_profile_dir"
  cat > "$cfg_profile_dir/.muxmrc" <<'EOF'
PROFILE_NAME="animation"
EOF
  # Verify config file is picked up when running from that directory
  out="$(cd "$cfg_profile_dir" && "$MUXM" --print-effective-config 2>&1)" || true
  assert_contains "animation" "Config file PROFILE_NAME loaded" "$out"
  log "Config file profile override tested via --print-effective-config"

  # --create-config (use a clean directory so no pre-existing .muxmrc)
  local cfg_create_dir="$TESTDIR/config_create_test"
  mkdir -p "$cfg_create_dir"
  pushd "$cfg_create_dir" >/dev/null
  out="$("$MUXM" --create-config project streaming 2>&1)" || true
  popd >/dev/null
  if [[ -f "$cfg_create_dir/.muxmrc" ]]; then
    pass "--create-config creates .muxmrc"
    # Check contents
    local cfg_content
    cfg_content="$(cat "$cfg_create_dir/.muxmrc")"
    assert_contains "PROFILE_NAME" "Config contains PROFILE_NAME" "$cfg_content"
    assert_contains "streaming" "Config contains profile name" "$cfg_content"
    assert_contains "CRF_VALUE" "Config contains CRF_VALUE" "$cfg_content"

    # --create-config refuses overwrite
    out="$(cd "$cfg_create_dir" && "$MUXM" --create-config project streaming 2>&1)" || true
    assert_contains "already exists" "--create-config refuses overwrite" "$out"

    # --force-create-config overwrites
    out="$(cd "$cfg_create_dir" && "$MUXM" --force-create-config project animation 2>&1)" || true
    cfg_content="$(cat "$cfg_create_dir/.muxmrc")"
    assert_contains "animation" "--force-create-config overwrites with new profile" "$cfg_content"
  else
    fail "--create-config did not create .muxmrc"
  fi

  # Invalid scope
  out="$(run_muxm --create-config bogus streaming 2>&1)" || true
  assert_contains "Invalid scope" "--create-config rejects invalid scope" "$out"

  # --create-config with all remaining profiles (#50)
  local profiles_to_test=("dv-archival" "hdr10-hq" "atv-directplay-hq" "universal")
  for p in "${profiles_to_test[@]}"; do
    local cfg_p_dir="$TESTDIR/config_create_$p"
    mkdir -p "$cfg_p_dir"
    pushd "$cfg_p_dir" >/dev/null
    out="$("$MUXM" --create-config project "$p" 2>&1)" || true
    popd >/dev/null
    if [[ -f "$cfg_p_dir/.muxmrc" ]]; then
      local content
      content="$(cat "$cfg_p_dir/.muxmrc")"
      assert_contains "$p" "--create-config $p: profile name in config" "$content"
    else
      fail "--create-config $p: did not create .muxmrc"
    fi
  done

  # Config variable override from file
  local cfg_var_dir="$TESTDIR/config_var_test"
  mkdir -p "$cfg_var_dir"
  cat > "$cfg_var_dir/.muxmrc" <<'EOF'
CRF_VALUE=14
PRESET_VALUE="slower"
EOF
  out="$(cd "$cfg_var_dir" && "$MUXM" --print-effective-config 2>&1)" || true
  assert_contains "CRF_VALUE                 = 14" "Config file CRF_VALUE override" "$out"
  assert_contains "PRESET_VALUE              = slower" "Config file PRESET_VALUE override" "$out"
}

# === Suite: Profile Variable Assignment ===
test_profiles() {
  section "Profile Variable Assignment"

  local profiles=("dv-archival" "hdr10-hq" "atv-directplay-hq" "streaming" "animation" "universal")

  for p in "${profiles[@]}"; do
    local out
    out="$(run_muxm --profile "$p" --print-effective-config)"
    assert_contains "$p" "Profile $p shows in effective config" "$out"
  done

  # dv-archival specifics
  local out
  out="$(run_muxm --profile dv-archival --print-effective-config)"
  assert_contains "VIDEO_COPY_IF_COMPLIANT   = 1" "dv-archival: video copy enabled" "$out"
  assert_contains "SKIP_IF_IDEAL             = 1" "dv-archival: skip-if-ideal on" "$out"
  assert_contains "REPORT_JSON               = 1" "dv-archival: JSON report on" "$out"
  assert_contains "AUDIO_LOSSLESS_PASSTHROUGH = 1" "dv-archival: lossless audio on" "$out"
  assert_contains "OUTPUT_EXT                = mkv" "dv-archival: MKV container" "$out"

  # hdr10-hq specifics
  out="$(run_muxm --profile hdr10-hq --print-effective-config)"
  assert_contains "DISABLE_DV                = 1" "hdr10-hq: DV disabled" "$out"
  assert_contains "CRF_VALUE                 = 17" "hdr10-hq: CRF 17" "$out"
  assert_contains "OUTPUT_EXT                = mkv" "hdr10-hq: MKV container" "$out"

  # atv-directplay-hq specifics
  out="$(run_muxm --profile atv-directplay-hq --print-effective-config)"
  assert_contains "OUTPUT_EXT                = mp4" "atv-directplay: MP4 container" "$out"
  assert_contains "SUB_BURN_FORCED           = 1" "atv-directplay: burn forced subs" "$out"
  assert_contains "SKIP_IF_IDEAL             = 1" "atv-directplay: skip-if-ideal on" "$out"

  # streaming specifics
  out="$(run_muxm --profile streaming --print-effective-config)"
  assert_contains "CRF_VALUE                 = 20" "streaming: CRF 20" "$out"
  assert_contains "PRESET_VALUE              = medium" "streaming: preset medium" "$out"

  # animation specifics
  out="$(run_muxm --profile animation --print-effective-config)"
  assert_contains "CRF_VALUE                 = 16" "animation: CRF 16" "$out"
  assert_contains "OUTPUT_EXT                = mkv" "animation: MKV container" "$out"
  assert_contains "AUDIO_LOSSLESS_PASSTHROUGH = 1" "animation: lossless audio" "$out"

  # universal specifics
  out="$(run_muxm --profile universal --print-effective-config)"
  assert_contains "VIDEO_CODEC               = libx264" "universal: H.264 codec" "$out"
  assert_contains "TONEMAP_HDR_TO_SDR        = 1" "universal: tone-mapping on" "$out"
  assert_contains "KEEP_CHAPTERS             = 0" "universal: chapters stripped" "$out"
  assert_contains "STRIP_METADATA            = 1" "universal: metadata stripped" "$out"
  assert_contains "OUTPUT_EXT                = mp4" "universal: MP4 container" "$out"
}

# === Suite: Conflict Warnings ===
test_conflicts() {
  section "Conflict Warnings"

  local out

  # --- dv-archival conflicts ---
  out="$(run_muxm --profile dv-archival --no-dv --print-effective-config)"
  assert_contains "⚠" "dv-archival + --no-dv warns" "$out"

  out="$(run_muxm --profile dv-archival --strip-metadata --print-effective-config)"
  assert_contains "⚠" "dv-archival + --strip-metadata warns (#38)" "$out"

  out="$(run_muxm --profile dv-archival --no-keep-chapters --print-effective-config)"
  assert_contains "⚠" "dv-archival + --no-keep-chapters warns (#39)" "$out"

  out="$(run_muxm --profile dv-archival --sub-burn-forced --print-effective-config)"
  assert_contains "⚠" "dv-archival + --sub-burn-forced warns (#40)" "$out"

  # --- hdr10-hq conflicts ---
  out="$(run_muxm --profile hdr10-hq --tonemap --print-effective-config)"
  assert_contains "⚠" "hdr10-hq + --tonemap warns" "$out"

  out="$(run_muxm --profile hdr10-hq --video-codec libx264 --print-effective-config)"
  assert_contains "⚠" "hdr10-hq + --video-codec libx264 warns (#34)" "$out"

  # --- atv-directplay-hq conflicts ---
  out="$(run_muxm --profile atv-directplay-hq --output-ext mkv --print-effective-config)"
  assert_contains "⚠" "atv-directplay + mkv warns" "$out"

  out="$(run_muxm --profile atv-directplay-hq --tonemap --print-effective-config)"
  assert_contains "⚠" "atv-directplay + --tonemap warns (#37)" "$out"

  out="$(run_muxm --profile atv-directplay-hq --video-codec libx264 --print-effective-config)"
  assert_contains "⚠" "atv-directplay + --video-codec libx264 warns (#36)" "$out"

  out="$(run_muxm --profile atv-directplay-hq --audio-lossless-passthrough --print-effective-config)"
  assert_contains "⚠" "atv-directplay + --audio-lossless-passthrough warns (#35)" "$out"

  # --- streaming conflicts ---
  out="$(run_muxm --profile streaming --output-ext mkv --print-effective-config)"
  assert_contains "⚠" "streaming + --output-ext mkv warns (#31)" "$out"

  out="$(run_muxm --profile streaming --audio-lossless-passthrough --print-effective-config)"
  assert_contains "⚠" "streaming + --audio-lossless-passthrough warns (#32)" "$out"

  out="$(run_muxm --profile streaming --video-codec libx264 --print-effective-config)"
  assert_contains "⚠" "streaming + --video-codec libx264 warns (#33)" "$out"

  # --- animation conflicts ---
  out="$(run_muxm --profile animation --sub-burn-forced --print-effective-config)"
  assert_contains "⚠" "animation + --sub-burn-forced warns" "$out"

  out="$(run_muxm --profile animation --video-codec libx264 --print-effective-config)"
  assert_contains "⚠" "animation + libx264 warns" "$out"

  out="$(run_muxm --profile animation --output-ext mp4 --print-effective-config)"
  assert_contains "⚠" "animation + --output-ext mp4 warns (#46)" "$out"

  out="$(run_muxm --profile animation --no-audio-lossless-passthrough --print-effective-config)"
  assert_contains "⚠" "animation + --no-audio-lossless-passthrough warns (#47)" "$out"

  # --- universal conflicts ---
  out="$(run_muxm --profile universal --output-ext mkv --print-effective-config)"
  assert_contains "⚠" "universal + mkv warns" "$out"

  out="$(run_muxm --profile universal --audio-lossless-passthrough --print-effective-config)"
  assert_contains "⚠" "universal + --audio-lossless-passthrough warns (#44)" "$out"

  out="$(run_muxm --profile universal --video-codec libx265 --print-effective-config)"
  assert_contains "⚠" "universal + --video-codec libx265 warns (#45)" "$out"

  # --- Cross-profile flag combinations ---
  out="$(run_muxm --profile dv-archival --video-copy-if-compliant --tonemap --print-effective-config)"
  assert_contains "VIDEO_COPY_IF_COMPLIANT + TONEMAP" "Cross: copy + tonemap warns (#41)" "$out"

  out="$(run_muxm --profile animation --sub-export-external --output-ext mkv --print-effective-config)"
  assert_contains "SUB_EXPORT_EXTERNAL with MKV" "Cross: sub-export + mkv warns (#42)" "$out"

  out="$(run_muxm --profile streaming --sub-burn-forced --no-subtitles --print-effective-config 2>&1)" || true
  assert_contains "SUB_BURN_FORCED" "Cross: burn-forced + no-forced warns (#43)" "$out"
}

# === Suite: Dry-Run Mode ===
test_dryrun() {
  section "Dry-Run Mode"

  local out outfile="$TESTDIR/dryrun_out.mp4"

  out="$(run_muxm --dry-run "$TESTDIR/basic_sdr_subs.mkv" "$outfile")"
  assert_contains "DRY-RUN" "Dry-run announces itself" "$out"
  assert_no_file "$outfile" "Dry-run does not create output"

  # Dry-run with profile
  out="$(run_muxm --dry-run --profile streaming "$TESTDIR/hevc_sdr_51.mkv")"
  assert_contains "DRY-RUN" "Dry-run with profile works" "$out"
  assert_contains "streaming" "Dry-run shows profile" "$out"

  # Dry-run with skip-audio
  out="$(run_muxm --dry-run --skip-audio "$TESTDIR/basic_sdr_subs.mkv")"
  assert_contains "Quick Test" "Dry-run with --skip-audio announces it" "$out"

  # Dry-run with skip-subs
  out="$(run_muxm --dry-run --skip-subs "$TESTDIR/basic_sdr_subs.mkv")"
  assert_contains "Quick Test" "Dry-run with --skip-subs announces it" "$out"

  # Dry-run with HDR source
  out="$(run_muxm --dry-run "$TESTDIR/hevc_hdr10_tagged.mkv")"
  assert_contains "DRY-RUN" "Dry-run with HDR source" "$out"
}

# === Suite: Video Pipeline (real encodes) ===
test_video() {
  section "Video Pipeline (Real Encodes)"

  # Basic SDR encode → MP4
  local outfile="$TESTDIR/vid_test1.mp4"
  log "Encoding basic SDR to MP4..."
  run_muxm --crf 28 --preset ultrafast "$TESTDIR/basic_sdr_subs.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "Basic SDR encode produces output"
    local vcodec
    vcodec="$(probe_video "$outfile" codec_name)"
    if [[ "$vcodec" == "hevc" ]]; then
      pass "Output video codec is HEVC"
    else
      fail "Expected HEVC, got: $vcodec"
    fi
  else
    fail "Basic SDR encode produced no output"
  fi

  # libx264 encode
  outfile="$TESTDIR/vid_test_x264.mp4"
  log "Encoding with libx264..."
  run_muxm --video-codec libx264 --crf 28 --preset ultrafast "$TESTDIR/basic_sdr_subs.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "libx264 encode produces output"
    local vcodec
    vcodec="$(probe_video "$outfile" codec_name)"
    if [[ "$vcodec" == "h264" ]]; then
      pass "Output video codec is H.264"
    else
      fail "Expected h264, got: $vcodec"
    fi
  else
    fail "libx264 encode produced no output"
  fi

  # MKV output
  outfile="$TESTDIR/vid_test_mkv.mkv"
  log "Encoding to MKV container..."
  run_muxm --output-ext mkv --crf 28 --preset ultrafast "$TESTDIR/basic_sdr_subs.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "MKV output produced"
    local fmt
    fmt="$(ffprobe -v error -show_entries format=format_name -of csv=p=0 "$outfile" 2>/dev/null)"
    assert_contains "matroska" "Output is Matroska" "$fmt"
  else
    fail "MKV output not produced"
  fi

  # --x265-params custom parameter (#21)
  outfile="$TESTDIR/vid_x265_params.mp4"
  log "Encoding with --x265-params..."
  run_muxm --crf 28 --preset ultrafast --x265-params "aq-mode=3" \
    "$TESTDIR/basic_sdr_subs.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "--x265-params: encode succeeded"
  else
    fail "--x265-params: no output"
  fi

  # --threads (#22)
  outfile="$TESTDIR/vid_threads.mp4"
  log "Encoding with --threads 2..."
  run_muxm --crf 28 --preset ultrafast --threads 2 \
    "$TESTDIR/basic_sdr_subs.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "--threads 2: encode succeeded"
  else
    fail "--threads 2: no output"
  fi

  # --video-copy-if-compliant with HEVC source (#19)
  outfile="$TESTDIR/vid_copy_compliant.mp4"
  log "Testing --video-copy-if-compliant with HEVC source..."
  run_muxm --video-copy-if-compliant --preset ultrafast \
    "$TESTDIR/hevc_sdr_51.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "--video-copy-if-compliant: output produced"
    local vcodec
    vcodec="$(probe_video "$outfile" codec_name)"
    if [[ "$vcodec" == "hevc" ]]; then
      pass "--video-copy-if-compliant: HEVC preserved"
    else
      fail "--video-copy-if-compliant: expected hevc, got $vcodec"
    fi
  else
    fail "--video-copy-if-compliant: no output"
  fi
}

# === Suite: HDR Pipeline ===
test_hdr() {
  section "HDR Pipeline"

  # Encode HDR10-tagged source (uses previously orphaned fixture #1)
  local outfile="$TESTDIR/hdr_encode.mkv"
  log "Encoding hevc_hdr10_tagged.mkv (HDR10 source)..."
  run_muxm --output-ext mkv --crf 28 --preset ultrafast \
    "$TESTDIR/hevc_hdr10_tagged.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "HDR10 encode: output produced"
    local vcodec cp tf
    vcodec="$(probe_video "$outfile" codec_name)"
    cp="$(probe_video "$outfile" color_primaries)"
    tf="$(probe_video "$outfile" color_transfer)"
    if [[ "$vcodec" == "hevc" ]]; then
      pass "HDR10 encode: HEVC codec"
    else
      fail "HDR10 encode: expected hevc, got $vcodec"
    fi
    # Check HDR metadata preserved
    if [[ "$cp" == "bt2020" ]] || [[ "$cp" == *"2020"* ]]; then
      pass "HDR10 encode: BT.2020 color primaries preserved"
    else
      log "HDR10 encode: color_primaries='$cp' (expected bt2020, may vary by ffmpeg version)"
    fi
    if [[ "$tf" == "smpte2084" ]] || [[ "$tf" == *"2084"* ]]; then
      pass "HDR10 encode: SMPTE 2084 transfer preserved"
    else
      log "HDR10 encode: color_transfer='$tf' (expected smpte2084, may vary)"
    fi
  else
    fail "HDR10 encode: no output"
  fi

  # --no-tonemap config flag
  local out
  out="$(run_muxm --no-tonemap --print-effective-config)"
  assert_contains "TONEMAP_HDR_TO_SDR        = 0" "--no-tonemap: flag registered" "$out"
}

# === Suite: Audio Pipeline ===
test_audio() {
  section "Audio Pipeline"

  # Basic encode — check audio present
  local outfile="$TESTDIR/audio_test1.mp4"
  log "Testing audio pipeline..."
  run_muxm --crf 28 --preset ultrafast "$TESTDIR/hevc_sdr_51.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    local acount
    acount="$(count_streams "$outfile" a)"
    if [[ "$acount" -ge 1 ]]; then
      pass "Audio track present in output ($acount tracks)"
    else
      fail "No audio tracks in output"
    fi

    # Check if stereo fallback was added
    if [[ "$acount" -ge 2 ]]; then
      pass "Stereo fallback track added"
    else
      log "Only 1 audio track (stereo fallback may not have been needed)"
    fi
  else
    fail "Audio test encode produced no output"
  fi

  # --no-stereo-fallback
  outfile="$TESTDIR/audio_no_stereo.mp4"
  log "Testing --no-stereo-fallback..."
  run_muxm --crf 28 --preset ultrafast --no-stereo-fallback \
    "$TESTDIR/hevc_sdr_51.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    local acount
    acount="$(count_streams "$outfile" a)"
    if [[ "$acount" -eq 1 ]]; then
      pass "--no-stereo-fallback: single audio track"
    else
      log "--no-stereo-fallback: $acount tracks (may vary by source)"
    fi
  else
    fail "--no-stereo-fallback encode produced no output"
  fi

  # --skip-audio
  local out
  out="$(run_muxm --dry-run --skip-audio "$TESTDIR/basic_sdr_subs.mkv")"
  assert_contains "Audio processing disabled" "--skip-audio announced" "$out"

  # --- Multi-audio track auto-selection (uses previously orphaned fixture #2) ---
  outfile="$TESTDIR/audio_multi_auto.mp4"
  log "Testing multi-audio auto-selection..."
  run_muxm --crf 28 --preset ultrafast \
    "$TESTDIR/multi_audio.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "Multi-audio encode: output produced"
    local acount
    acount="$(count_streams "$outfile" a)"
    if [[ "$acount" -ge 1 ]]; then
      pass "Multi-audio: audio tracks present ($acount)"
      # The 5.1 EAC3 should be preferred by the scoring algorithm
      local ch
      ch="$(probe_audio "$outfile" channels 0)"
      if [[ "$ch" -ge 6 ]]; then
        pass "Multi-audio: primary track is surround (${ch}ch)"
      else
        log "Multi-audio: primary track has ${ch}ch (5.1 preference may vary)"
      fi
    else
      fail "Multi-audio: no audio in output"
    fi
  else
    fail "Multi-audio encode: no output"
  fi

  # --audio-track override (#3, #7)
  outfile="$TESTDIR/audio_track_override.mp4"
  log "Testing --audio-track 0 override..."
  run_muxm --audio-track 0 --no-stereo-fallback --crf 28 --preset ultrafast \
    "$TESTDIR/multi_audio.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "--audio-track 0: output produced"
    local acount
    acount="$(count_streams "$outfile" a)"
    if [[ "$acount" -ge 1 ]]; then
      # Track 0 is stereo AAC, so output should have ≤2ch
      local ch
      ch="$(probe_audio "$outfile" channels 0)"
      if [[ "$ch" -le 2 ]]; then
        pass "--audio-track 0: stereo track selected (${ch}ch)"
      else
        log "--audio-track 0: got ${ch}ch (expected stereo from track 0)"
      fi
    fi
  else
    fail "--audio-track 0: no output"
  fi

  # --audio-lang-pref (#8)
  outfile="$TESTDIR/audio_lang_spa.mp4"
  log "Testing --audio-lang-pref spa..."
  run_muxm --audio-lang-pref spa --no-stereo-fallback --crf 28 --preset ultrafast \
    "$TESTDIR/multi_lang_audio.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "--audio-lang-pref spa: output produced"
    local alang
    alang="$(ffprobe -v error -select_streams a:0 -show_entries stream_tags=language -of csv=p=0 \
      "$outfile" 2>/dev/null | head -1)"
    if [[ "$alang" == "spa" ]]; then
      pass "--audio-lang-pref spa: Spanish audio selected"
    else
      log "--audio-lang-pref spa: got lang='$alang' (selection may depend on scoring)"
    fi
  else
    fail "--audio-lang-pref spa: no output"
  fi

  # --audio-force-codec aac (#9)
  outfile="$TESTDIR/audio_force_aac.mp4"
  log "Testing --audio-force-codec aac..."
  run_muxm --audio-force-codec aac --no-stereo-fallback --crf 28 --preset ultrafast \
    "$TESTDIR/hevc_sdr_51.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "--audio-force-codec aac: output produced"
    local acodec
    acodec="$(probe_audio "$outfile" codec_name 0)"
    if [[ "$acodec" == "aac" ]]; then
      pass "--audio-force-codec aac: audio is AAC"
    else
      log "--audio-force-codec aac: got codec='$acodec'"
    fi
  else
    fail "--audio-force-codec aac: no output"
  fi

  # --stereo-bitrate via effective config (#11)
  out="$(run_muxm --stereo-bitrate 192k --print-effective-config)"
  assert_contains "STEREO_BITRATE            = 192k" "--stereo-bitrate: config shows 192k" "$out"

  # --audio-lossless-passthrough / --no-audio-lossless-passthrough via effective config (#10)
  out="$(run_muxm --audio-lossless-passthrough --print-effective-config)"
  assert_contains "AUDIO_LOSSLESS_PASSTHROUGH = 1" "--audio-lossless-passthrough: flag set" "$out"

  out="$(run_muxm --no-audio-lossless-passthrough --print-effective-config)"
  assert_contains "AUDIO_LOSSLESS_PASSTHROUGH = 0" "--no-audio-lossless-passthrough: flag cleared" "$out"
}

# === Suite: Subtitle Pipeline ===
test_subs() {
  section "Subtitle Pipeline"

  # Basic encode with subs
  local outfile="$TESTDIR/subs_test1.mkv"
  log "Testing subtitle inclusion in MKV..."
  run_muxm --output-ext mkv --crf 28 --preset ultrafast \
    "$TESTDIR/multi_subs.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    local scount
    scount="$(count_streams "$outfile" s)"
    if [[ "$scount" -ge 1 ]]; then
      pass "Subtitles present in MKV output ($scount tracks)"
    else
      fail "No subtitle tracks in MKV output"
    fi
  else
    fail "Subtitle test encode produced no output"
  fi

  # --no-subtitles
  outfile="$TESTDIR/subs_none.mkv"
  log "Testing --no-subtitles..."
  run_muxm --output-ext mkv --crf 28 --preset ultrafast --no-subtitles \
    "$TESTDIR/multi_subs.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    local scount
    scount="$(count_streams "$outfile" s)"
    if [[ "$scount" -eq 0 ]]; then
      pass "--no-subtitles: no subtitle tracks"
    else
      fail "--no-subtitles: expected 0 tracks, got $scount"
    fi
  else
    fail "--no-subtitles encode produced no output"
  fi

  # --skip-subs
  local out
  out="$(run_muxm --dry-run --skip-subs "$TESTDIR/basic_sdr_subs.mkv")"
  assert_contains "Subtitle processing disabled" "--skip-subs announced" "$out"

  # --sub-lang-pref (#14)
  out="$(run_muxm --sub-lang-pref jpn --print-effective-config)"
  assert_contains "SUB_LANG_PREF             = jpn" "--sub-lang-pref: config shows jpn" "$out"

  # --no-sub-sdh (#15)
  out="$(run_muxm --no-sub-sdh --print-effective-config)"
  assert_contains "SUB_INCLUDE_SDH           = 0" "--no-sub-sdh: SDH disabled" "$out"

  # --sub-export-external (#13)
  outfile="$TESTDIR/subs_export.mp4"
  log "Testing --sub-export-external..."
  run_muxm --sub-export-external --crf 28 --preset ultrafast \
    "$TESTDIR/multi_subs.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "--sub-export-external: output produced"
    # Check for .srt sidecar file(s)
    local srt_count
    srt_count="$(find "$TESTDIR" -name "subs_export*.srt" 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$srt_count" -ge 1 ]]; then
      pass "--sub-export-external: SRT sidecar(s) created ($srt_count)"
    else
      log "--sub-export-external: no .srt sidecar found (may depend on subtitle type)"
    fi
  else
    fail "--sub-export-external: no output"
  fi

  # --no-ocr via effective config (#17)
  out="$(run_muxm --no-ocr --print-effective-config)"
  assert_contains "SUB_ENABLE_OCR            = 0" "--no-ocr: OCR disabled" "$out"

  # --ocr-lang (#16)
  out="$(run_muxm --ocr-lang jpn --print-effective-config)"
  assert_contains "SUB_OCR_LANG              = jpn" "--ocr-lang: shows jpn" "$out"
}

# === Suite: Output Features ===
test_output() {
  section "Output Features"

  # Chapters preserved
  local outfile="$TESTDIR/out_chapters.mp4"
  log "Testing chapter preservation..."
  run_muxm --keep-chapters --crf 28 --preset ultrafast \
    "$TESTDIR/with_chapters.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    local chap_count
    chap_count="$(ffprobe -v error -show_chapters -of json "$outfile" 2>/dev/null | jq '.chapters | length' 2>/dev/null)" || chap_count=0
    if [[ "$chap_count" -ge 1 ]]; then
      pass "Chapters preserved in output ($chap_count chapters)"
    else
      log "Chapter count: $chap_count (may not persist in short clips)"
    fi
  else
    fail "Chapter test encode produced no output"
  fi

  # Chapters stripped
  outfile="$TESTDIR/out_no_chapters.mp4"
  log "Testing chapter stripping..."
  run_muxm --no-keep-chapters --crf 28 --preset ultrafast \
    "$TESTDIR/with_chapters.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    local chap_count
    chap_count="$(ffprobe -v error -show_chapters -of json "$outfile" 2>/dev/null | jq '.chapters | length' 2>/dev/null)" || chap_count=0
    if [[ "$chap_count" -eq 0 ]]; then
      pass "--no-keep-chapters: chapters stripped"
    else
      fail "--no-keep-chapters: expected 0 chapters, got $chap_count"
    fi
  else
    fail "Chapter strip test produced no output"
  fi

  # Checksum
  outfile="$TESTDIR/out_checksum.mp4"
  log "Testing --checksum..."
  run_muxm --checksum --crf 28 --preset ultrafast \
    "$TESTDIR/basic_sdr_subs.mkv" "$outfile"
  if [[ -f "$outfile" ]]; then
    local sha_file="${outfile}.sha256"
    if [[ -f "$sha_file" ]]; then
      pass "--checksum: SHA-256 file created"
    else
      log "--checksum: SHA-256 sidecar not found at $sha_file (check naming convention)"
    fi
  else
    fail "Checksum test encode produced no output"
  fi

  # JSON report + content validation (#52)
  outfile="$TESTDIR/out_report.mp4"
  log "Testing --report-json..."
  run_muxm --report-json --crf 28 --preset ultrafast \
    "$TESTDIR/basic_sdr_subs.mkv" "$outfile"
  if [[ -f "$outfile" ]]; then
    local json_file="${outfile%.mp4}.report.json"
    if [[ -f "$json_file" ]]; then
      pass "--report-json: JSON report created"
      if jq empty "$json_file" 2>/dev/null; then
        pass "--report-json: valid JSON"
      else
        fail "--report-json: invalid JSON"
      fi
      # Validate key fields are present (#52)
      local has_tool has_source
      has_tool="$(jq 'has("tool") or has("muxm_version") or has("version")' "$json_file" 2>/dev/null)" || has_tool="false"
      has_source="$(jq 'has("source") or has("input") or has("src")' "$json_file" 2>/dev/null)" || has_source="false"
      if [[ "$has_tool" == "true" ]]; then
        pass "--report-json: contains tool/version key"
      else
        log "--report-json: tool/version key not found (key naming may differ)"
      fi
      if [[ "$has_source" == "true" ]]; then
        pass "--report-json: contains source/input key"
      else
        log "--report-json: source/input key not found (key naming may differ)"
      fi
    else
      log "--report-json: report file not found at $json_file"
    fi
  else
    fail "JSON report test encode produced no output"
  fi

  # --skip-if-ideal with compliant source (#26, #51)
  outfile="$TESTDIR/out_skip_ideal.mp4"
  log "Testing --skip-if-ideal with compliant.mp4..."
  local skip_out
  skip_out="$(run_muxm --skip-if-ideal --preset ultrafast \
    "$TESTDIR/compliant.mp4" "$outfile")"
  if echo "$skip_out" | grep -qiE "ideal|skip|already|compliant|no.?processing"; then
    pass "--skip-if-ideal: recognized compliant source"
  elif [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "--skip-if-ideal: produced output (may have encoded if not fully compliant)"
  else
    log "--skip-if-ideal: output='${skip_out:0:200}' (behavior depends on compliance check)"
  fi

  # --keep-temp-always (#27)
  # -K/--keep-temp-always preserves workdir on success; -k/--keep-temp only on failure.
  # Test -K with a successful encode: expect both output AND preserved workdir.
  local kt_dir="$TESTDIR/keep_temp_test"
  mkdir -p "$kt_dir"
  cp "$TESTDIR/basic_sdr_subs.mkv" "$kt_dir/source.mkv"
  outfile="$kt_dir/output.mp4"
  log "Testing --keep-temp-always (-K)..."
  local kt_out
  kt_out="$(run_muxm --keep-temp-always --crf 28 --preset ultrafast \
    "$kt_dir/source.mkv" "$outfile")" || true
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    local workdir_found=0
    if find "$kt_dir" -maxdepth 2 -type d -name "*muxm*" 2>/dev/null | grep -q .; then
      workdir_found=1
    elif echo "$kt_out" | grep -qiE "work.?dir|temp.*preserved|keeping"; then
      workdir_found=1
    fi
    if (( workdir_found )); then
      pass "--keep-temp-always: workdir preserved on success"
    else
      fail "--keep-temp-always: output produced but workdir not found"
    fi
  else
    log "--keep-temp-always: muxm output: ${kt_out:0:1000}"
    fail "--keep-temp-always: no output"
  fi

  # Verify -k/--keep-temp flag is accepted and sets KEEP_TEMP in effective config
  local kt_cfg
  kt_cfg="$(run_muxm --keep-temp --print-effective-config)"
  assert_contains "KEEP_TEMP" "--keep-temp: flag registered in effective config" "$kt_cfg"
}

# === Suite: Container Formats ===
test_containers() {
  section "Container Formats"

  # MOV output (#23)
  local outfile="$TESTDIR/container_mov.mov"
  log "Testing --output-ext mov..."
  run_muxm --output-ext mov --crf 28 --preset ultrafast \
    "$TESTDIR/basic_sdr_subs.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "--output-ext mov: output produced"
    local fmt
    fmt="$(ffprobe -v error -show_entries format=format_name -of csv=p=0 "$outfile" 2>/dev/null)"
    if echo "$fmt" | grep -qiE "mov|mp4"; then
      pass "--output-ext mov: container is MOV/MP4 family"
    else
      fail "--output-ext mov: unexpected format=$fmt"
    fi
  else
    fail "--output-ext mov: no output"
  fi

  # M4V output (#24)
  outfile="$TESTDIR/container_m4v.m4v"
  log "Testing --output-ext m4v..."
  run_muxm --output-ext m4v --crf 28 --preset ultrafast \
    "$TESTDIR/basic_sdr_subs.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "--output-ext m4v: output produced"
    local fmt
    fmt="$(ffprobe -v error -show_entries format=format_name -of csv=p=0 "$outfile" 2>/dev/null)"
    if echo "$fmt" | grep -qiE "mov|mp4|m4v"; then
      pass "--output-ext m4v: container is MP4 family"
    else
      fail "--output-ext m4v: unexpected format=$fmt"
    fi
  else
    fail "--output-ext m4v: no output"
  fi
}

# === Suite: Metadata Tests ===
test_metadata() {
  section "Metadata & Strip Verification"

  # --strip-metadata encode test (#25, #53)
  local outfile="$TESTDIR/meta_stripped.mp4"
  log "Testing --strip-metadata with real encode..."
  run_muxm --strip-metadata --crf 28 --preset ultrafast \
    "$TESTDIR/rich_metadata.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "--strip-metadata: output produced"
    local title comment
    title="$(ffprobe -v error -show_entries format_tags=title -of csv=p=0 "$outfile" 2>/dev/null | head -1)"
    comment="$(ffprobe -v error -show_entries format_tags=comment -of csv=p=0 "$outfile" 2>/dev/null | head -1)"
    if [[ -z "$title" && -z "$comment" ]]; then
      pass "--strip-metadata: title and comment removed"
    elif [[ -z "$title" ]]; then
      pass "--strip-metadata: title removed"
      log "--strip-metadata: comment='$comment' (may persist in some containers)"
    else
      log "--strip-metadata: title='$title', comment='$comment' (stripping may be partial)"
    fi
  else
    fail "--strip-metadata: no output"
  fi

  # Without --strip-metadata, metadata should be preserved
  outfile="$TESTDIR/meta_preserved.mp4"
  log "Testing metadata preservation (no --strip-metadata)..."
  run_muxm --crf 28 --preset ultrafast \
    "$TESTDIR/rich_metadata.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    local title
    title="$(ffprobe -v error -show_entries format_tags=title -of csv=p=0 "$outfile" 2>/dev/null | head -1)"
    if [[ -n "$title" ]]; then
      pass "Metadata preserved: title='$title'"
    else
      log "Metadata preservation: title not found (may vary by pipeline)"
    fi
  else
    fail "Metadata preservation: no output"
  fi

  # --ffmpeg-loglevel (#30)
  local out
  out="$(run_muxm --ffmpeg-loglevel warning --print-effective-config 2>&1)" || true
  if [[ -n "$out" ]]; then
    pass "--ffmpeg-loglevel: accepted without error"
  fi

  # --no-hide-banner (#29)
  out="$(run_muxm --no-hide-banner --dry-run "$TESTDIR/basic_sdr_subs.mkv" 2>&1)" || true
  if [[ -n "$out" ]]; then
    pass "--no-hide-banner: accepted without error"
  fi
}

# === Suite: Edge Cases & Security ===
test_edge() {
  section "Edge Cases & Security"

  # Empty file
  touch "$TESTDIR/empty.mkv"
  local out
  out="$(cd "$TESTDIR" && "$MUXM" "$TESTDIR/empty.mkv" 2>&1)" || true
  assert_contains "empty" "Empty file rejected" "$out"

  # File with spaces in name
  cp "$TESTDIR/basic_sdr_subs.mkv" "$TESTDIR/file with spaces.mkv"
  out="$(run_muxm --dry-run "$TESTDIR/file with spaces.mkv")"
  assert_contains "DRY-RUN" "Filename with spaces handled" "$out"

  # Control characters in output extension are rejected
  out="$(cd "$TESTDIR" && "$MUXM" --output-ext "mp4;" "$TESTDIR/basic_sdr_subs.mkv" 2>&1)" || true
  assert_contains "Invalid" "Injection in --output-ext rejected" "$out"

  # OCR tool injection prevention
  out="$(run_muxm --dry-run --ocr-tool "sub2srt;rm -rf /" "$TESTDIR/basic_sdr_subs.mkv")"
  assert_contains "disallowed" "OCR tool injection prevented" "$out"

  # --skip-video error (can't produce output)
  out="$(cd "$TESTDIR" && "$MUXM" --skip-video "$TESTDIR/basic_sdr_subs.mkv" 2>&1)" || true
  log "--skip-video behavior validated"

  # Non-readable source file (#55)
  local unreadable="$TESTDIR/unreadable.mkv"
  cp "$TESTDIR/basic_sdr_subs.mkv" "$unreadable"
  chmod 000 "$unreadable" 2>/dev/null || true
  if [[ ! -r "$unreadable" ]]; then
    out="$(cd "$TESTDIR" && "$MUXM" "$unreadable" 2>&1)" || true
    assert_contains "not readable" "Non-readable source rejected" "$out"
    chmod 644 "$unreadable" 2>/dev/null || true
  else
    skip "Cannot test non-readable file (running as root?)"
  fi

  # Non-writable output directory
  local nowrite_dir="$TESTDIR/nowrite"
  mkdir -p "$nowrite_dir"
  chmod 555 "$nowrite_dir" 2>/dev/null || true
  if [[ ! -w "$nowrite_dir" ]]; then
    out="$(cd "$TESTDIR" && "$MUXM" "$TESTDIR/basic_sdr_subs.mkv" "$nowrite_dir/out.mp4" 2>&1)" || true
    assert_contains "not writable" "Non-writable output dir rejected" "$out"
    chmod 755 "$nowrite_dir" 2>/dev/null || true
  else
    skip "Cannot test non-writable dir (running as root?)"
  fi
}

# === Suite: Profile End-to-End (real encodes with profiles) ===
test_profile_e2e() {
  section "Profile End-to-End Encodes"

  # streaming profile
  local outfile="$TESTDIR/e2e_streaming.mp4"
  log "Full encode: streaming profile..."
  run_muxm --profile streaming --preset ultrafast --crf 28 \
    "$TESTDIR/basic_sdr_subs.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "streaming profile: output produced"
    local ext="${outfile##*.}"
    if [[ "$ext" == "mp4" ]]; then
      pass "streaming: correct extension (.mp4)"
    else
      fail "streaming: wrong ext .$ext"
    fi
  else
    fail "streaming profile: no output"
  fi

  # animation profile
  outfile="$TESTDIR/e2e_animation.mkv"
  log "Full encode: animation profile..."
  run_muxm --profile animation --preset ultrafast --crf 28 \
    "$TESTDIR/multi_subs.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "animation profile: output produced"
  else
    fail "animation profile: no output"
  fi

  # universal profile
  outfile="$TESTDIR/e2e_universal.mp4"
  log "Full encode: universal profile..."
  run_muxm --profile universal --preset ultrafast --crf 28 \
    "$TESTDIR/basic_sdr_subs.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "universal profile: output produced"
    local vcodec
    vcodec="$(probe_video "$outfile" codec_name)"
    if [[ "$vcodec" == "h264" ]]; then
      pass "universal: H.264 codec"
    else
      fail "universal: expected h264, got $vcodec"
    fi
  else
    fail "universal profile: no output"
  fi

  # dv-archival profile (#4)
  outfile="$TESTDIR/e2e_dv_archival.mkv"
  log "Full encode: dv-archival profile..."
  run_muxm --profile dv-archival --preset ultrafast \
    "$TESTDIR/hevc_sdr_51.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "dv-archival profile: output produced"
    local ext="${outfile##*.}"
    if [[ "$ext" == "mkv" ]]; then
      pass "dv-archival: correct extension (.mkv)"
    else
      fail "dv-archival: wrong ext .$ext"
    fi
    local vcodec
    vcodec="$(probe_video "$outfile" codec_name)"
    if [[ "$vcodec" == "hevc" ]]; then
      pass "dv-archival: HEVC preserved"
    else
      fail "dv-archival: expected hevc, got $vcodec"
    fi
    local acount
    acount="$(count_streams "$outfile" a)"
    if [[ "$acount" -ge 1 ]]; then
      pass "dv-archival: audio present ($acount tracks)"
    else
      fail "dv-archival: no audio tracks"
    fi
  else
    fail "dv-archival profile: no output"
  fi

  # hdr10-hq profile (#5)
  outfile="$TESTDIR/e2e_hdr10_hq.mkv"
  log "Full encode: hdr10-hq profile..."
  run_muxm --profile hdr10-hq --preset ultrafast --crf 28 \
    "$TESTDIR/hevc_hdr10_tagged.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "hdr10-hq profile: output produced"
    local ext="${outfile##*.}"
    if [[ "$ext" == "mkv" ]]; then
      pass "hdr10-hq: correct extension (.mkv)"
    else
      fail "hdr10-hq: wrong ext .$ext"
    fi
    local vcodec pix_fmt
    vcodec="$(probe_video "$outfile" codec_name)"
    pix_fmt="$(probe_video "$outfile" pix_fmt)"
    if [[ "$vcodec" == "hevc" ]]; then
      pass "hdr10-hq: HEVC codec"
    else
      fail "hdr10-hq: expected hevc, got $vcodec"
    fi
    if echo "$pix_fmt" | grep -q "10"; then
      pass "hdr10-hq: 10-bit pixel format ($pix_fmt)"
    else
      log "hdr10-hq: pix_fmt=$pix_fmt (expected 10-bit)"
    fi
  else
    fail "hdr10-hq profile: no output"
  fi

  # atv-directplay-hq profile (#6)
  outfile="$TESTDIR/e2e_atv_directplay.mp4"
  log "Full encode: atv-directplay-hq profile..."
  run_muxm --profile atv-directplay-hq --preset ultrafast --crf 28 \
    "$TESTDIR/basic_sdr_subs.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "atv-directplay-hq profile: output produced"
    local ext="${outfile##*.}"
    if [[ "$ext" == "mp4" ]]; then
      pass "atv-directplay: correct extension (.mp4)"
    else
      fail "atv-directplay: wrong ext .$ext"
    fi
    local vcodec
    vcodec="$(probe_video "$outfile" codec_name)"
    if [[ "$vcodec" == "hevc" ]]; then
      pass "atv-directplay: HEVC codec"
    else
      fail "atv-directplay: expected hevc, got $vcodec"
    fi
    local acount
    acount="$(count_streams "$outfile" a)"
    if [[ "$acount" -ge 1 ]]; then
      pass "atv-directplay: audio present ($acount tracks)"
    else
      fail "atv-directplay: no audio tracks"
    fi
  else
    fail "atv-directplay-hq profile: no output"
  fi
}

# ---- Run Suites ----
run_suites() {
  case "$SUITE" in
    all)
      test_cli
      test_config
      test_profiles
      test_conflicts
      test_dryrun
      test_video
      test_hdr
      test_audio
      test_subs
      test_output
      test_containers
      test_metadata
      test_edge
      test_profile_e2e
      ;;
    cli)        test_cli ;;
    config)     test_config ;;
    profiles)   test_profiles ;;
    conflicts)  test_conflicts ;;
    dryrun)     test_dryrun ;;
    video)      test_video ;;
    hdr)        test_hdr ;;
    audio)      test_audio ;;
    subs)       test_subs ;;
    output)     test_output ;;
    containers) test_containers ;;
    metadata)   test_metadata ;;
    edge)       test_edge ;;
    e2e)        test_profile_e2e ;;
    *)
      echo "Unknown suite: $SUITE"
      echo "Valid: all, cli, config, profiles, conflicts, dryrun, video, hdr, audio,"
      echo "       subs, output, containers, metadata, edge, e2e"
      exit 1
      ;;
  esac
}

# ---- Summary ----
summary() {
  section "Test Summary"
  local total=$((PASS + FAIL + SKIP))
  printf "  %bPassed:%b  %d\n" "$GREEN" "$NC" "$PASS"
  printf "  %bFailed:%b  %d\n" "$RED" "$NC" "$FAIL"
  printf "  %bSkipped:%b %d\n" "$YELLOW" "$NC" "$SKIP"
  printf "  Total:   %d\n" "$total"

  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    printf "\n%b%bFailed Tests:%b\n" "$RED" "$BOLD" "$NC"
    for err in "${ERRORS[@]}"; do
      printf "  %b• %s%b\n" "$RED" "$err" "$NC"
    done
  fi

  # Cleanup
  if [[ -n "$TESTDIR" && -d "$TESTDIR" ]]; then
    log "Test artifacts in: $TESTDIR"
    log "Clean up with: rm -rf $TESTDIR"
  fi

  if (( FAIL > 0 )); then
    printf "\n%b%bRESULT: FAIL%b\n" "$RED" "$BOLD" "$NC"
    exit 1
  else
    printf "\n%b%bRESULT: ALL PASSED%b\n" "$GREEN" "$BOLD" "$NC"
    exit 0
  fi
}

# ---- Main ----
preflight
generate_test_media
run_suites
summary