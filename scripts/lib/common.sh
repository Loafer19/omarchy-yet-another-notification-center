# shellcheck shell=bash
# Paths, limits and helpers every command shares. Sourced by backend.sh.

defaults_js=$plugin_root/defaults.js
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
src_dir=${YANC_SRC_DIR:-$state_home/omarchy/notifications}
src_history=${YANC_SRC_HISTORY:-$src_dir/history}
store=${YANC_STORE:-$state_home/omarchy/yoyo.notification-center}
archive="$store/archive.jsonl"
trash="$store/trash.jsonl"
images="$store/images"
seen_file="$store/seen"
# omapager: the keys live.json/history.json held when we last read them, so a
# row deleted from the archive (Empty Trash, purge) is not taken in again.
ledger="$store/engine-keys"
# omapager: pictures the panel saved from live toasts, waiting for `capture`.
captures="$store/captures"
lock_file="$store/lock"
settings_file="$store/settings.json"

keep_days=${YANC_KEEP_DAYS:-30}
max_items=${YANC_MAX_ITEMS:-1000}
history_limit=${YANC_HISTORY_LIMIT:-50}
trash_days=${YANC_TRASH_DAYS:-30}
previews=${YANC_PREVIEWS:-1}

# Failures print {"ok":false,"error":"…"} on stdout and exit 1; the panel shows
# the error. Works without jq too (that is one of the errors).
json_string() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -Rs .
  else
    local s=${1//\\/\\\\}
    s=${s//\"/\\\"}
    printf '"%s"' "${s//[$'\t\r\n']/ }"
  fi
}

die() {
  printf '{"ok":false,"error":%s}\n' "$(json_string "$1")"
  printf 'yoyo.notification-center: %s\n' "$1" >&2
  exit 1
}

with_lock() {
  ( exec 9>"$lock_file"; flock 9; "$@" )
}

defaults_config() {
  awk 'BEGIN{p=0} /^var CONFIG = \{/ {p=1; sub(/^var CONFIG = /, "")} p' "$defaults_js"
}

default_settings_json() {
  defaults_config | jq -c '.defaults'
}

ensure_store() {
  mkdir -p "$store" "$images" || die "cannot create $store"
  [[ -f $archive ]] || : > "$archive"
  [[ -f $trash ]] || : > "$trash"
  if [[ ! -f $settings_file ]]; then
    default_settings_json > "$settings_file"
  fi
  chmod 700 "$store" "$images" 2>/dev/null || true
  chmod 600 "$archive" "$trash" "$settings_file" "$seen_file" 2>/dev/null || true
}

# YANC_NOW_MS pins the clock (tests only).
now_ms() {
  if [[ ${YANC_NOW_MS:-} =~ ^[0-9]+$ ]]; then printf '%s' "$YANC_NOW_MS"
  else printf '%s' "$(($(date +%s%N) / 1000000))"; fi
}

load_runtime_limits() {
  [[ -f $settings_file ]] || return 0
  local cfg
  cfg=$(defaults_config)
  limit_setting keep_days keepDays "$cfg"
  limit_setting max_items maxItems "$cfg"
  limit_setting trash_days trashDays "$cfg"
  limit_setting history_limit displayLimit "$cfg"
  # History cannot outgrow the archive ceiling.
  if (( history_limit > max_items )); then
    history_limit=$max_items
  fi
}

# Sets variable VAR to settings.json's KEY when it is a whole number, or to
# the limit's fallback when it is out of range (CFG: defaults.js config).
limit_setting() {
  local -n out=$1
  local key=$2 cfg=$3 v
  v=$(jq -r --arg k "$key" '.[$k] // empty' "$settings_file" 2>/dev/null || true)
  [[ $v =~ ^[0-9]+$ ]] || return 0
  # shellcheck disable=SC2034 # nameref
  out=$(printf '%s' "$cfg" | jq -r --arg k "$key" --argjson v "$v" \
    '.limits[$k] | if $v >= .min and $v <= .max then $v else .fallback end')
}

valid_key() {
  [[ ${1:-} =~ ^[A-Za-z0-9._+-]{1,128}$ ]]
}

valid_sound() {
  defaults_config | jq -e --arg id "${1:-}" '(.sounds | map(.id) | index($id)) != null' >/dev/null
}

themed_icon() {
  local s=${1:-}
  [[ $s =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || { printf '%s' ""; return; }
  [[ $s == *..* ]] && { printf '%s' ""; return; }
  printf '%s' "$s"
}

is_under() {
  local path=$1 root=$2
  local real root_real
  real=$(realpath -e -- "$path" 2>/dev/null) || return 1
  root_real=$(realpath -e -- "$root" 2>/dev/null) || return 1
  [[ $real == "$root_real" || $real == "$root_real"/* ]]
}

have_key_in() {
  local file=$1 key=$2
  valid_key "$key" || return 1
  [[ -s $file ]] || return 1
  grep -qF "\"key\":\"$key\"" "$file" 2>/dev/null
}

have_key() {
  have_key_in "$archive" "$1" || have_key_in "$trash" "$1"
}

is_path() {
  case $1 in
    file:///*|/*) return 0 ;;
    *) return 1 ;;
  esac
}

clamp_limit() {
  local limit=${1:-200}
  [[ $limit =~ ^[0-9]+$ ]] || limit=200
  (( limit < 1 )) && limit=1
  (( limit > 500 )) && limit=500
  printf '%s' "$limit"
}
