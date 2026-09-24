#!/bin/bash
set -euo pipefail

MHS_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MHS_PROJECT_ROOT/scripts/common.bash"

keep_sunshine=0

usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [options]

Options:
  --keep-sunshine  Leave the Sunshine keybinding unchanged.
  -h, --help       Show this help.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --keep-sunshine)
      keep_sunshine=1
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

if [[ ! -f "$MHS_STATE_DIR/install-state-version" ]]; then
  mhs_die "no managed installation state was found"
  exit 1
fi

temp_dir="$(mhs_make_temp_dir)"
trap '/bin/rm -rf "$temp_dir"' EXIT

if [[ "$keep_sunshine" == "0" && -x "$MHS_PROJECT_ROOT/scripts/sunshine.bash" ]]; then
  "$MHS_PROJECT_ROOT/scripts/sunshine.bash" uninstall
fi

mhs_bootout_managed_launch_agent
mhs_restore_hotkey "$temp_dir"
mhs_restore_hid_mapping "$temp_dir"
mhs_restore_launch_agent
mhs_archive_state

mhs_info "uninstalled managed physical Han/Yeong switching"
