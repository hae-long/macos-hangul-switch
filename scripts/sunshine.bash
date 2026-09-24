#!/bin/bash
set -euo pipefail

MHS_PROJECT_ROOT="${MHS_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$MHS_PROJECT_ROOT/scripts/common.bash"

requested_command="${1:-}"
if [[ -n "${MHS_SUNSHINE_CONFIG:-}" ]]; then
  SUNSHINE_CONFIG="$MHS_SUNSHINE_CONFIG"
elif [[ "$requested_command" == "uninstall" || "$requested_command" == "status" ]] &&
  [[ -f "$MHS_STATE_DIR/sunshine-config-path" ]]; then
  SUNSHINE_CONFIG="$(/usr/bin/head -n 1 "$MHS_STATE_DIR/sunshine-config-path")"
else
  SUNSHINE_CONFIG="$MHS_EFFECTIVE_HOME/.config/sunshine/sunshine.conf"
fi
SUNSHINE_SOURCE=165
SUNSHINE_DESTINATION=129

block_start=0
block_end=0
pair_sources=()
pair_destinations=()

usage() {
  cat <<'EOF'
Usage: scripts/sunshine.bash install|uninstall|status|validate-install

Edits the macOS Sunshine configuration without restarting Sunshine.
Set MHS_SUNSHINE_CONFIG to use a non-default configuration path.
EOF
}

sunshine_number() {
  local token="$1"

  if [[ "$token" =~ ^0[xX][0-9A-Fa-f]+$ ]]; then
    printf '%d\n' "$token"
  elif [[ "$token" =~ ^[0-9]+$ ]]; then
    printf '%d\n' "$((10#$token))"
  else
    mhs_die "invalid Sunshine keybinding number: $token"
    return 1
  fi
}

sunshine_parse() {
  local start_lines
  local start_count
  local block_content
  local residual_content
  local token
  local token_count
  local index
  local source
  local destination

  block_start=0
  block_end=0
  pair_sources=()
  pair_destinations=()

  if [[ ! -f "$SUNSHINE_CONFIG" ]]; then
    mhs_die "Sunshine configuration not found: $SUNSHINE_CONFIG"
    return 1
  fi

  start_lines="$(
    /usr/bin/awk '/^[[:space:]]*keybindings[[:space:]]*=/ { print NR }' "$SUNSHINE_CONFIG"
  )"
  start_count="$(printf '%s\n' "$start_lines" | /usr/bin/awk 'NF { count++ } END { print count + 0 }')"

  if [[ "$start_count" -gt 1 ]]; then
    mhs_die "multiple Sunshine keybindings blocks are not supported"
    return 1
  fi
  if [[ "$start_count" -eq 0 ]]; then
    return
  fi

  block_start="$(printf '%s\n' "$start_lines" | /usr/bin/awk 'NF { print; exit }')"
  block_end="$(
    /usr/bin/awk -v start="$block_start" '
      NR >= start && index($0, "]") {
        print NR
        exit
      }
    ' "$SUNSHINE_CONFIG"
  )"

  if [[ -z "$block_end" ]]; then
    mhs_die "Sunshine keybindings block has no closing bracket"
    return 1
  fi

  block_content="$(
    /usr/bin/awk -v start="$block_start" -v finish="$block_end" '
      NR < start || NR > finish { next }
      {
        line = $0
        sub(/#.*/, "", line)
        if (NR == start) {
          opening = index(line, "[")
          if (!opening) {
            exit 65
          }
          line = substr(line, opening + 1)
        }
        closing = index(line, "]")
        if (closing) {
          line = substr(line, 1, closing - 1)
          print line
          exit
        }
        print line
      }
    ' "$SUNSHINE_CONFIG"
  )" || {
    mhs_die "Sunshine keybindings block has no opening bracket"
    return 1
  }

  residual_content="$(
    printf '%s\n' "$block_content" |
      /usr/bin/sed -E \
        -e 's/0[xX][0-9A-Fa-f]+//g' \
        -e 's/[0-9]+//g' \
        -e 's/[,[:space:]]//g'
  )"
  if [[ -n "$residual_content" ]]; then
    mhs_die "Sunshine keybindings contain an unsupported token"
    return 1
  fi

  tokens=()
  while IFS= read -r token; do
    if [[ -n "$token" ]]; then
      tokens[${#tokens[@]}]="$token"
    fi
  done < <(
    printf '%s\n' "$block_content" |
      /usr/bin/grep -Eo '0[xX][0-9A-Fa-f]+|[0-9]+' || true
  )

  token_count="${#tokens[@]}"
  if [[ $((token_count % 2)) -ne 0 ]]; then
    mhs_die "Sunshine keybindings must contain an even number of elements"
    return 1
  fi

  index=0
  while [[ "$index" -lt "$token_count" ]]; do
    source="$(sunshine_number "${tokens[$index]}")"
    destination="$(sunshine_number "${tokens[$((index + 1))]}")"
    pair_sources[${#pair_sources[@]}]="$source"
    pair_destinations[${#pair_destinations[@]}]="$destination"
    index=$((index + 2))
  done
}

sunshine_pair_state() {
  local index
  local found=0

  index=0
  while [[ "$index" -lt "${#pair_sources[@]}" ]]; do
    if [[ "${pair_sources[$index]}" == "$SUNSHINE_SOURCE" ]]; then
      if [[ "${pair_destinations[$index]}" != "$SUNSHINE_DESTINATION" ]]; then
        printf '%s\n' "conflict"
        return
      fi
      found=1
    fi
    index=$((index + 1))
  done

  if [[ "$found" == "1" ]]; then
    printf '%s\n' "exact"
  else
    printf '%s\n' "absent"
  fi
}

sunshine_render_pairs() {
  local index=0
  local pair_count="${#pair_sources[@]}"
  local suffix

  if [[ "$pair_count" -eq 0 ]]; then
    return
  fi

  printf '%s\n' 'keybindings = ['
  while [[ "$index" -lt "$pair_count" ]]; do
    suffix=","
    if [[ "$index" -eq $((pair_count - 1)) ]]; then
      suffix=""
    fi
    printf '  0x%02X, 0x%02X%s\n' \
      "${pair_sources[$index]}" \
      "${pair_destinations[$index]}" \
      "$suffix"
    index=$((index + 1))
  done
  printf '%s\n' ']'
}

sunshine_write() {
  local config_dir
  local temp_file
  local backup_file
  local mode
  local total_lines
  local final_byte

  config_dir="$(dirname "$SUNSHINE_CONFIG")"
  temp_file="$(/usr/bin/mktemp "$config_dir/.sunshine.conf.mhs.XXXXXX")"
  mode="$(/usr/bin/stat -f '%Lp' "$SUNSHINE_CONFIG")"

  if [[ "$block_start" -eq 0 ]]; then
    /usr/bin/awk '{ print }' "$SUNSHINE_CONFIG" > "$temp_file"
    if [[ -s "$temp_file" ]]; then
      printf '\n' >> "$temp_file"
    fi
    sunshine_render_pairs >> "$temp_file"
  else
    total_lines="$(/usr/bin/awk 'END { print NR + 0 }' "$SUNSHINE_CONFIG")"
    : > "$temp_file"
    if [[ "$block_start" -gt 1 ]]; then
      /usr/bin/sed -n "1,$((block_start - 1))p" "$SUNSHINE_CONFIG" >> "$temp_file"
    fi
    sunshine_render_pairs >> "$temp_file"
    if [[ "$block_end" -lt "$total_lines" ]]; then
      /usr/bin/sed -n "$((block_end + 1)),${total_lines}p" "$SUNSHINE_CONFIG" >> "$temp_file"
    fi
  fi

  if [[ -s "$temp_file" ]]; then
    final_byte="$(/usr/bin/tail -c 1 "$temp_file" | /usr/bin/od -An -t x1 | /usr/bin/tr -d '[:space:]')"
    if [[ "$final_byte" != "0a" ]]; then
      printf '\n' >> "$temp_file"
    fi
  fi

  backup_file="$SUNSHINE_CONFIG.backup-macos-hangul-switch-$(/bin/date +%Y%m%d-%H%M%S)-$$"
  /bin/cp -p "$SUNSHINE_CONFIG" "$backup_file"
  /bin/chmod "$mode" "$temp_file"
  /bin/mv "$temp_file" "$SUNSHINE_CONFIG"
  mhs_info "Sunshine backup created at $backup_file"
}

sunshine_record_state() {
  local ownership="$1"

  /bin/mkdir -p "$MHS_STATE_DIR"
  /bin/chmod 700 "$MHS_STATE_DIR"
  printf '%s\n' "$SUNSHINE_CONFIG" > "$MHS_STATE_DIR/sunshine-config-path"
  /bin/rm -f "$MHS_STATE_DIR/sunshine-added" "$MHS_STATE_DIR/sunshine-preexisting"
  : > "$MHS_STATE_DIR/$ownership"
}

sunshine_validate_install() {
  local state

  sunshine_parse
  state="$(sunshine_pair_state)"
  if [[ "$state" == "conflict" ]]; then
    mhs_die "Sunshine keybinding conflict: source 0xA5 already maps to another destination"
    return 1
  fi
}

sunshine_install() {
  local state

  sunshine_validate_install
  state="$(sunshine_pair_state)"

  if [[ "$state" == "exact" ]]; then
    if [[ ! -f "$MHS_STATE_DIR/sunshine-added" ]]; then
      sunshine_record_state "sunshine-preexisting"
    fi
    mhs_info "Sunshine 0xA5 -> 0x81 is already configured"
    return
  fi

  pair_sources[${#pair_sources[@]}]="$SUNSHINE_SOURCE"
  pair_destinations[${#pair_destinations[@]}]="$SUNSHINE_DESTINATION"
  sunshine_write
  sunshine_record_state "sunshine-added"
  mhs_info "added Sunshine 0xA5 -> 0x81; restart Sunshine manually"
}

sunshine_uninstall() {
  local state
  local remaining_sources=()
  local remaining_destinations=()
  local index=0

  if [[ -f "$MHS_STATE_DIR/sunshine-preexisting" ]]; then
    mhs_info "leaving the pre-existing Sunshine 0xA5 -> 0x81 mapping untouched"
    return
  fi
  if [[ ! -f "$MHS_STATE_DIR/sunshine-added" ]]; then
    mhs_info "no managed Sunshine mapping was found"
    return
  fi

  sunshine_parse
  state="$(sunshine_pair_state)"
  if [[ "$state" != "exact" ]]; then
    mhs_warn "managed Sunshine mapping changed after installation; leaving the file untouched"
    return
  fi

  while [[ "$index" -lt "${#pair_sources[@]}" ]]; do
    if [[ "${pair_sources[$index]}" != "$SUNSHINE_SOURCE" ||
      "${pair_destinations[$index]}" != "$SUNSHINE_DESTINATION" ]]; then
      remaining_sources[${#remaining_sources[@]}]="${pair_sources[$index]}"
      remaining_destinations[${#remaining_destinations[@]}]="${pair_destinations[$index]}"
    fi
    index=$((index + 1))
  done

  pair_sources=()
  pair_destinations=()
  if [[ "${#remaining_sources[@]}" -gt 0 ]]; then
    pair_sources=("${remaining_sources[@]}")
    pair_destinations=("${remaining_destinations[@]}")
  fi
  sunshine_write
  /bin/rm -f "$MHS_STATE_DIR/sunshine-added"
  mhs_info "removed the managed Sunshine 0xA5 -> 0x81 mapping"
}

sunshine_status() {
  local state

  if ! sunshine_parse >/dev/null 2>&1; then
    printf '%-24s %s\n' "Sunshine 0xA5 -> 0x81" "configuration unavailable"
    return 1
  fi

  state="$(sunshine_pair_state)"
  case "$state" in
    exact)
      printf '%-24s %s\n' "Sunshine 0xA5 -> 0x81" "configured"
      ;;
    conflict)
      printf '%-24s %s\n' "Sunshine 0xA5 -> 0x81" "conflict"
      return 1
      ;;
    *)
      printf '%-24s %s\n' "Sunshine 0xA5 -> 0x81" "not configured"
      return 1
      ;;
  esac
}

if [[ "$#" -ne 1 ]]; then
  usage >&2
  exit 64
fi

case "$1" in
  install)
    sunshine_install
    ;;
  uninstall)
    sunshine_uninstall
    ;;
  status)
    sunshine_status
    ;;
  validate-install)
    sunshine_validate_install
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage >&2
    mhs_die "unknown command: $1"
    exit 64
    ;;
esac
