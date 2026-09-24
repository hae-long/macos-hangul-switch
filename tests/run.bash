#!/bin/bash
set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
overall_status=0
test_files_found=0

for test_file in "$PROJECT_ROOT"/tests/test_*.bash; do
  if [[ "$(basename "$test_file")" == "test_helper.bash" ]]; then
    continue
  fi

  test_files_found=$((test_files_found + 1))
  printf '# %s\n' "$(basename "$test_file")"
  if ! /bin/bash "$test_file"; then
    overall_status=1
  fi
done

if [[ "$test_files_found" -eq 0 ]]; then
  printf '%s\n' 'no test files found' >&2
  exit 1
fi

exit "$overall_status"
