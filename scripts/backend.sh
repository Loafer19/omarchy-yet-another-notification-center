#!/usr/bin/env bash
# Store for yoyo.notification-center.
# Reads Omarchy's popup/history files; never writes into those directories.

set -uo pipefail
umask 077

state_home=${XDG_STATE_HOME:-$HOME/.local/state}
src_dir=${YANC_SRC_DIR:-$state_home/omarchy/notifications}
src_history=${YANC_SRC_HISTORY:-$src_dir/history}
store=${YANC_STORE:-$state_home/omarchy/yoyo.notification-center}
archive="$store/archive.jsonl"
trash="$store/trash.jsonl"
images="$store/images"
seen_file="$store/seen"
lock_file="$store/lock"
settings_file="$store/settings.json"

keep_days=${YANC_KEEP_DAYS:-30}
max_items=${YANC_MAX_ITEMS:-1000}
trash_days=${YANC_TRASH_DAYS:-30}
previews=${YANC_PREVIEWS:-1}

die() {
  printf '{"ok":false,"error":%s}\n' "$(printf '%s' "$1" | jq -Rs .)"
  exit 1
}

command -v jq >/dev/null 2>&1 || die "jq is not installed"

with_lock() {
  ( exec 9>"$lock_file"; flock 9; "$@" )
}

default_settings_json() {
  cat <<'JSON'
{
  "displayLimit": 50,
  "keepDays": 30,
  "maxItems": 1000,
  "trashDays": 30,
  "autoHideMs": 0,
  "soundEnabled": true,
  "defaultSound": "message-new-instant",
  "soundLow": "complete",
  "soundNormal": "message-new-instant",
  "soundCritical": "dialog-warning",
  "muteSoundWhenDnd": true,
  "appSounds": {},
  "badge": "Dot",
  "clickAction": "Auto",
  "showBody": true,
  "showPreview": true
}
JSON
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

now_ms() { printf '%s' "$(($(date +%s%N) / 1000000))"; }

load_runtime_limits() {
  [[ -f $settings_file ]] || return 0
  local kd mi td
  kd=$(jq -r '.keepDays // empty' "$settings_file" 2>/dev/null || true)
  mi=$(jq -r '.maxItems // empty' "$settings_file" 2>/dev/null || true)
  td=$(jq -r '.trashDays // empty' "$settings_file" 2>/dev/null || true)
  [[ $kd =~ ^[0-9]+$ ]] && (( kd >= 1 && kd <= 365 )) && keep_days=$kd
  [[ $mi =~ ^[0-9]+$ ]] && (( mi >= 50 && mi <= 10000 )) && max_items=$mi
  [[ $td =~ ^[0-9]+$ ]] && (( td >= 1 && td <= 365 )) && trash_days=$td
}

valid_key() {
  [[ ${1:-} =~ ^[A-Za-z0-9._+-]{1,128}$ ]]
}

valid_sound() {
  case ${1:-} in
    mute|message-new-instant|dialog-warning|dialog-error|complete|bell|camera-shutter|alarm-clock-elapsed|phone-incoming-call) return 0 ;;
    *) return 1 ;;
  esac
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

copy_image() {
  local src=$1 key=$2 slot=$3 dest tmp mime ext=""
  valid_key "$key" || { printf '%s' ""; return; }
  case $slot in
    appIcon|image|preview) ;;
    *) printf '%s' ""; return ;;
  esac
  src=${src#file://}
  [[ $src == /* ]] || { printf '%s' ""; return; }
  [[ $src == *..* ]] && { printf '%s' ""; return; }
  src=$(realpath -e -- "$src" 2>/dev/null) || { printf '%s' ""; return; }
  [[ -f $src && -r $src ]] || { printf '%s' ""; return; }
  command -v file >/dev/null 2>&1 || { printf '%s' ""; return; }

  tmp="$images/$key-$slot.tmp"
  dest="$images/$key-$slot"
  if timeout 5 head -c 5242881 -- "$src" > "$tmp" 2>/dev/null &&
     (( $(stat -c%s -- "$tmp" 2>/dev/null || echo 0) <= 5242880 )); then
    mime=$(file -bL --mime-type -- "$tmp" 2>/dev/null || true)
    case $mime in
      image/jpeg) ext=.jpg ;;
      image/png) ext=.png ;;
      image/webp) ext=.webp ;;
      image/gif) ext=.gif ;;
      *) rm -f -- "$tmp"; printf '%s' ""; return ;;
    esac
    if [[ $slot == preview ]] && command -v magick >/dev/null 2>&1; then
      timeout 5 magick "$tmp" -auto-orient -resize '720x720>' -quality 82 "$tmp.resized" 2>/dev/null \
        && mv -f -- "$tmp.resized" "$tmp"
      rm -f -- "$tmp.resized"
    fi
    dest="$images/$key-$slot$ext"
    mv -f -- "$tmp" "$dest"
    printf 'file://%s' "$dest"
  else
    rm -f -- "$tmp"
    printf '%s' ""
  fi
}

preview_source() {
  local action=$1 path
  if [[ $action == \[* ]]; then
    path=$(printf '%s' "$action" | jq -r --arg re '^(file://)?/[^"'"'"'\r\n]*\.(jpe?g|png|webp|gif)$' '
      if type == "array" then
        .[] | select(type == "string") | select(test($re; "i"))
      else empty end
    ' 2>/dev/null | head -n 1)
  else
    path=$(printf '%s' "$action" | grep -oiE "(file://)?/[^\"' ]*\.(jpe?g|png|webp|gif)" | head -n 1)
  fi
  path=${path#file://}
  [[ $path == /* && $path != *..* ]] || { printf '%s' ""; return; }
  printf '%s' "$path"
}

drop_images() {
  local key=$1
  valid_key "$key" || return 0
  rm -f -- "$images/$key-appIcon" "$images/$key-image" "$images/$key-preview"
  rm -f -- "$images/$key-appIcon."* "$images/$key-image."* "$images/$key-preview."*
  rm -f -- "$images/$key-appIcon.tmp" "$images/$key-image.tmp" "$images/$key-preview.tmp"
  rm -f -- "$images/$key-appIcon.tmp.resized" "$images/$key-image.tmp.resized" "$images/$key-preview.tmp.resized"
}

ingest_file() {
  local file=$1 announce_existing=${2:-0}
  local key entry app_icon image_src exec_src icon_copy image_copy file_src preview_copy size
  is_under "$file" "$src_dir" || is_under "$file" "$src_history" || return 0
  key=$(basename -- "$file"); key=${key%.json}
  valid_key "$key" || return 0
  if have_key "$key"; then
    (( announce_existing )) && grep -F "\"key\":\"$key\"" "$archive" | head -n 1
    return 0
  fi
  [[ -s $file ]] || return 0
  size=$(stat -c%s -- "$file" 2>/dev/null || echo 0)
  (( size > 0 && size <= 262144 )) || return 0
  jq -e . "$file" >/dev/null 2>&1 || return 0

  app_icon=$(jq -r '.appIcon // ""' "$file")
  image_src=$(jq -r '.image // ""' "$file")
  exec_src=$(jq -c '.execArgv // .exec // empty' "$file" 2>/dev/null || true)

  icon_copy=""
  image_copy=""
  if is_path "$app_icon"; then
    icon_copy=$(copy_image "$app_icon" "$key" "appIcon")
  else
    icon_copy=$(themed_icon "$app_icon")
  fi
  is_path "$image_src" && image_copy=$(copy_image "$image_src" "$key" "image")

  file_src=$(preview_source "$exec_src")
  preview_copy=""
  if (( previews )) && [[ -n $file_src ]]; then
    preview_copy=$(copy_image "$file_src" "$key" "preview")
  fi

  entry=$(jq -c \
    --arg key "$key" \
    --arg appIcon "$icon_copy" \
    --arg image "$image_copy" \
    --arg preview "$preview_copy" \
    '{
       key: $key,
       app: ((.app // "") | tostring | .[0:64]),
       appIcon: $appIcon,
       summary: ((.summary // "") | tostring | .[0:240]),
       body: ((.body // "") | tostring | .[0:500]),
       image: $image,
       preview: $preview,
       file: "",
       glyph: ((.glyph // "") | tostring | .[0:8]),
       urgency: (if (.urgency | tonumber? // 1) >= 2 then 2
                 elif (.urgency | tonumber? // 1) <= 0 then 0
                 else 1 end),
       timestamp: (.timestamp // 0)
     }
     | .timestamp = (if .timestamp > 0 then .timestamp
                     else ((.key | split("-")[0] | tonumber?) // 0) end)' \
    "$file" 2>/dev/null) || return 0
  [[ -n $entry ]] || return 0

  printf '%s\n' "$entry" >> "$archive"
  printf '%s\n' "$entry"
}

sync_all() {
  local file
  for file in "$src_history"/*.json "$src_dir"/*.json; do
    [[ -e $file ]] || continue
    ingest_file "$file"
  done
}

filter_jsonl() {
  local src=$1 pred=$2
  jq -Rc "$pred" "$src" 2>/dev/null || true
}

prune() {
  load_runtime_limits
  local cutoff trash_cutoff kept dropped
  cutoff=$(( $(now_ms) - keep_days * 86400000 ))
  trash_cutoff=$(( $(now_ms) - trash_days * 86400000 ))

  if [[ -s $archive ]]; then
    if kept=$(jq -Rc --argjson cutoff "$cutoff" \
        'fromjson? // empty | select((.timestamp // 0) >= $cutoff)' "$archive" 2>/dev/null); then
      kept=$(printf '%s\n' "$kept" | grep -v '^$' | tail -n "$max_items")
      dropped=$(comm -23 \
        <(jq -r '.key // empty' "$archive" 2>/dev/null | sort -u) \
        <(printf '%s\n' "$kept" | jq -r 'select(.key) | .key' 2>/dev/null | sort -u))
      printf '%s\n' "$kept" | grep -v '^$' > "$archive.tmp" || : > "$archive.tmp"
      mv -f "$archive.tmp" "$archive"
      local key
      while IFS= read -r key; do
        [[ -n $key ]] || continue
        drop_images "$key"
      done <<< "$dropped"
    fi
  fi

  if [[ -s $trash ]]; then
    if kept=$(jq -Rc --argjson cutoff "$trash_cutoff" \
        'fromjson? // empty | select((.trashedAt // .timestamp // 0) >= $cutoff)' "$trash" 2>/dev/null); then
      dropped=$(comm -23 \
        <(jq -r '.key // empty' "$trash" 2>/dev/null | sort -u) \
        <(printf '%s\n' "$kept" | jq -r 'select(.key) | .key' 2>/dev/null | sort -u))
      printf '%s\n' "$kept" | grep -v '^$' > "$trash.tmp" || : > "$trash.tmp"
      mv -f "$trash.tmp" "$trash"
      while IFS= read -r key; do
        [[ -n $key ]] || continue
        drop_images "$key"
      done <<< "$dropped"
    fi
  fi
}

quiet=0
sync_and_prune() {
  if (( quiet )); then sync_all >/dev/null; else sync_all; fi
  prune
}

cmd_sync() {
  ensure_store
  with_lock sync_and_prune
}

ingest_one() {
  ingest_file "$1" 1
  prune
}

cmd_watch() {
  ensure_store
  mkdir -p "$src_dir" "$src_history"
  quiet=1
  cmd_sync

  command -v inotifywait >/dev/null 2>&1 || die "inotifywait is not installed"

  exec 3< <(inotifywait -m -q -e close_write -e moved_to --format '%w%f' \
    "$src_dir" "$src_history" 2>/dev/null)
  watcher=$!
  trap 'kill "$watcher" 2>/dev/null' EXIT INT TERM

  while IFS= read -r file <&3; do
    [[ $file == *.json ]] || continue
    is_under "$file" "$src_dir" || is_under "$file" "$src_history" || continue
    with_lock ingest_one "$file"
  done
}

clamp_limit() {
  local limit=${1:-200}
  [[ $limit =~ ^[0-9]+$ ]] || limit=200
  (( limit < 1 )) && limit=1
  (( limit > 500 )) && limit=500
  printf '%s' "$limit"
}

list_file() {
  local src=$1 limit
  limit=$(clamp_limit "${2:-200}")
  tac "$src" 2>/dev/null \
    | jq -Rc 'fromjson? // empty' 2>/dev/null \
    | head -n "$limit" \
    | jq -s '.' 2>/dev/null || printf '[]\n'
}

cmd_list() { ensure_store; list_file "$archive" "${1:-200}"; }
cmd_trash_list() { ensure_store; list_file "$trash" "${1:-200}"; }

take_line() {
  local src=$1 key=$2
  jq -Rc --arg key "$key" 'fromjson? // empty | select(.key == $key)' "$src" 2>/dev/null | head -n 1
}

strip_key() {
  local src=$1 key=$2
  jq -Rc --arg key "$key" 'fromjson? // empty | select(.key != $key)' "$src" 2>/dev/null \
    | grep -v '^$' > "$src.tmp" || : > "$src.tmp"
  mv -f "$src.tmp" "$src"
}

dismiss_key() {
  local key=$1 line now
  line=$(take_line "$archive" "$key")
  [[ -n $line ]] || return 1
  now=$(now_ms)
  printf '%s\n' "$line" | jq -c --argjson trashedAt "$now" '. + {trashedAt: $trashedAt}' >> "$trash"
  strip_key "$archive" "$key"
  return 0
}

restore_key() {
  local key=$1 line
  line=$(take_line "$trash" "$key")
  [[ -n $line ]] || return 1
  printf '%s\n' "$line" | jq -c 'del(.trashedAt)' >> "$archive"
  strip_key "$trash" "$key"
  return 0
}

purge_key() {
  local key=$1
  have_key_in "$trash" "$key" || return 1
  strip_key "$trash" "$key"
  drop_images "$key"
  return 0
}

clear_all() {
  local now line
  now=$(now_ms)
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    printf '%s\n' "$line" | jq -c --argjson trashedAt "$now" '. + {trashedAt: $trashedAt}' >> "$trash"
  done < "$archive"
  : > "$archive"
}

empty_trash() {
  local key
  while IFS= read -r key; do
    [[ -n $key ]] || continue
    drop_images "$key"
  done < <(jq -r 'fromjson? // empty | .key' "$trash" 2>/dev/null)
  : > "$trash"
}

cmd_dismiss() {
  ensure_store
  local key=${1:-}
  valid_key "$key" || die "dismiss needs a key"
  if with_lock dismiss_key "$key"; then
    printf '{"ok":true,"dismissed":%s}\n' "$(printf '%s' "$key" | jq -Rs .)"
  else
    die "not in history"
  fi
}

cmd_restore() {
  ensure_store
  local key=${1:-}
  valid_key "$key" || die "restore needs a key"
  if with_lock restore_key "$key"; then
    printf '{"ok":true,"restored":%s}\n' "$(printf '%s' "$key" | jq -Rs .)"
  else
    die "not in trash"
  fi
}

cmd_purge() {
  ensure_store
  local key=${1:-}
  valid_key "$key" || die "purge needs a key"
  if with_lock purge_key "$key"; then
    printf '{"ok":true,"purged":%s}\n' "$(printf '%s' "$key" | jq -Rs .)"
  else
    die "not in trash"
  fi
}

cmd_clear() {
  ensure_store
  with_lock clear_all
  printf '{"ok":true,"cleared":true}\n'
}

cmd_empty_trash() {
  ensure_store
  with_lock empty_trash
  printf '{"ok":true,"emptied":true}\n'
}

cmd_seen() {
  ensure_store
  local stamp
  if [[ $# -gt 0 && -n ${1:-} ]]; then
    [[ ${1:-} =~ ^[0-9]{1,16}$ ]] || die "seen needs a millisecond stamp"
    printf '%s\n' "$1" > "$seen_file"
    printf '{"ok":true,"seen":%s}\n' "$1"
    return
  fi
  stamp=$(cat "$seen_file" 2>/dev/null || echo 0)
  [[ $stamp =~ ^[0-9]+$ ]] || stamp=0
  printf '{"ok":true,"seen":%s}\n' "$stamp"
}

cmd_unread() {
  ensure_store
  local seen
  seen=$(cat "$seen_file" 2>/dev/null || echo 0)
  [[ $seen =~ ^[0-9]+$ ]] || seen=0
  printf '{"ok":true,"unread":%s}\n' \
    "$(jq -Rc --argjson seen "$seen" 'fromjson? // empty | select((.timestamp // 0) > $seen)' "$archive" 2>/dev/null \
      | grep -c . || echo 0)"
}

cmd_settings_get() {
  ensure_store
  jq -c '.' "$settings_file" 2>/dev/null || default_settings_json | jq -c .
}

cmd_settings_set() {
  ensure_store
  local patch=${1:-}
  [[ -n $patch ]] || die "settings-set needs JSON"
  (( ${#patch} <= 32768 )) || die "settings patch too large"
  printf '%s' "$patch" | jq -e . >/dev/null 2>&1 || die "invalid JSON"
  with_lock merge_settings "$patch"
  cmd_settings_get
}

merge_settings() {
  local patch=$1
  jq -c --argjson patch "$patch" --argjson defaults "$(default_settings_json)" '
    def clamp(v; lo; hi; fb):
      ((v | tonumber? // fb) | if . < lo then lo elif . > hi then hi else . end);
    def as_bool(v; fb):
      if v == true then true elif v == false then false else fb end;
    def sound:
      if . == "email" or . == "message" then "message-new-instant"
      elif . == "warning" then "dialog-warning"
      elif . == "camera" then "camera-shutter"
      elif . == "mute" or . == "message-new-instant" or . == "dialog-warning"
           or . == "dialog-error" or . == "complete" or . == "bell"
           or . == "camera-shutter" or . == "alarm-clock-elapsed"
           or . == "phone-incoming-call" then .
      else "message-new-instant" end;
    def badge:
      if . == "Dot" or . == "Highlight" or . == "Count" or . == "None" then . else "Dot" end;
    def click:
      if . == "Auto" or . == "Focus the app" or . == "Nothing" then . else "Auto" end;
    def sounds(obj):
      (obj // {})
      | to_entries
      | map(select(.key | test("^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$")))
      | map({key: .key[0:64], value: (.value | tostring | sound)})
      | from_entries;
    ($defaults + .) as $cur
    | {
        displayLimit: clamp($patch.displayLimit // $cur.displayLimit; 10; 500; 50),
        keepDays: clamp($patch.keepDays // $cur.keepDays; 1; 365; 30),
        maxItems: clamp($patch.maxItems // $cur.maxItems; 50; 10000; 1000),
        trashDays: clamp($patch.trashDays // $cur.trashDays; 1; 365; 30),
        autoHideMs: clamp($patch.autoHideMs // $cur.autoHideMs; 0; 30000; 0),
        soundEnabled: as_bool($patch.soundEnabled // $cur.soundEnabled; true),
        defaultSound: (($patch.defaultSound // $cur.defaultSound) | tostring | sound),
        soundLow: (($patch.soundLow // $cur.soundLow) | tostring | sound),
        soundNormal: (($patch.soundNormal // $cur.soundNormal) | tostring | sound),
        soundCritical: (($patch.soundCritical // $cur.soundCritical) | tostring | sound),
        muteSoundWhenDnd: as_bool($patch.muteSoundWhenDnd // $cur.muteSoundWhenDnd; true),
        appSounds: sounds($patch.appSounds // $cur.appSounds),
        badge: (($patch.badge // $cur.badge) | tostring | badge),
        clickAction: (($patch.clickAction // $cur.clickAction) | tostring | click),
        showBody: as_bool($patch.showBody // $cur.showBody; true),
        showPreview: as_bool($patch.showPreview // $cur.showPreview; true)
      }
  ' "$settings_file" > "$settings_file.tmp" && mv -f "$settings_file.tmp" "$settings_file"
}

cmd_apps() {
  ensure_store
  cat "$archive" "$trash" 2>/dev/null | jq -s '
    [ .[] | .app // "" | select(. != "") ]
    | group_by(.)
    | map({app: .[0], count: length})
    | sort_by(-.count, .app)
  ' 2>/dev/null || printf '[]\n'
}

sound_event() {
  case $1 in
    email|message) printf '%s' "message-new-instant" ;;
    warning) printf '%s' "dialog-warning" ;;
    camera) printf '%s' "camera-shutter" ;;
    mute|"") printf '%s' "" ;;
    *) printf '%s' "$1" ;;
  esac
}

cmd_play_sound() {
  local id=${1:-message-new-instant} event file
  event=$(sound_event "$id")
  [[ -n $event ]] || { printf '{"ok":true,"played":false}\n'; return 0; }
  valid_sound "$event" || { printf '{"ok":true,"played":false}\n'; return 0; }
  [[ $event == mute ]] && { printf '{"ok":true,"played":false}\n'; return 0; }
  file="/usr/share/sounds/freedesktop/stereo/${event}.oga"
  if [[ -f $file ]] && command -v pw-play >/dev/null 2>&1; then
    pw-play -- "$file" >/dev/null 2>&1 &
    printf '{"ok":true,"played":true,"id":%s}\n' "$(printf '%s' "$event" | jq -Rs .)"
    return 0
  fi
  if command -v canberra-gtk-play >/dev/null 2>&1; then
    canberra-gtk-play -i "$event" >/dev/null 2>&1 &
    printf '{"ok":true,"played":true,"id":%s}\n' "$(printf '%s' "$event" | jq -Rs .)"
    return 0
  fi
  printf '{"ok":true,"played":false}\n'
}

cmd_seed() {
  ensure_store
  local count=${1:-16}
  [[ $count =~ ^[0-9]+$ ]] || count=16
  (( count > 48 )) && count=48
  with_lock seed_entries "$count"
  printf '{"ok":true,"seeded":%s}\n' "$count"
}

# app|icon|summary|body|minutesAgo|urgency (0 low / 1 normal / 2 critical)
readonly SEED_ROWS=(
  "Slack|slack|#design from Mara|Pushed the new empty state|4|1"
  "Signal|signal-desktop|Jules|Are we still on for Thursday?|55|1"
  "Chromium|chromium|Calendar|Standup starts in 10 minutes|38|2"
  "Spotify|spotify|Talk Talk|Life's What You Make It|12|0"
  "omarchy||Reminder|Stand up and walk about|96|0"
  "Thunderbird|thunderbird|Invoice paid|Nova Systems paid invoice 2026-114|190|1"
  "Discord|discord|#homelab|that fan curve fixed it|260|0"
  "Slack|slack|#ops|Deploy is live on production|140|2"
  "Signal|signal-desktop|Mum|Landed, all fine|1180|1"
  "omarchy||Update available|17 packages|520|1"
  "Chromium|chromium|GitHub|CI passed|3300|0"
  "Thunderbird|thunderbird|Domain renewal|renews in 14 days|1580|2"
)

seed_entries() {
  local count=${1:-16} i row stamp key app icon summary body minutes urgency
  local total=${#SEED_ROWS[@]}
  for (( i = 0; i < count; i++ )); do
    row=${SEED_ROWS[$((i % total))]}
    IFS='|' read -r app icon summary body minutes urgency <<< "$row"
    [[ $urgency =~ ^[0-2]$ ]] || urgency=1
    stamp=$(( $(now_ms) - (minutes + (i / total) * 2880) * 60000 ))
    key="seed-$stamp-$i"
    jq -cn \
      --arg key "$key" \
      --arg app "$app" \
      --arg appIcon "$icon" \
      --arg summary "$summary" \
      --arg body "$body" \
      --argjson timestamp "$stamp" \
      --argjson urgency "$urgency" \
      '{key:$key, app:$app, appIcon:$appIcon, summary:$summary, body:$body,
        image:"", preview:"", file:"", glyph:"", urgency:$urgency, timestamp:$timestamp}' >> "$archive"
  done
  jq -sc 'sort_by(.timestamp) | .[]' "$archive" > "$archive.tmp" && mv -f "$archive.tmp" "$archive"
}

case ${1:-} in
  sync) shift; quiet=1; cmd_sync; printf '{"ok":true,"synced":true}\n' ;;
  watch) shift; cmd_watch ;;
  list) shift; cmd_list "${1:-200}" ;;
  trash-list) shift; cmd_trash_list "${1:-200}" ;;
  dismiss) shift; cmd_dismiss "${1:-}" ;;
  restore) shift; cmd_restore "${1:-}" ;;
  purge) shift; cmd_purge "${1:-}" ;;
  clear) shift; cmd_clear ;;
  empty-trash) shift; cmd_empty_trash ;;
  seen) shift; cmd_seen "$@" ;;
  unread) shift; cmd_unread ;;
  settings-get) shift; cmd_settings_get ;;
  settings-set) shift; cmd_settings_set "${1:-}" ;;
  apps) shift; cmd_apps ;;
  play-sound) shift; cmd_play_sound "${1:-message}" ;;
  seed) shift; cmd_seed "${1:-16}" ;;
  prune) shift; ensure_store; with_lock prune; printf '{"ok":true,"pruned":true}\n' ;;
  *)
    cat >&2 <<'USAGE'
yoyo.notification-center store

  watch              follow Omarchy notifications and archive them
  sync               catch up, then prune
  list [LIMIT]       history, newest first
  trash-list [LIMIT] recycle bin
  dismiss KEY        history → trash
  restore KEY        trash → history
  purge KEY          delete from trash
  clear              all history → trash
  empty-trash        delete trash
  seen [MS]          last-opened stamp
  unread             count newer than seen
  settings-get
  settings-set JSON
  apps               apps seen in history+trash
  play-sound ID      freedesktop event name, or mute
  seed [N]
  prune
USAGE
    exit 64
    ;;
esac
