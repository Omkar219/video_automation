#!/usr/bin/env bash
set -euo pipefail

# video_automation.sh — Minimal CLI to rotate and split videos into segments using FFmpeg
#
# Usage examples:
#   Single file, copy when possible (fast):
#     ./video_automation.sh -i input.mp4 -t 60 -o ./out
#   Force rotate 180° (re-encodes video):
#     ./video_automation.sh -i input.mp4 --rotate 180 -t 60 -o ./out
#   Batch process all videos in a directory:
#     ./video_automation.sh -D ./videos -t 60 -o ./out --rotate auto
#   Show help:
#     ./video_automation.sh --help

SCRIPT_NAME="$(basename "$0")"

print_usage() {
  cat <<EOF
$SCRIPT_NAME — Rotate and split videos into fixed-length segments using FFmpeg

Required (pick one):
  -i, --input <file>          Path to a single input video file
  -D, --input-dir <dir>       Path to a directory to batch process (recurses)

Options:
  -o, --output-dir <dir>      Output directory (default: ./output)
  -t, --segment-time <sec>    Segment length in seconds (default: 60)
      --rotate <val>          Rotate: 0 | 90 | 180 | 270 | auto (default: 0)
      --reencode <mode>       auto | always | never (default: auto)
      --vcodec <codec>        Video codec when re-encoding (default: libx264)
      --crf <val>             CRF for x264/x265 (default: 23)
      --preset <val>          Preset for encoder (default: medium)
      --pattern <fmt>         Output filename pattern (default: <basename>_%03d.mp4)
      --start <time>          Start time (ffmpeg -ss), e.g. 00:00:10
      --end <time>            End time (ffmpeg -to), e.g. 00:05:00
      --threads <n>           Number of threads to use (optional)
      --dry-run               Print commands without executing
  -y, --overwrite             Overwrite output files without asking
  -h, --help                  Show this help

Notes:
- If rotation is applied or filters are used, re-encoding is required.
- Without filters and with --reencode auto, the script uses stream copy for speed.
EOF
}

# Defaults
input_file=""
input_dir=""
output_dir="./output"
segment_time="60"
rotate="0"
reencode_mode="auto"
vcodec="libx264"
crf="23"
preset="medium"
pattern=""
start_time=""
end_time=""
threads=""
dry_run=false
overwrite=false

# Parse arguments
ARGS=("$@")
if [[ ${#ARGS[@]} -eq 0 ]]; then
  print_usage
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input)
      input_file="${2:-}"; shift 2 ;;
    -D|--input-dir)
      input_dir="${2:-}"; shift 2 ;;
    -o|--output-dir)
      output_dir="${2:-}"; shift 2 ;;
    -t|--segment-time)
      segment_time="${2:-}"; shift 2 ;;
    --rotate)
      rotate="${2:-}"; shift 2 ;;
    --reencode)
      reencode_mode="${2:-}"; shift 2 ;;
    --vcodec)
      vcodec="${2:-}"; shift 2 ;;
    --crf)
      crf="${2:-}"; shift 2 ;;
    --preset)
      preset="${2:-}"; shift 2 ;;
    --pattern)
      pattern="${2:-}"; shift 2 ;;
    --start)
      start_time="${2:-}"; shift 2 ;;
    --end)
      end_time="${2:-}"; shift 2 ;;
    --threads)
      threads="${2:-}"; shift 2 ;;
    --dry-run)
      dry_run=true; shift ;;
    -y|--overwrite)
      overwrite=true; shift ;;
    -h|--help)
      print_usage; exit 0 ;;
    --)
      shift; break ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Use --help to see usage." >&2
      exit 1 ;;
  esac
done

# Basic validation
if [[ -z "$input_file" && -z "$input_dir" ]]; then
  echo "Error: Provide either --input <file> or --input-dir <dir>." >&2
  exit 1
fi
if [[ -n "$input_file" && -n "$input_dir" ]]; then
  echo "Error: Use only one of --input or --input-dir, not both." >&2
  exit 1
fi

# Check tools only if we will actually run work
require_tools() {
  command -v ffmpeg >/dev/null 2>&1 || { echo "Error: ffmpeg not found in PATH." >&2; exit 127; }
  command -v ffprobe >/dev/null 2>&1 || { echo "Error: ffprobe not found in PATH." >&2; exit 127; }
}

# Determine rotation filter string
rotation_filter_from_value() {
  local value="$1"
  case "$value" in
    0|"0") echo "" ;;
    90|"90") echo "-vf transpose=1" ;;   # 90° clockwise
    180|"180") echo "-vf transpose=2,transpose=2" ;; # 180°
    270|"270") echo "-vf transpose=2" ;;  # 90° counterclockwise
    *) echo "INVALID" ;;
  esac
}

# Probe auto-rotation from metadata (rotate tag)
auto_rotation_filter() {
  local file="$1"
  local tag
  tag=$(ffprobe -v error -select_streams v:0 -show_entries stream_tags=rotate -of default=nw=1:nk=1 "$file" || true)
  case "$tag" in
    90) echo "-vf transpose=1" ;;
    180) echo "-vf transpose=2,transpose=2" ;;
    270) echo "-vf transpose=2" ;;
    *) echo "" ;;
  esac
}

# Build ffmpeg command for a single input file
process_file() {
  local in_file="$1"
  local out_dir="$2"
  local seg_time="$3"
  local rotate_pref="$4"
  local reencode_pref="$5"
  local vcodec_pref="$6"
  local crf_pref="$7"
  local preset_pref="$8"
  local pattern_pref="$9"
  local start_pref="${10}"
  local end_pref="${11}"
  local threads_pref="${12}"
  local overwrite_pref="${13}"

  if [[ ! -f "$in_file" ]]; then
    echo "Skipping missing file: $in_file" >&2
    return 0
  fi

  mkdir -p "$out_dir"

  local base
  base="$(basename "${in_file}")"
  base="${base%.*}"

  local filter_flags=""
  if [[ "$rotate_pref" == "auto" ]]; then
    filter_flags="$(auto_rotation_filter "$in_file")"
  else
    filter_flags="$(rotation_filter_from_value "$rotate_pref")"
    if [[ "$filter_flags" == "INVALID" ]]; then
      echo "Error: Invalid --rotate value '$rotate_pref'. Use 0, 90, 180, 270, or auto." >&2
      return 2
    fi
  fi

  local will_reencode=false
  case "$reencode_pref" in
    always) will_reencode=true ;;
    never) will_reencode=false ;;
    auto)
      if [[ -n "$filter_flags" ]]; then
        will_reencode=true
      else
        will_reencode=false
      fi
      ;;
    *) echo "Error: --reencode must be auto|always|never" >&2; return 2 ;;
  esac

  local maps=(-map 0:v:0 -map 0:a?)
  local ss=()
  local to=()
  [[ -n "$start_pref" ]] && ss=(-ss "$start_pref")
  [[ -n "$end_pref" ]] && to=(-to "$end_pref")
  local overwrite_flag=""
  $overwrite_pref && overwrite_flag="-y" || overwrite_flag="-n"

  local codec_args=()
  if $will_reencode; then
    codec_args=(-c:v "$vcodec_pref" -crf "$crf_pref" -preset "$preset_pref" -c:a copy)
    [[ -n "$threads_pref" ]] && codec_args+=( -threads "$threads_pref" )
  else
    codec_args=(-c copy)
  fi

  local out_pattern
  if [[ -n "$pattern_pref" ]]; then
    out_pattern="$pattern_pref"
  else
    out_pattern="${base}_%03d.mp4"
  fi

  local cmd=(ffmpeg -hide_banner -loglevel info $overwrite_flag "${ss[@]}" -i "$in_file" "${to[@]}" ${maps[*]} ${filter_flags} -f segment -segment_time "$seg_time" -reset_timestamps 1 "${codec_args[@]}" "$out_dir/$out_pattern")

  echo "Processing: $in_file"
  echo "Output to: $out_dir/$out_pattern"
  echo "Command: ${cmd[*]}"
  if $dry_run; then
    return 0
  fi

  "${cmd[@]}"
}

run_single() {
  process_file "$input_file" "$output_dir" "$segment_time" "$rotate" "$reencode_mode" "$vcodec" "$crf" "$preset" "$pattern" "$start_time" "$end_time" "$threads" "$overwrite"
}

run_batch() {
  local dir="$1"
  # Find common video files; case-insensitive extensions
  # shellcheck disable=SC2038
  find "$dir" -type f \( \
    -iname '*.mp4' -o -iname '*.mov' -o -iname '*.mkv' -o -iname '*.avi' -o -iname '*.m4v' -o -iname '*.webm' \
  \) | while IFS= read -r f; do
    local rel
    rel="${f#$dir/}"
    local base
    base="${rel%.*}"
    local sub_out_dir="$output_dir/$base"
    process_file "$f" "$sub_out_dir" "$segment_time" "$rotate" "$reencode_mode" "$vcodec" "$crf" "$preset" "$pattern" "$start_time" "$end_time" "$threads" "$overwrite"
  done
}

main() {
  # Only require tools if we will run actual work (not just --help earlier)
  require_tools

  if [[ -n "$input_file" ]]; then
    run_single
  else
    run_batch "$input_dir"
  fi
}

main "$@"