#!/bin/bash

TESTS_RUN=0
TESTS_FAILED=0

fail() {
  printf '%s\n' "$*" >&2
  return 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="${3:-values differ}"

  if [[ "$expected" != "$actual" ]]; then
    fail "$message: expected [$expected], got [$actual]"
  fi
}

assert_file_contains() {
  local needle="$1"
  local file="$2"

  if ! /usr/bin/grep -Fq -- "$needle" "$file"; then
    fail "expected [$file] to contain [$needle]"
  fi
}

assert_file_not_contains() {
  local needle="$1"
  local file="$2"

  if /usr/bin/grep -Fq -- "$needle" "$file"; then
    fail "expected [$file] not to contain [$needle]"
  fi
}

run_test() {
  local name="$1"
  local test_function="$2"

  TESTS_RUN=$((TESTS_RUN + 1))
  if "$test_function"; then
    printf 'ok %d - %s\n' "$TESTS_RUN" "$name"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf 'not ok %d - %s\n' "$TESTS_RUN" "$name"
  fi
}

finish_tests() {
  if [[ "$TESTS_FAILED" -ne 0 ]]; then
    printf '# %d of %d tests failed\n' "$TESTS_FAILED" "$TESTS_RUN" >&2
    return 1
  fi

  printf '# all %d tests passed\n' "$TESTS_RUN"
}
