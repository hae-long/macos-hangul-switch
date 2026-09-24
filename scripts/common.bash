#!/bin/bash

MHS_PROJECT_ROOT="${MHS_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MHS_EFFECTIVE_HOME="${MHS_HOME:-$HOME}"
MHS_STATE_DIR="$MHS_EFFECTIVE_HOME/Library/Application Support/macos-hangul-switch"
MHS_LAUNCH_AGENT_DIR="$MHS_EFFECTIVE_HOME/Library/LaunchAgents"
MHS_LAUNCH_AGENT="$MHS_LAUNCH_AGENT_DIR/com.local.global-hangul-switch.plist"
MHS_LAUNCH_AGENT_LABEL="com.local.global-hangul-switch"
MHS_SYMBOLIC_HOTKEY_DOMAIN="com.apple.symbolichotkeys"

MHS_PLUTIL="${MHS_PLUTIL:-/usr/bin/plutil}"
MHS_DEFAULTS="${MHS_DEFAULTS:-/usr/bin/defaults}"
MHS_HIDUTIL="${MHS_HIDUTIL:-/usr/bin/hidutil}"
MHS_LAUNCHCTL="${MHS_LAUNCHCTL:-/bin/launchctl}"
MHS_KILLALL="${MHS_KILLALL:-/usr/bin/killall}"
MHS_ID="${MHS_ID:-/usr/bin/id}"
MHS_UNAME="${MHS_UNAME:-/usr/bin/uname}"

MHS_HID_LANG1=30064771216
MHS_HID_RIGHT_ALT=30064771302
MHS_HID_RIGHT_COMMAND=30064771303
MHS_HID_F18=30064771181

mhs_info() {
  printf 'info: %s\n' "$*"
}

mhs_warn() {
  printf 'warning: %s\n' "$*" >&2
}

mhs_die() {
  printf 'error: %s\n' "$*" >&2
  return 1
}

mhs_require_macos() {
  if [[ "$("$MHS_UNAME" -s)" != "Darwin" ]]; then
    mhs_die "macOS is required"
    return 1
  fi
}

mhs_make_temp_dir() {
  /usr/bin/mktemp -d "${TMPDIR:-/tmp}/macos-hangul-switch.XXXXXX"
}

mhs_gui_domain() {
  printf 'gui/%s\n' "$("$MHS_ID" -u)"
}

mhs_ensure_shortcut_container() {
  local plist="$1"
  local value_type

  if ! value_type="$("$MHS_PLUTIL" -type AppleSymbolicHotKeys "$plist" 2>/dev/null)"; then
    "$MHS_PLUTIL" -insert AppleSymbolicHotKeys -dictionary "$plist"
    return
  fi

  if [[ "$value_type" != "dictionary" ]]; then
    mhs_die "AppleSymbolicHotKeys is not a dictionary"
    return 1
  fi
}

mhs_export_symbolic_hotkeys() {
  local destination="$1"

  if [[ -n "${MHS_SYMBOLIC_HOTKEYS_PLIST:-}" ]]; then
    if [[ -f "$MHS_SYMBOLIC_HOTKEYS_PLIST" ]]; then
      /bin/cp "$MHS_SYMBOLIC_HOTKEYS_PLIST" "$destination"
    else
      "$MHS_PLUTIL" -create xml1 "$destination"
    fi
    return
  fi

  if ! "$MHS_DEFAULTS" export "$MHS_SYMBOLIC_HOTKEY_DOMAIN" "$destination" >/dev/null 2>&1; then
    "$MHS_PLUTIL" -create xml1 "$destination"
  fi
}

mhs_import_symbolic_hotkeys() {
  local source="$1"

  if [[ -n "${MHS_SYMBOLIC_HOTKEYS_PLIST:-}" ]]; then
    /bin/cp "$source" "$MHS_SYMBOLIC_HOTKEYS_PLIST"
    return
  fi

  "$MHS_DEFAULTS" import "$MHS_SYMBOLIC_HOTKEY_DOMAIN" "$source" >/dev/null
  "$MHS_KILLALL" cfprefsd >/dev/null 2>&1 || true
  "$MHS_KILLALL" SystemUIServer >/dev/null 2>&1 || true
}

mhs_configure_f18_shortcut() {
  local temp_dir="$1"
  local plist="$temp_dir/symbolic-hotkeys.plist"
  local hotkey_json

  hotkey_json='{"enabled":true,"value":{"type":"standard","parameters":[65535,79,8388608]}}'

  mhs_export_symbolic_hotkeys "$plist"
  mhs_ensure_shortcut_container "$plist"

  if "$MHS_PLUTIL" -extract AppleSymbolicHotKeys.60 raw -o /dev/null "$plist" >/dev/null 2>&1; then
    "$MHS_PLUTIL" -replace AppleSymbolicHotKeys.60 -json "$hotkey_json" "$plist"
  else
    "$MHS_PLUTIL" -insert AppleSymbolicHotKeys.60 -json "$hotkey_json" "$plist"
  fi

  mhs_import_symbolic_hotkeys "$plist"
}

mhs_hotkey_is_f18() {
  local temp_dir="$1"
  local plist="$temp_dir/current-symbolic-hotkeys.plist"

  mhs_export_symbolic_hotkeys "$plist"

  [[ "$("$MHS_PLUTIL" -extract AppleSymbolicHotKeys.60.enabled raw -o - "$plist" 2>/dev/null)" == "true" ]] &&
    [[ "$("$MHS_PLUTIL" -extract AppleSymbolicHotKeys.60.value.type raw -o - "$plist" 2>/dev/null)" == "standard" ]] &&
    [[ "$("$MHS_PLUTIL" -extract AppleSymbolicHotKeys.60.value.parameters.0 raw -o - "$plist" 2>/dev/null)" == "65535" ]] &&
    [[ "$("$MHS_PLUTIL" -extract AppleSymbolicHotKeys.60.value.parameters.1 raw -o - "$plist" 2>/dev/null)" == "79" ]] &&
    [[ "$("$MHS_PLUTIL" -extract AppleSymbolicHotKeys.60.value.parameters.2 raw -o - "$plist" 2>/dev/null)" == "8388608" ]]
}

mhs_restore_hotkey() {
  local temp_dir="$1"
  local plist="$temp_dir/restore-symbolic-hotkeys.plist"
  local backup="$MHS_STATE_DIR/hotkey-60.before.plist"
  local missing_marker="$MHS_STATE_DIR/hotkey-60.was-missing"
  local xml_value

  if ! mhs_hotkey_is_f18 "$temp_dir"; then
    mhs_warn "symbolic hotkey 60 changed after installation; leaving it untouched"
    return
  fi

  mhs_export_symbolic_hotkeys "$plist"
  mhs_ensure_shortcut_container "$plist"

  if [[ -f "$backup" ]]; then
    xml_value="$("$MHS_PLUTIL" -convert xml1 -o - "$backup")"
    if "$MHS_PLUTIL" -extract AppleSymbolicHotKeys.60 raw -o /dev/null "$plist" >/dev/null 2>&1; then
      "$MHS_PLUTIL" -replace AppleSymbolicHotKeys.60 -xml "$xml_value" "$plist"
    else
      "$MHS_PLUTIL" -insert AppleSymbolicHotKeys.60 -xml "$xml_value" "$plist"
    fi
  elif [[ -f "$missing_marker" ]]; then
    "$MHS_PLUTIL" -remove AppleSymbolicHotKeys.60 "$plist" 2>/dev/null || true
  else
    mhs_warn "no symbolic hotkey backup was found"
    return
  fi

  mhs_import_symbolic_hotkeys "$plist"
}

mhs_capture_hid_mapping() {
  local destination="$1"
  local temp_dir="$2"
  local raw_file="$temp_dir/hid-current.txt"
  local current_plist="$temp_dir/hid-current.plist"
  local index=0
  local source
  local destination_usage

  "$MHS_PLUTIL" -create xml1 "$destination"
  "$MHS_PLUTIL" -insert UserKeyMapping -array "$destination"

  "$MHS_HIDUTIL" property --get UserKeyMapping > "$raw_file"
  if /usr/bin/grep -Eq '^[[:space:]]*\(null\)[[:space:]]*$' "$raw_file"; then
    return
  fi

  if ! "$MHS_PLUTIL" -convert xml1 -o "$current_plist" "$raw_file" 2>/dev/null; then
    mhs_die "could not parse the current hidutil UserKeyMapping"
    return 1
  fi

  while source="$("$MHS_PLUTIL" -extract "$index.HIDKeyboardModifierMappingSrc" raw -o - "$current_plist" 2>/dev/null)"; do
    destination_usage="$("$MHS_PLUTIL" -extract "$index.HIDKeyboardModifierMappingDst" raw -o - "$current_plist")"
    if [[ ! "$source" =~ ^[0-9]+$ || ! "$destination_usage" =~ ^[0-9]+$ ]]; then
      mhs_die "current hidutil mapping contains a non-numeric usage"
      return 1
    fi

    "$MHS_PLUTIL" -insert "UserKeyMapping.$index" -json \
      "{\"HIDKeyboardModifierMappingSrc\":$source,\"HIDKeyboardModifierMappingDst\":$destination_usage}" \
      "$destination"
    index=$((index + 1))
  done
}

mhs_append_hid_mapping() {
  local plist="$1"
  local source_to_add="$2"
  local destination_to_add="$3"
  local key_name="$4"
  local index=0
  local source
  local destination_usage

  while source="$("$MHS_PLUTIL" -extract "UserKeyMapping.$index.HIDKeyboardModifierMappingSrc" raw -o - "$plist" 2>/dev/null)"; do
    destination_usage="$("$MHS_PLUTIL" -extract "UserKeyMapping.$index.HIDKeyboardModifierMappingDst" raw -o - "$plist")"
    if [[ "$source" == "$source_to_add" ]]; then
      if [[ "$destination_usage" != "$destination_to_add" ]]; then
        mhs_die "HID mapping conflict for $key_name: existing destination is $destination_usage"
        return 1
      fi
      return
    fi
    index=$((index + 1))
  done

  "$MHS_PLUTIL" -insert "UserKeyMapping.$index" -json \
    "{\"HIDKeyboardModifierMappingSrc\":$source_to_add,\"HIDKeyboardModifierMappingDst\":$destination_to_add}" \
    "$plist"
}

mhs_mapping_json() {
  local plist="$1"
  "$MHS_PLUTIL" -convert json -o - "$plist"
}

mhs_plists_equal() {
  local first="$1"
  local second="$2"
  local temp_dir="$3"
  local first_binary="$temp_dir/first.binary.plist"
  local second_binary="$temp_dir/second.binary.plist"

  /bin/cp "$first" "$first_binary"
  /bin/cp "$second" "$second_binary"
  "$MHS_PLUTIL" -convert binary1 "$first_binary"
  "$MHS_PLUTIL" -convert binary1 "$second_binary"
  /usr/bin/cmp -s "$first_binary" "$second_binary"
}

mhs_backup_initial_state() {
  local current_hid_plist="$1"
  local temp_dir="$2"
  local shortcuts="$temp_dir/shortcuts-before.plist"
  local existing_label
  local gui_domain

  if [[ -f "$MHS_STATE_DIR/install-state-version" ]]; then
    return
  fi

  /bin/mkdir -p "$MHS_STATE_DIR"
  /bin/chmod 700 "$MHS_STATE_DIR"

  if [[ -f "$MHS_LAUNCH_AGENT" ]]; then
    /bin/cp -p "$MHS_LAUNCH_AGENT" "$MHS_STATE_DIR/launch-agent.before.plist"
    if existing_label="$("$MHS_PLUTIL" -extract Label raw -o - "$MHS_LAUNCH_AGENT" 2>/dev/null)"; then
      printf '%s\n' "$existing_label" > "$MHS_STATE_DIR/launch-agent.before-label"
      gui_domain="$(mhs_gui_domain)"
      if "$MHS_LAUNCHCTL" print "$gui_domain/$existing_label" >/dev/null 2>&1; then
        : > "$MHS_STATE_DIR/launch-agent.was-loaded"
        : > "$MHS_STATE_DIR/launch-agent.needs-first-bootout"
      fi
    fi
  else
    : > "$MHS_STATE_DIR/launch-agent.was-missing"
  fi

  /bin/cp "$current_hid_plist" "$MHS_STATE_DIR/hid-before.plist"

  mhs_export_symbolic_hotkeys "$shortcuts"
  if "$MHS_PLUTIL" -extract AppleSymbolicHotKeys.60 xml1 \
    -o "$MHS_STATE_DIR/hotkey-60.before.plist" "$shortcuts" 2>/dev/null; then
    :
  else
    : > "$MHS_STATE_DIR/hotkey-60.was-missing"
  fi

  printf '%s\n' "1" > "$MHS_STATE_DIR/install-state-version"
}

mhs_bootout_previous_launch_agent() {
  local label_file="$MHS_STATE_DIR/launch-agent.before-label"
  local bootout_marker="$MHS_STATE_DIR/launch-agent.needs-first-bootout"
  local existing_label
  local gui_domain

  if [[ ! -f "$bootout_marker" || ! -f "$label_file" ]]; then
    return
  fi

  existing_label="$(/usr/bin/head -n 1 "$label_file")"
  gui_domain="$(mhs_gui_domain)"
  "$MHS_LAUNCHCTL" bootout "$gui_domain/$existing_label"
  /bin/rm -f "$bootout_marker"
}

mhs_generate_launch_agent() {
  local mapping_json="$1"
  local destination="$2"
  local template="$MHS_PROJECT_ROOT/assets/com.local.global-hangul-switch.plist.in"
  local escaped_mapping

  if [[ ! -f "$template" ]]; then
    mhs_die "LaunchAgent template is missing: $template"
    return 1
  fi

  escaped_mapping="${mapping_json//&/\\&}"
  /usr/bin/sed "s|__MHS_KEY_MAPPING__|$escaped_mapping|" "$template" > "$destination"
  "$MHS_PLUTIL" -lint "$destination" >/dev/null
  /bin/chmod 644 "$destination"
}

mhs_apply_launch_agent() {
  local mapping_json="$1"
  local gui_domain

  "$MHS_HIDUTIL" property --set "$mapping_json" >/dev/null
  gui_domain="$(mhs_gui_domain)"
  "$MHS_LAUNCHCTL" bootout "$gui_domain" "$MHS_LAUNCH_AGENT" >/dev/null 2>&1 || true
  "$MHS_LAUNCHCTL" bootstrap "$gui_domain" "$MHS_LAUNCH_AGENT"
}

mhs_bootout_managed_launch_agent() {
  local gui_domain
  gui_domain="$(mhs_gui_domain)"
  "$MHS_LAUNCHCTL" bootout "$gui_domain" "$MHS_LAUNCH_AGENT" >/dev/null 2>&1 || true
}

mhs_restore_hid_mapping() {
  local temp_dir="$1"
  local current="$temp_dir/hid-at-uninstall.plist"
  local installed="$MHS_STATE_DIR/hid-installed.plist"
  local before="$MHS_STATE_DIR/hid-before.plist"
  local before_json

  if [[ ! -f "$installed" || ! -f "$before" ]]; then
    mhs_warn "no complete HID mapping backup was found"
    return
  fi

  mhs_capture_hid_mapping "$current" "$temp_dir"
  if ! mhs_plists_equal "$current" "$installed" "$temp_dir"; then
    mhs_warn "live HID mapping changed after installation; leaving it untouched"
    return
  fi

  before_json="$(mhs_mapping_json "$before")"
  "$MHS_HIDUTIL" property --set "$before_json" >/dev/null
}

mhs_restore_launch_agent() {
  local gui_domain

  if [[ -f "$MHS_STATE_DIR/launch-agent.before.plist" ]]; then
    /bin/cp -p "$MHS_STATE_DIR/launch-agent.before.plist" "$MHS_LAUNCH_AGENT"
    if [[ -f "$MHS_STATE_DIR/launch-agent.was-loaded" ]]; then
      gui_domain="$(mhs_gui_domain)"
      "$MHS_LAUNCHCTL" bootstrap "$gui_domain" "$MHS_LAUNCH_AGENT"
    fi
  elif [[ -f "$MHS_STATE_DIR/launch-agent.was-missing" ]]; then
    /bin/rm -f "$MHS_LAUNCH_AGENT"
  else
    mhs_warn "no LaunchAgent backup was found"
  fi
}

mhs_archive_state() {
  local archived

  if [[ ! -d "$MHS_STATE_DIR" ]]; then
    return
  fi

  archived="$MHS_STATE_DIR.uninstalled-$(/bin/date +%Y%m%d-%H%M%S)-$$"
  /bin/mv "$MHS_STATE_DIR" "$archived"
  mhs_info "recovery state kept at $archived"
}
