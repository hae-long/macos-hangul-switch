#!/bin/bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_ROOT/tests/test_helper.bash"

FIXTURE_ROOT=""
FIXTURE_HOME=""
SUNSHINE_CONFIG=""

cleanup_fixture() {
  if [[ -n "$FIXTURE_ROOT" && -d "$FIXTURE_ROOT" ]]; then
    /bin/rm -rf "$FIXTURE_ROOT"
  fi
}

trap cleanup_fixture EXIT

new_fixture() {
  cleanup_fixture
  FIXTURE_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/macos-hangul-switch-sunshine-test.XXXXXX")"
  FIXTURE_HOME="$FIXTURE_ROOT/home"
  SUNSHINE_CONFIG="$FIXTURE_HOME/.config/sunshine/sunshine.conf"
  /bin/mkdir -p "$(dirname "$SUNSHINE_CONFIG")"
}

run_sunshine() {
  env \
    MHS_HOME="$FIXTURE_HOME" \
    MHS_SUNSHINE_CONFIG="$SUNSHINE_CONFIG" \
    /bin/bash "$PROJECT_ROOT/scripts/sunshine.bash" "$@"
}

run_sunshine_without_path_override() {
  env \
    MHS_HOME="$FIXTURE_HOME" \
    /bin/bash "$PROJECT_ROOT/scripts/sunshine.bash" "$@"
}

file_checksum() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

assert_final_newline() {
  local file="$1"
  local final_byte
  final_byte="$(/usr/bin/tail -c 1 "$file" | /usr/bin/od -An -t x1 | /usr/bin/tr -d '[:space:]')"
  assert_eq "0a" "$final_byte" "file should end with a newline"
}

test_install_appends_block_when_missing() {
  new_fixture
  printf '%s\n' 'hevc_mode = 1' 'av1_mode = 1' > "$SUNSHINE_CONFIG"

  run_sunshine install >/dev/null || return 1

  assert_file_contains "hevc_mode = 1" "$SUNSHINE_CONFIG" &&
    assert_file_contains "av1_mode = 1" "$SUNSHINE_CONFIG" &&
    assert_file_contains "  0xA5, 0x81" "$SUNSHINE_CONFIG" &&
    assert_eq "1" "$(/usr/bin/find "$(dirname "$SUNSHINE_CONFIG")" -maxdepth 1 -name 'sunshine.conf.backup-macos-hangul-switch-*' | /usr/bin/wc -l | /usr/bin/tr -d ' ')" &&
    assert_final_newline "$SUNSHINE_CONFIG"
}

test_install_merges_one_line_block() {
  new_fixture
  printf '%s\n' 'keybindings = [ 0x10, 0xA0 ]' > "$SUNSHINE_CONFIG"

  run_sunshine install >/dev/null || return 1

  assert_file_contains "  0x10, 0xA0," "$SUNSHINE_CONFIG" &&
    assert_file_contains "  0xA5, 0x81" "$SUNSHINE_CONFIG"
}

test_install_merges_multiline_block() {
  new_fixture
  printf '%s\n' \
    'hevc_mode = 1' \
    'keybindings = [' \
    '  0x10, 0xA0,' \
    '  0x11, 0xA2' \
    ']' \
    'av1_mode = 1' > "$SUNSHINE_CONFIG"

  run_sunshine install >/dev/null || return 1

  assert_file_contains "  0x10, 0xA0," "$SUNSHINE_CONFIG" &&
    assert_file_contains "  0x11, 0xA2," "$SUNSHINE_CONFIG" &&
    assert_file_contains "  0xA5, 0x81" "$SUNSHINE_CONFIG" &&
    assert_file_contains "av1_mode = 1" "$SUNSHINE_CONFIG"
}

test_existing_exact_pair_is_idempotent_and_not_owned() {
  local before

  new_fixture
  printf '%s\n' 'keybindings = [ 0xA5, 0x81 ]' > "$SUNSHINE_CONFIG"
  before="$(file_checksum "$SUNSHINE_CONFIG")"

  run_sunshine install >/dev/null || return 1
  run_sunshine uninstall >/dev/null || return 1

  assert_eq "$before" "$(file_checksum "$SUNSHINE_CONFIG")" \
    "pre-existing exact pair should not be rewritten or removed"
}

test_conflicting_pair_is_rejected_without_changes() {
  local before

  new_fixture
  printf '%s\n' 'keybindings = [ 0xA5, 0x5B ]' > "$SUNSHINE_CONFIG"
  before="$(file_checksum "$SUNSHINE_CONFIG")"

  if run_sunshine install >"$FIXTURE_ROOT/output.log" 2>&1; then
    fail "conflicting Sunshine mapping should be rejected"
    return
  fi

  assert_file_contains "conflict" "$FIXTURE_ROOT/output.log" &&
    assert_eq "$before" "$(file_checksum "$SUNSHINE_CONFIG")" \
      "conflicting configuration should remain byte-identical"
}

test_uninstall_removes_only_managed_pair() {
  new_fixture
  printf '%s\n' 'keybindings = [ 0x10, 0xA0 ]' > "$SUNSHINE_CONFIG"

  run_sunshine install >/dev/null || return 1
  run_sunshine uninstall >/dev/null || return 1

  assert_file_contains "  0x10, 0xA0" "$SUNSHINE_CONFIG" &&
    assert_file_not_contains "0xA5" "$SUNSHINE_CONFIG"
}

test_uninstall_removes_empty_managed_block() {
  new_fixture
  printf '%s\n' 'hevc_mode = 1' > "$SUNSHINE_CONFIG"

  run_sunshine install >/dev/null || return 1
  run_sunshine uninstall >/dev/null || return 1

  assert_eq "hevc_mode = 1" "$(/bin/cat "$SUNSHINE_CONFIG")"
}

test_odd_pair_count_is_rejected_without_changes() {
  local before

  new_fixture
  printf '%s\n' 'keybindings = [ 0x10, 0xA0, 0x11 ]' > "$SUNSHINE_CONFIG"
  before="$(file_checksum "$SUNSHINE_CONFIG")"

  if run_sunshine install >"$FIXTURE_ROOT/output.log" 2>&1; then
    fail "odd keybinding count should be rejected"
    return
  fi

  assert_file_contains "even" "$FIXTURE_ROOT/output.log" &&
    assert_eq "$before" "$(file_checksum "$SUNSHINE_CONFIG")"
}

test_unclosed_block_is_rejected_without_changes() {
  local before

  new_fixture
  printf '%s\n' 'keybindings = [' '  0x10, 0xA0' > "$SUNSHINE_CONFIG"
  before="$(file_checksum "$SUNSHINE_CONFIG")"

  if run_sunshine install >"$FIXTURE_ROOT/output.log" 2>&1; then
    fail "unclosed keybindings block should be rejected"
    return
  fi

  assert_file_contains "closing" "$FIXTURE_ROOT/output.log" &&
    assert_eq "$before" "$(file_checksum "$SUNSHINE_CONFIG")"
}

test_unsupported_token_is_rejected_without_changes() {
  local before

  new_fixture
  printf '%s\n' 'keybindings = [ 0x10, banana, 0xA0 ]' > "$SUNSHINE_CONFIG"
  before="$(file_checksum "$SUNSHINE_CONFIG")"

  if run_sunshine install >"$FIXTURE_ROOT/output.log" 2>&1; then
    fail "unsupported keybinding token should be rejected"
    return
  fi

  assert_file_contains "unsupported" "$FIXTURE_ROOT/output.log" &&
    assert_eq "$before" "$(file_checksum "$SUNSHINE_CONFIG")"
}

test_uninstall_uses_recorded_custom_config_path() {
  local custom_config

  new_fixture
  custom_config="$FIXTURE_HOME/custom/sunshine.conf"
  /bin/mkdir -p "$(dirname "$custom_config")"
  SUNSHINE_CONFIG="$custom_config"
  printf '%s\n' 'hevc_mode = 1' > "$SUNSHINE_CONFIG"

  run_sunshine install >/dev/null || return 1
  run_sunshine_without_path_override uninstall >/dev/null || return 1

  assert_file_not_contains "0xA5" "$custom_config" &&
    assert_file_contains "hevc_mode = 1" "$custom_config"
}

run_test "install appends a missing keybindings block" test_install_appends_block_when_missing
run_test "install merges a one-line keybindings block" test_install_merges_one_line_block
run_test "install merges a multiline keybindings block" test_install_merges_multiline_block
run_test "pre-existing exact pair is idempotent and not removed" test_existing_exact_pair_is_idempotent_and_not_owned
run_test "conflicting pair is rejected without changes" test_conflicting_pair_is_rejected_without_changes
run_test "uninstall removes only the managed pair" test_uninstall_removes_only_managed_pair
run_test "uninstall removes an empty managed block" test_uninstall_removes_empty_managed_block
run_test "odd pair count is rejected without changes" test_odd_pair_count_is_rejected_without_changes
run_test "unclosed block is rejected without changes" test_unclosed_block_is_rejected_without_changes
run_test "unsupported token is rejected without changes" test_unsupported_token_is_rejected_without_changes
run_test "uninstall uses the recorded custom config path" test_uninstall_uses_recorded_custom_config_path
finish_tests
