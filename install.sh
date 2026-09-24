#!/bin/bash
set -euo pipefail

MHS_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MHS_PROJECT_ROOT/scripts/common.bash"

include_right_command=0
configure_sunshine=0
include_right_alt=1

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --lang1-only     Map only the dedicated LANG1 key.
  --right-command  Also map Right Command to F18.
  --sunshine       Add the Moonlight/Sunshine 0xA5 -> 0x81 mapping.
  -h, --help       Show this help.

Sunshine is never restarted automatically.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --right-command)
      include_right_command=1
      ;;
    --lang1-only)
      include_right_alt=0
      ;;
    --sunshine)
      configure_sunshine=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      mhs_die "unknown option: $1"
      exit 64
      ;;
  esac
  shift
done

mhs_require_macos

if [[ "$configure_sunshine" == "1" ]]; then
  "$MHS_PROJECT_ROOT/scripts/sunshine.bash" validate-install
fi

temp_dir="$(mhs_make_temp_dir)"
trap '/bin/rm -rf "$temp_dir"' EXIT

current_mapping="$temp_dir/hid-before.plist"
merged_mapping="$temp_dir/hid-installed.plist"
generated_launch_agent="$temp_dir/com.local.global-hangul-switch.plist"

mhs_capture_hid_mapping "$current_mapping" "$temp_dir"
/bin/cp "$current_mapping" "$merged_mapping"
mhs_append_hid_mapping "$merged_mapping" "$MHS_HID_LANG1" "$MHS_HID_F18" "LANG1"
if [[ "$include_right_alt" == "1" ]]; then
  mhs_append_hid_mapping "$merged_mapping" "$MHS_HID_RIGHT_ALT" "$MHS_HID_F18" "Right Alt"
fi
if [[ "$include_right_command" == "1" ]]; then
  mhs_append_hid_mapping "$merged_mapping" "$MHS_HID_RIGHT_COMMAND" "$MHS_HID_F18" "Right Command"
fi

mapping_json="$(mhs_mapping_json "$merged_mapping")"
mhs_generate_launch_agent "$mapping_json" "$generated_launch_agent"
mhs_backup_initial_state "$current_mapping" "$temp_dir"
mhs_configure_f18_shortcut "$temp_dir"
mhs_bootout_previous_launch_agent

/bin/mkdir -p "$MHS_LAUNCH_AGENT_DIR"
/bin/cp "$generated_launch_agent" "$MHS_LAUNCH_AGENT"
/bin/cp "$merged_mapping" "$MHS_STATE_DIR/hid-installed.plist"
if [[ "$include_right_alt" == "1" ]]; then
  : > "$MHS_STATE_DIR/include-right-alt"
else
  /bin/rm -f "$MHS_STATE_DIR/include-right-alt"
fi
if [[ "$include_right_command" == "1" ]]; then
  : > "$MHS_STATE_DIR/include-right-command"
else
  /bin/rm -f "$MHS_STATE_DIR/include-right-command"
fi
mhs_apply_launch_agent "$mapping_json"

if [[ "$configure_sunshine" == "1" ]]; then
  "$MHS_PROJECT_ROOT/scripts/sunshine.bash" install
fi

mhs_info "installed physical Han/Yeong switching for LANG1"
if [[ "$include_right_alt" == "1" ]]; then
  mhs_info "Right Alt is also mapped to Han/Yeong"
fi
if [[ "$include_right_command" == "1" ]]; then
  mhs_info "Right Command is also mapped to Han/Yeong"
fi
if [[ "$configure_sunshine" == "1" ]]; then
  mhs_info "Sunshine configuration updated; restart Sunshine manually when it is safe to disconnect Moonlight"
fi
