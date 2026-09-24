#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_ROOT/tests/test_helper.bash"

FIXTURE_ROOT=""
FIXTURE_HOME=""
SHORTCUTS_PLIST=""
HID_STATE=""
FAKE_HIDUTIL=""
FAKE_LAUNCHCTL=""

cleanup_fixture() {
  if [[ -n "$FIXTURE_ROOT" && -d "$FIXTURE_ROOT" ]]; then
    /bin/rm -rf "$FIXTURE_ROOT"
  fi
}

trap cleanup_fixture EXIT

new_fixture() {
  cleanup_fixture
  FIXTURE_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/macos-hangul-switch-test.XXXXXX")"
  FIXTURE_HOME="$FIXTURE_ROOT/home"
  SHORTCUTS_PLIST="$FIXTURE_ROOT/symbolic-hotkeys.plist"
  HID_STATE="$FIXTURE_ROOT/hid-state.json"
  FAKE_HIDUTIL="$FIXTURE_ROOT/hidutil"
  FAKE_LAUNCHCTL="$FIXTURE_ROOT/launchctl"

  /bin/mkdir -p \
    "$FIXTURE_HOME/Library/LaunchAgents" \
    "$FIXTURE_HOME/Library/Application Support" \
    "$FIXTURE_HOME/.config/sunshine"

  /usr/bin/plutil -create xml1 "$SHORTCUTS_PLIST"
  /usr/bin/plutil -insert AppleSymbolicHotKeys -dictionary "$SHORTCUTS_PLIST"
  /usr/bin/plutil -insert AppleSymbolicHotKeys.60 -json \
    '{"enabled":false,"value":{"type":"standard","parameters":[1,2,3]}}' \
    "$SHORTCUTS_PLIST"

  printf '%s\n' '(null)' > "$HID_STATE"

  printf '%s\n' \
    '#!/bin/bash' \
    'set -e' \
    'if [[ "$1 $2 $3" == "property --get UserKeyMapping" ]]; then' \
    '  /bin/cat "$MHS_FAKE_HID_STATE"' \
    '  exit 0' \
    'fi' \
    'if [[ "$1 $2" == "property --set" ]]; then' \
    '  printf "%s\n" "$3" > "$MHS_FAKE_HID_LAST_SET"' \
    '  printf "%s\n" "$3" | /usr/bin/plutil -extract UserKeyMapping json -o "$MHS_FAKE_HID_STATE.next" -' \
    '  /bin/mv "$MHS_FAKE_HID_STATE.next" "$MHS_FAKE_HID_STATE"' \
    '  exit 0' \
    'fi' \
    'printf "unexpected hidutil arguments: %s\n" "$*" >&2' \
    'exit 64' > "$FAKE_HIDUTIL"
  /bin/chmod +x "$FAKE_HIDUTIL"

  printf '%s\n' \
    '#!/bin/bash' \
    'printf "%s\n" "$*" >> "$MHS_FAKE_LAUNCHCTL_LOG"' \
    'if [[ "$1" == "print" ]]; then' \
    '  exit "${MHS_FAKE_LAUNCHCTL_PRINT_STATUS:-0}"' \
    'fi' \
    'exit 0' > "$FAKE_LAUNCHCTL"
  /bin/chmod +x "$FAKE_LAUNCHCTL"
}

run_project_script() {
  local script="$1"
  shift

  env \
    MHS_HOME="$FIXTURE_HOME" \
    MHS_SYMBOLIC_HOTKEYS_PLIST="$SHORTCUTS_PLIST" \
    MHS_HIDUTIL="$FAKE_HIDUTIL" \
    MHS_LAUNCHCTL="$FAKE_LAUNCHCTL" \
    MHS_KILLALL=/usr/bin/true \
    MHS_FAKE_HID_STATE="$HID_STATE" \
    MHS_FAKE_HID_LAST_SET="$FIXTURE_ROOT/hid-last-set.json" \
    MHS_FAKE_LAUNCHCTL_LOG="$FIXTURE_ROOT/launchctl.log" \
    MHS_FAKE_LAUNCHCTL_PRINT_STATUS="${MHS_FAKE_LAUNCHCTL_PRINT_STATUS:-0}" \
    /bin/bash "$PROJECT_ROOT/$script" "$@"
}

mapping_destination() {
  local mapping_file="$1"
  local wanted_source="$2"
  local index=0
  local source
  local destination

  while source="$(/usr/bin/plutil -extract "$index.HIDKeyboardModifierMappingSrc" raw -o - "$mapping_file" 2>/dev/null)"; do
    destination="$(/usr/bin/plutil -extract "$index.HIDKeyboardModifierMappingDst" raw -o - "$mapping_file")"
    if [[ "$source" == "$wanted_source" ]]; then
      printf '%s\n' "$destination"
      return 0
    fi
    index=$((index + 1))
  done

  return 1
}

launch_agent_mapping_file() {
  local launch_agent="$FIXTURE_HOME/Library/LaunchAgents/com.local.global-hangul-switch.plist"
  local mapping_json

  mapping_json="$(/usr/bin/plutil -extract ProgramArguments.3 raw -o - "$launch_agent")"
  printf '%s\n' "$mapping_json" | /usr/bin/plutil -extract UserKeyMapping xml1 \
    -o "$FIXTURE_ROOT/launch-agent-mapping.plist" -
  printf '%s\n' "$FIXTURE_ROOT/launch-agent-mapping.plist"
}

test_fresh_install_configures_default_keys_and_f18() {
  local mapping_file

  new_fixture
  printf '%s\n' \
    '[{"HIDKeyboardModifierMappingSrc":30064771076,"HIDKeyboardModifierMappingDst":30064771077}]' \
    > "$HID_STATE"

  run_project_script install.sh >/dev/null || return 1
  mapping_file="$(launch_agent_mapping_file)"

  assert_eq "30064771181" "$(mapping_destination "$mapping_file" 30064771216)" \
    "LANG1 should map to F18" &&
    assert_eq "30064771181" "$(mapping_destination "$mapping_file" 30064771302)" \
      "Right Alt should map to F18" &&
    ! mapping_destination "$mapping_file" 30064771303 >/dev/null &&
    assert_eq "30064771077" "$(mapping_destination "$mapping_file" 30064771076)" \
      "unrelated existing mapping should survive" &&
    assert_eq "true" "$(/usr/bin/plutil -extract AppleSymbolicHotKeys.60.enabled raw -o - "$SHORTCUTS_PLIST")" &&
    assert_eq "65535" "$(/usr/bin/plutil -extract AppleSymbolicHotKeys.60.value.parameters.0 raw -o - "$SHORTCUTS_PLIST")" &&
    assert_eq "79" "$(/usr/bin/plutil -extract AppleSymbolicHotKeys.60.value.parameters.1 raw -o - "$SHORTCUTS_PLIST")" &&
    assert_eq "8388608" "$(/usr/bin/plutil -extract AppleSymbolicHotKeys.60.value.parameters.2 raw -o - "$SHORTCUTS_PLIST")" &&
    assert_eq "10" "$(/usr/bin/plutil -extract StartInterval raw -o - "$FIXTURE_HOME/Library/LaunchAgents/com.local.global-hangul-switch.plist")" &&
    assert_eq "true" "$(/usr/bin/plutil -extract RunAtLoad raw -o - "$FIXTURE_HOME/Library/LaunchAgents/com.local.global-hangul-switch.plist")"
}

test_right_command_is_opt_in() {
  local mapping_file

  new_fixture
  run_project_script install.sh --right-command >/dev/null || return 1
  mapping_file="$(launch_agent_mapping_file)"
  run_project_script status.sh > "$FIXTURE_ROOT/status.log" || return 1

  assert_eq "30064771181" "$(mapping_destination "$mapping_file" 30064771303)" \
    "Right Command should map to F18 when requested" &&
    assert_file_contains "Right Command -> F18" "$FIXTURE_ROOT/status.log" &&
    assert_file_contains "active" "$FIXTURE_ROOT/status.log"
}

test_lang1_only_leaves_right_alt_unmapped() {
  local mapping_file

  new_fixture
  run_project_script install.sh --lang1-only >/dev/null || return 1
  mapping_file="$(launch_agent_mapping_file)"
  run_project_script status.sh > "$FIXTURE_ROOT/status.log" || return 1

  assert_eq "30064771181" "$(mapping_destination "$mapping_file" 30064771216)" \
    "LANG1 should remain mapped" &&
    ! mapping_destination "$mapping_file" 30064771302 >/dev/null
}

test_conflicting_existing_hid_mapping_is_rejected_without_changes() {
  local before

  new_fixture
  printf '%s\n' \
    '[{"HIDKeyboardModifierMappingSrc":30064771302,"HIDKeyboardModifierMappingDst":30064771076}]' \
    > "$HID_STATE"
  before="$(/usr/bin/shasum -a 256 "$HID_STATE" | /usr/bin/awk '{print $1}')"

  if run_project_script install.sh >"$FIXTURE_ROOT/output.log" 2>&1; then
    fail "install should reject a conflicting Right Alt mapping"
    return
  fi

  assert_file_contains "conflict" "$FIXTURE_ROOT/output.log" &&
    assert_eq "$before" "$(/usr/bin/shasum -a 256 "$HID_STATE" | /usr/bin/awk '{print $1}')" \
    "HID state should remain byte-identical" &&
    [[ ! -e "$FIXTURE_HOME/Library/LaunchAgents/com.local.global-hangul-switch.plist" ]]
}

test_repeat_install_preserves_first_run_backups() {
  local backup
  local first_checksum

  new_fixture
  run_project_script install.sh >/dev/null || return 1
  backup="$FIXTURE_HOME/Library/Application Support/macos-hangul-switch/hotkey-60.before.plist"
  [[ -f "$backup" ]] || return 1
  first_checksum="$(/usr/bin/shasum -a 256 "$backup" | /usr/bin/awk '{print $1}')"

  /usr/bin/plutil -replace AppleSymbolicHotKeys.60.enabled -bool true "$SHORTCUTS_PLIST"
  run_project_script install.sh >/dev/null || return 1

  assert_eq "$first_checksum" "$(/usr/bin/shasum -a 256 "$backup" | /usr/bin/awk '{print $1}')" \
    "repeat install must not overwrite the original hotkey backup"
}

test_uninstall_restores_previous_state() {
  local launch_agent
  local original_launch_agent
  local restored_destination

  new_fixture
  launch_agent="$FIXTURE_HOME/Library/LaunchAgents/com.local.global-hangul-switch.plist"
  original_launch_agent="$FIXTURE_ROOT/original-launch-agent.plist"
  printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0"><dict><key>Label</key><string>com.example.previous</string></dict></plist>' \
    > "$launch_agent"
  /bin/cp "$launch_agent" "$original_launch_agent"
  printf '%s\n' \
    '[{"HIDKeyboardModifierMappingSrc":30064771076,"HIDKeyboardModifierMappingDst":30064771077}]' \
    > "$HID_STATE"

  run_project_script install.sh >/dev/null || return 1
  run_project_script uninstall.sh --keep-sunshine >/dev/null || return 1

  restored_destination="$(
    printf '%s\n' "$(/bin/cat "$HID_STATE")" |
      /usr/bin/plutil -extract 0.HIDKeyboardModifierMappingDst raw -o - -
  )"

  /usr/bin/cmp -s "$launch_agent" "$original_launch_agent" &&
    assert_eq "false" "$(/usr/bin/plutil -extract AppleSymbolicHotKeys.60.enabled raw -o - "$SHORTCUTS_PLIST")" &&
    assert_eq "1" "$(/usr/bin/plutil -extract AppleSymbolicHotKeys.60.value.parameters.0 raw -o - "$SHORTCUTS_PLIST")" &&
    assert_eq "2" "$(/usr/bin/plutil -extract AppleSymbolicHotKeys.60.value.parameters.1 raw -o - "$SHORTCUTS_PLIST")" &&
    assert_eq "3" "$(/usr/bin/plutil -extract AppleSymbolicHotKeys.60.value.parameters.2 raw -o - "$SHORTCUTS_PLIST")" &&
    assert_eq "30064771077" "$restored_destination"
}

test_status_succeeds_when_optional_sunshine_is_not_configured() {
  new_fixture
  run_project_script install.sh >/dev/null || return 1

  run_project_script status.sh > "$FIXTURE_ROOT/status.log" || return 1

  assert_file_contains "LaunchAgent" "$FIXTURE_ROOT/status.log" &&
    assert_file_contains "installed" "$FIXTURE_ROOT/status.log" &&
    assert_file_contains "Sunshine 0xA5 -> 0x81" "$FIXTURE_ROOT/status.log"
}

test_sunshine_option_integrates_without_restarting_service() {
  local sunshine_config="$FIXTURE_HOME/.config/sunshine/sunshine.conf"

  new_fixture
  sunshine_config="$FIXTURE_HOME/.config/sunshine/sunshine.conf"
  printf '%s\n' 'hevc_mode = 1' > "$sunshine_config"

  run_project_script install.sh --sunshine >/dev/null || return 1

  assert_file_contains "0xA5, 0x81" "$sunshine_config" &&
    assert_file_not_contains "sunshine" "$FIXTURE_ROOT/launchctl.log"
}

test_uninstall_does_not_start_previously_unloaded_launch_agent() {
  local launch_agent
  local bootstrap_count

  new_fixture
  launch_agent="$FIXTURE_HOME/Library/LaunchAgents/com.local.global-hangul-switch.plist"
  printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0"><dict><key>Label</key><string>com.example.unloaded</string></dict></plist>' \
    > "$launch_agent"

  MHS_FAKE_LAUNCHCTL_PRINT_STATUS=1 run_project_script install.sh >/dev/null || return 1
  MHS_FAKE_LAUNCHCTL_PRINT_STATUS=1 run_project_script uninstall.sh --keep-sunshine >/dev/null || return 1
  bootstrap_count="$(/usr/bin/grep -c '^bootstrap ' "$FIXTURE_ROOT/launchctl.log")"

  assert_eq "1" "$bootstrap_count" \
    "only the managed LaunchAgent should have been bootstrapped"
}

test_install_stops_a_loaded_previous_launch_agent_by_label() {
  local launch_agent
  local previous_bootout_count

  new_fixture
  launch_agent="$FIXTURE_HOME/Library/LaunchAgents/com.local.global-hangul-switch.plist"
  printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0"><dict><key>Label</key><string>com.example.loaded</string></dict></plist>' \
    > "$launch_agent"

  run_project_script install.sh >/dev/null || return 1
  run_project_script install.sh >/dev/null || return 1
  previous_bootout_count="$(
    /usr/bin/grep -c "^bootout gui/$(/usr/bin/id -u)/com.example.loaded$" \
      "$FIXTURE_ROOT/launchctl.log"
  )"

  assert_eq "1" "$previous_bootout_count" \
    "the pre-install LaunchAgent should be stopped only on the first install"
}

run_test "fresh install preserves mappings and configures F18" test_fresh_install_configures_default_keys_and_f18
run_test "Right Command mapping is opt-in" test_right_command_is_opt_in
run_test "LANG1-only profile leaves Right Alt unmapped" test_lang1_only_leaves_right_alt_unmapped
run_test "conflicting HID mapping is rejected without changes" test_conflicting_existing_hid_mapping_is_rejected_without_changes
run_test "repeat install preserves first-run backups" test_repeat_install_preserves_first_run_backups
run_test "uninstall restores previous state" test_uninstall_restores_previous_state
run_test "status accepts missing optional Sunshine setup" test_status_succeeds_when_optional_sunshine_is_not_configured
run_test "Sunshine option integrates without restarting it" test_sunshine_option_integrates_without_restarting_service
run_test "uninstall preserves a previously unloaded LaunchAgent state" test_uninstall_does_not_start_previously_unloaded_launch_agent
run_test "install stops a loaded previous LaunchAgent by label" test_install_stops_a_loaded_previous_launch_agent_by_label
finish_tests
