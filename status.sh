#!/bin/bash
set -u

MHS_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MHS_PROJECT_ROOT/scripts/common.bash"

overall_status=0
temp_dir="$(mhs_make_temp_dir)"
trap '/bin/rm -rf "$temp_dir"' EXIT

if [[ -f "$MHS_LAUNCH_AGENT" ]]; then
  printf '%-24s %s\n' "LaunchAgent" "installed"
else
  printf '%-24s %s\n' "LaunchAgent" "not installed"
  overall_status=1
fi

if mhs_hotkey_is_f18 "$temp_dir"; then
  printf '%-24s %s\n' "F18 input shortcut" "configured"
else
  printf '%-24s %s\n' "F18 input shortcut" "not configured"
  overall_status=1
fi

current_mapping="$temp_dir/current-hid.plist"
if mhs_capture_hid_mapping "$current_mapping" "$temp_dir"; then
  required_mappings=("$MHS_HID_LANG1:LANG1")
  if [[ -f "$MHS_STATE_DIR/include-right-alt" ]]; then
    required_mappings[${#required_mappings[@]}]="$MHS_HID_RIGHT_ALT:Right Alt"
  else
    printf '%-24s %s\n' "Right Alt -> F18" "not selected"
  fi
  if [[ -f "$MHS_STATE_DIR/include-right-command" ]]; then
    required_mappings[${#required_mappings[@]}]="$MHS_HID_RIGHT_COMMAND:Right Command"
  else
    printf '%-24s %s\n' "Right Command -> F18" "not selected"
  fi

  for mapping_spec in "${required_mappings[@]}"; do
    source_usage="${mapping_spec%%:*}"
    key_name="${mapping_spec#*:}"
    index=0
    found=0
    while source="$("$MHS_PLUTIL" -extract "UserKeyMapping.$index.HIDKeyboardModifierMappingSrc" raw -o - "$current_mapping" 2>/dev/null)"; do
      destination="$("$MHS_PLUTIL" -extract "UserKeyMapping.$index.HIDKeyboardModifierMappingDst" raw -o - "$current_mapping")"
      if [[ "$source" == "$source_usage" && "$destination" == "$MHS_HID_F18" ]]; then
        found=1
        break
      fi
      index=$((index + 1))
    done

    if [[ "$found" == "1" ]]; then
      printf '%-24s %s\n' "$key_name -> F18" "active"
    else
      printf '%-24s %s\n' "$key_name -> F18" "not active"
      overall_status=1
    fi
  done
else
  printf '%-24s %s\n' "Live HID mapping" "unavailable"
  overall_status=1
fi

if [[ -x "$MHS_PROJECT_ROOT/scripts/sunshine.bash" ]]; then
  "$MHS_PROJECT_ROOT/scripts/sunshine.bash" status || true
else
  printf '%-24s %s\n' "Sunshine 0xA5 -> 0x81" "helper unavailable"
fi

exit "$overall_status"
