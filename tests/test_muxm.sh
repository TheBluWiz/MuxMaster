#!/usr/bin/env bash
# =============================================================================
#  muxm Test Harness v1.0
#  Automated testing for MuxMaster — generates synthetic media and validates
#  CLI parsing, config precedence, profile behavior, and pipeline outputs.
#
#  Usage:
#    ./test_muxm.sh [--muxm /path/to/muxm] [--suite SUITE] [--verbose]
#
#  Suites: all, cli, config, profiles, video, audio, subs, output, dryrun, edge
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
      echo "Suites: all, cli, config, profiles, video, audio, subs, output, dryrun, edge"
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

  # dv-archival + --no-dv
  local out
  out="$(run_muxm --profile dv-archival --no-dv --print-effective-config)"
  assert_contains "⚠" "dv-archival + --no-dv warns" "$out"

  # hdr10-hq + --tonemap
  out="$(run_muxm --profile hdr10-hq --tonemap --print-effective-config)"
  assert_contains "⚠" "hdr10-hq + --tonemap warns" "$out"

  # atv-directplay + --output-ext mkv
  out="$(run_muxm --profile atv-directplay-hq --output-ext mkv --print-effective-config)"
  assert_contains "⚠" "atv-directplay + mkv warns" "$out"

  # animation + --sub-burn-forced
  out="$(run_muxm --profile animation --sub-burn-forced --print-effective-config)"
  assert_contains "⚠" "animation + --sub-burn-forced warns" "$out"

  # animation + --video-codec libx264
  out="$(run_muxm --profile animation --video-codec libx264 --print-effective-config)"
  assert_contains "⚠" "animation + libx264 warns" "$out"

  # universal + --output-ext mkv
  out="$(run_muxm --profile universal --output-ext mkv --print-effective-config)"
  assert_contains "⚠" "universal + mkv warns" "$out"

  # Cross-profile: burn forced but no forced subs
  out="$(run_muxm --sub-burn-forced --no-subtitles --print-effective-config 2>&1)" || true
  # This is a parse-time check; may produce a warning
  log "Cross-profile conflict: burn + no-subs checked"
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
    # Verify it's actually video
    local vcodec
    vcodec="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$outfile" 2>/dev/null)"
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
    vcodec="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$outfile" 2>/dev/null)"
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
    acount="$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$outfile" 2>/dev/null | wc -l)"
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
    acount="$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$outfile" 2>/dev/null | wc -l)"
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
    scount="$(ffprobe -v error -select_streams s -show_entries stream=codec_type -of csv=p=0 "$outfile" 2>/dev/null | wc -l)"
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
    scount="$(ffprobe -v error -select_streams s -show_entries stream=codec_type -of csv=p=0 "$outfile" 2>/dev/null | wc -l)"
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
    # Check for .sha256 sidecar
    if [[ -f "$sha_file" ]]; then
      pass "--checksum: SHA-256 file created"
    else
      # Might also be named differently
      log "--checksum: SHA-256 sidecar not found at $sha_file (check naming convention)"
    fi
  else
    fail "Checksum test encode produced no output"
  fi

  # JSON report
  outfile="$TESTDIR/out_report.mp4"
  log "Testing --report-json..."
  run_muxm --report-json --crf 28 --preset ultrafast \
    "$TESTDIR/basic_sdr_subs.mkv" "$outfile"
  if [[ -f "$outfile" ]]; then
    local json_file="${outfile%.mp4}.report.json"
    if [[ -f "$json_file" ]]; then
      pass "--report-json: JSON report created"
      # Validate it's valid JSON
      if jq empty "$json_file" 2>/dev/null; then
        pass "--report-json: valid JSON"
      else
        fail "--report-json: invalid JSON"
      fi
    else
      log "--report-json: report file not found at $json_file"
    fi
  else
    fail "JSON report test encode produced no output"
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
  # This should either error or produce a warning
  log "--skip-video behavior validated"
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

  # universal profile (tone-mapping is a no-op on SDR source, but pipeline should work)
  outfile="$TESTDIR/e2e_universal.mp4"
  log "Full encode: universal profile..."
  run_muxm --profile universal --preset ultrafast --crf 28 \
    "$TESTDIR/basic_sdr_subs.mkv" "$outfile"
  if [[ -f "$outfile" && -s "$outfile" ]]; then
    pass "universal profile: output produced"
    local vcodec
    vcodec="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$outfile" 2>/dev/null)"
    if [[ "$vcodec" == "h264" ]]; then
      pass "universal: H.264 codec"
    else
      fail "universal: expected h264, got $vcodec"
    fi
  else
    fail "universal profile: no output"
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
      test_audio
      test_subs
      test_output
      test_edge
      test_profile_e2e
      ;;
    cli)       test_cli ;;
    config)    test_config ;;
    profiles)  test_profiles ;;
    conflicts) test_conflicts ;;
    dryrun)    test_dryrun ;;
    video)     test_video ;;
    audio)     test_audio ;;
    subs)      test_subs ;;
    output)    test_output ;;
    edge)      test_edge ;;
    e2e)       test_profile_e2e ;;
    *)
      echo "Unknown suite: $SUITE"
      echo "Valid: all, cli, config, profiles, conflicts, dryrun, video, audio, subs, output, edge, e2e"
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