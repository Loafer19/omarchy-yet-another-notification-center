#!/usr/bin/env bash
# Store for yoyo.notification-center.
# Reads Omarchy's notification files; never writes into those directories.
# Two layouts:
#   legacy   (Omarchy 4.0.x) one JSON file per notification in
#            notifications/ (on screen) and notifications/history/
#   omapager (Omarchy 4.5)   notifications/live.json (on screen, oldest first)
#            and notifications/history.json (closed, newest first)
#            Those files keep no pictures, so the panel saves a toast's
#            picture while it is on screen (captures/KEY.png, see capture).

set -uo pipefail
umask 077

plugin_root=$(cd "$(dirname -- "$0")/.." && pwd)
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

command -v jq >/dev/null 2>&1 || die "jq is not installed"
[[ -f $defaults_js ]] || die "defaults.js is missing"

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
  local kd mi td dl cfg
  cfg=$(defaults_config)
  kd=$(jq -r '.keepDays // empty' "$settings_file" 2>/dev/null || true)
  mi=$(jq -r '.maxItems // empty' "$settings_file" 2>/dev/null || true)
  td=$(jq -r '.trashDays // empty' "$settings_file" 2>/dev/null || true)
  dl=$(jq -r '.displayLimit // empty' "$settings_file" 2>/dev/null || true)
  if [[ $kd =~ ^[0-9]+$ ]]; then
    keep_days=$(printf '%s' "$cfg" | jq -r --argjson v "$kd" '.limits.keepDays | if $v >= .min and $v <= .max then $v else .fallback end')
  fi
  if [[ $mi =~ ^[0-9]+$ ]]; then
    max_items=$(printf '%s' "$cfg" | jq -r --argjson v "$mi" '.limits.maxItems | if $v >= .min and $v <= .max then $v else .fallback end')
  fi
  if [[ $td =~ ^[0-9]+$ ]]; then
    trash_days=$(printf '%s' "$cfg" | jq -r --argjson v "$td" '.limits.trashDays | if $v >= .min and $v <= .max then $v else .fallback end')
  fi
  if [[ $dl =~ ^[0-9]+$ ]]; then
    history_limit=$(printf '%s' "$cfg" | jq -r --argjson v "$dl" '.limits.displayLimit | if $v >= .min and $v <= .max then $v else .fallback end')
  fi
  # History cannot outgrow the archive ceiling.
  if (( history_limit > max_items )); then
    history_limit=$max_items
  fi
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

# ---- Omarchy 4.5 (omapager) --------------------------------------------------
# Rows carry key, app, appIcon (a theme name), summary, body, glyph, urgency
# and ts (seconds). Pictures are never persisted there, so none are archived.
engine_live="$src_dir/live.json"
engine_history="$src_dir/history.json"

engine_files_present() {
  [[ -f $engine_history || -f $engine_live ]]
}

# Rows from FILE as compact JSON, oldest first. Anything but an array of
# objects with a valid key is skipped; oversized files are not parsed.
engine_rows() {
  local file=$1 order=$2 size
  [[ -s $file ]] || return 0
  is_under "$file" "$src_dir" || return 0
  size=$(stat -c%s -- "$file" 2>/dev/null || echo 0)
  (( size > 0 && size <= 4194304 )) || return 0
  jq -c --arg order "$order" '
    if type == "array" then . else [] end
    | map(select(type == "object" and (.key | type) == "string"
                 and (.key | test("^[A-Za-z0-9._+-]{1,128}$"))))
    | if $order == "newest-first" then reverse else . end
    | .[]
  ' "$file" 2>/dev/null || true
}

# What 4.5 shows for a secret-bearing notification (Store.js redacted()).
engine_redacted() {
  [[ $1 == "Verification notification" && $2 == "[redacted]" ]]
}

# A picture the panel already captured for KEY (capture), as file:// URL.
captured_image() {
  local key=$1 f
  valid_key "$key" || return 0
  for f in "$images/$key-image".png "$images/$key-image".jpg "$images/$key-image".webp "$images/$key-image".gif; do
    [[ -f $f && ! -L $f ]] && { printf 'file://%s' "$f"; return 0; }
  done
  return 0
}

# showPreview from settings.json (default on): off = no new picture copies.
previews_enabled() {
  (( previews )) || return 1
  [[ -f $settings_file ]] || return 0
  [[ $(jq -r 'if .showPreview == false then "off" else "on" end' "$settings_file" 2>/dev/null) != off ]]
}

# Finish one new omapager entry (compact JSON with _exec/_redacted): attach the
# captured picture and a screenshot preview from the click command, like 4.0;
# a redacted placeholder keeps no picture at all.
engine_finish() {
  local line=$1 key summary body exec image="" preview="" file_src
  key=$(jq -r '.key' <<< "$line" 2>/dev/null) || return 0
  summary=$(jq -r '.summary' <<< "$line" 2>/dev/null)
  body=$(jq -r '.body' <<< "$line" 2>/dev/null)
  if engine_redacted "$summary" "$body"; then
    drop_images "$key"
  else
    image=$(captured_image "$key")
    exec=$(jq -r '._exec // ""' <<< "$line" 2>/dev/null)
    if [[ -n $exec ]] && previews_enabled; then
      file_src=$(preview_source "$exec")
      [[ -n $file_src ]] && preview=$(copy_image "$file_src" "$key" "preview")
    fi
  fi
  jq -c --arg image "$image" --arg preview "$preview" \
    'del(._exec) | .image = $image | .preview = $preview' \
    <<< "$line" 2>/dev/null || jq -c 'del(._exec)' <<< "$line"
}

# Archive every row of live.json and history.json not seen before; print the
# new entries. Known = archive + trash + the ledger. The ledger is then the
# keys both files hold now, so it stays as small as they are.
# link: the first web address in the text, else the site a browser
# notification came from (its source).
ingest_engine() {
  local rows new line done_lines=""
  rows=$( { engine_rows "$engine_history" newest-first; engine_rows "$engine_live" oldest-first; } )
  [[ -n $rows ]] || { : > "$ledger"; return 0; }
  new=$(printf '%s\n' "$rows" | jq -nc \
      --slurpfile have <( { jq -Rc 'fromjson? // empty | .key // empty | strings' "$archive" "$trash" 2>/dev/null
                           cat "$ledger" 2>/dev/null | jq -Rc 'select(length > 0)'; } ) '
    def icon: tostring | if test("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$") and (contains("..") | not)
                         then . else "" end;
    def ms: (tonumber? // 0) | if . > 0 then (. * 1000 | round) else 0 end;
    def weburl: if type == "string" and length <= 2048
                   and test("^https?://[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*(:[0-9]{1,5})?([/?#][^\\s<>\"'"'"'\\\\]*)?$")
                   and (explode | any(. < 32 or (. >= 127 and . < 160)) | not)
                then . else "" end;
    def link: . as $row | ((($row.rawBody // "") | tostring) + " " + (($row.body // "") | tostring)) as $b
      | ([ ($b | [scan("href=[\"'"'"'](https?://[^\"'"'"'<>\\s]+)[\"'"'"']")] | map(.[0]) | .[]),
           ($b | gsub("<[^>]*>"; " ") | [scan("https?://[^\\s<>\"'"'"']+")] | .[]
               | sub("[).,;:!?]+$"; "")) ]
         | map(gsub("&amp;"; "&") | weburl) | map(select(. != "")) | first) // ""
      | if . != "" then .
        else (($row.source // "") | tostring | ascii_downcase
              | if test("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$")
                then "https://" + . + "/" else "" end)
        end;
    def redacted: .summary == "Verification notification" and .body == "[redacted]";
    reduce inputs as $r ({k: ($have | map({(.): true}) | add // {}), out: []};
      if .k[$r.key] then . else .k[$r.key] = true | .out += [$r] end)
    | .out[]
    | (if redacted then "" else link end) as $link
    | ((.execArgv // "") | if type == "string" then . elif type == "array" then tojson else "" end) as $exec
    | {
        key: .key,
        app: ((.app // "") | tostring | .[0:64]),
        appIcon: ((.appIcon // "") | icon),
        summary: ((.summary // "") | tostring | .[0:240]),
        body: ((.body // "") | tostring | .[0:500]),
        image: "",
        preview: "",
        file: "",
        glyph: ((.glyph // "") | tostring | .[0:8]),
        urgency: (if (.urgency | tonumber? // 1) >= 2 then 2
                  elif (.urgency | tonumber? // 1) <= 0 then 0
                  else 1 end),
        timestamp: (((.ts // 0) | ms) as $t
                    | if $t > 0 then $t else ((.closed_ts // 0) | ms) end)
      }
    | if $link != "" then .link = $link else . end
    | ._exec = $exec
  ') || return 1
  if [[ -n $new ]]; then
    while IFS= read -r line; do
      [[ -n $line ]] || continue
      line=$(engine_finish "$line")
      [[ -n $line ]] && done_lines+=$line$'\n'
    done <<< "$new"
    new=${done_lines%$'\n'}
  fi
  if [[ -n $new ]]; then
    printf '%s\n' "$new" >> "$archive" || return 1
  fi
  if ! { printf '%s\n' "$rows" | jq -r '.key' > "$ledger.tmp" 2>/dev/null && mv -f "$ledger.tmp" "$ledger"; }; then
    rm -f "$ledger.tmp"
  fi
  [[ -n $new ]] && printf '%s\n' "$new"
  return 0
}

# omapager: a picture the panel saved from a live toast (captures/KEY.png) is
# checked like any other copy and moved into images/. If KEY is archived
# already it gets the picture now (and is printed); otherwise ingest picks it
# up. A redacted placeholder never gets one.
capture_one() {
  local key=$1 staged="$captures/$1.png" dest file patched=""
  [[ -f $staged && ! -L $staged ]] || return 2
  dest=$(copy_image "$staged" "$key" "image")
  rm -f -- "$staged"
  [[ -n $dest ]] || return 3
  for file in "$archive" "$trash"; do
    have_key_in "$file" "$key" || continue
    if jq -Rc --arg k "$key" 'fromjson? // empty | select(.key == $k)
         | select(.summary == "Verification notification" and .body == "[redacted]")' "$file" 2>/dev/null | grep -q .; then
      drop_images "$key"
      return 0
    fi
    if ! { jq -Rc --arg k "$key" --arg d "$dest" 'fromjson? // empty
             | if .key == $k and ((.image // "") == "") then .image = $d else . end' "$file" > "$file.tmp" 2>/dev/null \
           && mv -f -- "$file.tmp" "$file"; }; then
      rm -f -- "$file.tmp"; return 1
    fi
    [[ $file == "$archive" ]] && patched=$(jq -Rc --arg k "$key" 'fromjson? // empty | select(.key == $k)' "$archive" 2>/dev/null | head -n 1)
  done
  [[ -n $patched ]] && printf '%s\n' "$patched"
  return 0
}

cmd_capture() {
  local key=${1:-} rc=0
  valid_key "$key" || die "capture needs a key"
  ensure_store
  mkdir -p "$captures" && chmod 700 "$captures" 2>/dev/null
  with_lock capture_one "$key" || rc=$?
  case $rc in
    0) ;;
    2) die "nothing captured for $key" ;;
    3) die "not a picture" ;;
    *) die "cannot write $store" ;;
  esac
}

# omapager housekeeping: a capture nobody claimed (a toast that was never
# archived, e.g. silenced and ephemeral) is gone after a day.
prune_captures() {
  local f key
  [[ -d $captures ]] && find "$captures" -maxdepth 1 -type f -name '*.png' -mmin +1440 -delete 2>/dev/null
  [[ -d $images ]] || return 0
  for f in "$images"/*-image.*; do
    [[ -f $f ]] || continue
    key=$(basename -- "$f"); key=${key%-image.*}
    valid_key "$key" || continue
    have_key "$key" && continue
    grep -qxF -- "$key" "$ledger" 2>/dev/null && continue
    [[ -n $(find "$f" -mmin +1440 2>/dev/null) ]] && drop_images "$key"
  done
  return 0
}

filter_jsonl() {
  local src=$1 pred=$2
  jq -Rc "$pred" "$src" 2>/dev/null || true
}

prune() {
  load_runtime_limits
  local cutoff trash_cutoff now limit tagged key

  now=$(now_ms)
  cutoff=$(( now - keep_days * 86400000 ))
  trash_cutoff=$(( now - trash_days * 86400000 ))
  limit=$history_limit
  (( limit < 1 )) && limit=1

  if [[ -s $archive ]]; then
    # One jq pass over History, in file order:
    # - entries older than keepDays are dropped for good;
    # - History keeps the newest displayLimit (and never more than maxItems);
    #   the oldest overflow goes to Trash with trashedAt = now.
    # Lines are tagged "A\t" (stay) / "T\t" (to Trash); compact JSON never
    # contains a raw tab. If jq fails nothing is written.
    tagged=$(jq -Rnr --argjson cutoff "$cutoff" --argjson limit "$limit" \
        --argjson max "$max_items" --argjson now "$now" '
      [inputs | fromjson? // empty | select((.timestamp // 0) >= $cutoff)] as $kept
      | ([$limit, $max] | min | if . < 0 then 0 else . end) as $cap
      | ([($kept | length) - $cap, 0] | max) as $drop
      | ($kept[:$drop][] | "T\t" + (. + {trashedAt: $now} | tojson)),
        ($kept[$drop:][] | "A\t" + tojson)
    ' "$archive" 2>/dev/null) || return 1
    # New History first, so a failed write changes nothing; then Trash.
    if ! printf '%s\n' "$tagged" | sed -n 's/^A\t//p' > "$archive.tmp"; then
      rm -f "$archive.tmp"; return 1
    fi
    if [[ $tagged == *$'T\t'* ]] \
        && ! printf '%s\n' "$tagged" | sed -n 's/^T\t//p' >> "$trash"; then
      rm -f "$archive.tmp"; return 1
    fi
    mv -f "$archive.tmp" "$archive" || { rm -f "$archive.tmp"; return 1; }
  fi

  if [[ -s $trash ]]; then
    # One jq pass over Trash: keep entries newer than trashDays, list the keys
    # that are gone (no kept entry with that key) so their pictures go too.
    tagged=$(jq -Rnr --argjson cutoff "$trash_cutoff" '
      [inputs | fromjson? // empty] as $all
      | ($all | map(select((.trashedAt // .timestamp // 0) >= $cutoff))) as $kept
      | ($kept | map(.key // empty | tostring) | unique) as $keep
      | ($kept[] | "A\t" + tojson),
        ($all | map(.key // empty | tostring) | unique - $keep | .[] | "D\t" + .)
    ' "$trash" 2>/dev/null) || return 1
    if ! printf '%s\n' "$tagged" | sed -n 's/^A\t//p' > "$trash.tmp" \
        || ! mv -f "$trash.tmp" "$trash"; then
      rm -f "$trash.tmp"; return 1
    fi
    while IFS= read -r key; do
      [[ -n $key ]] && drop_images "$key"
    done < <(printf '%s\n' "$tagged" | sed -n 's/^D\t//p')
  fi
  return 0
}


quiet=0
engine=legacy
sync_and_prune() {
  local sync=sync_all
  [[ $engine == omapager ]] && sync=ingest_engine
  if (( quiet )); then "$sync" >/dev/null; else "$sync"; fi
  prune || return 1
  [[ $engine == omapager ]] && prune_captures
  return 0
}

cmd_sync() {
  ensure_store
  with_lock sync_and_prune
}

# legacy | omapager | auto (omapager when its files are there). The panel
# passes what the running Omarchy service is; auto is its fallback.
set_engine() {
  case ${1:-legacy} in
    legacy|"") engine=legacy ;;
    omapager) engine=omapager ;;
    auto) if engine_files_present; then engine=omapager; else engine=legacy; fi ;;
    *) die "unknown engine: $1" ;;
  esac
}

ingest_one() {
  ingest_file "$1" 1
  prune
}

ingest_engine_one() {
  ingest_engine
  prune
}

cmd_watch() {
  set_engine "${1:-legacy}"
  ensure_store
  local -a dirs
  if [[ $engine == omapager ]]; then
    # 4.5 keeps everything in two files; never recreate the old history/.
    mkdir -p "$src_dir" "$captures" && chmod 700 "$captures" 2>/dev/null
    dirs=("$src_dir")
  else
    mkdir -p "$src_dir" "$src_history"
    dirs=("$src_dir" "$src_history")
  fi
  quiet=1
  cmd_sync

  command -v inotifywait >/dev/null 2>&1 || die "inotifywait is not installed"

  # inotifywait must not outlive us. The EXIT trap only runs when we exit
  # cleanly; when the shell restarts, this script can be SIGKILLed, and the
  # watcher used to linger, reparented to systemd, one per restart. So the
  # kernel kills it with us (setpriv --pdeathsig), or, without setpriv, a
  # small guard does once our pid is gone.
  local self=$BASHPID parent check=${YANC_WATCH_CHECK:-5}
  parent=$(ps -o ppid= -p "$self" 2>/dev/null | tr -d ' ')
  local -a deathsig=()
  if [[ -z ${YANC_NO_PDEATHSIG:-} ]] && command -v setpriv >/dev/null 2>&1 \
    && setpriv --pdeathsig TERM true 2>/dev/null; then
    deathsig=(setpriv --pdeathsig TERM --)
  fi
  exec 3< <(exec "${deathsig[@]}" inotifywait -m -q -e close_write -e moved_to --format '%w%f' \
    "${dirs[@]}" 2>/dev/null)
  watcher=$!
  if (( ${#deathsig[@]} == 0 )); then
    (while kill -0 "$self" 2>/dev/null; do sleep 1; done; kill "$watcher" 2>/dev/null) >/dev/null 2>&1 &
  fi
  trap 'kill "$watcher" 2>/dev/null' EXIT INT TERM

  local file rc now_parent
  while true; do
    IFS= read -r -t "$check" file <&3; rc=$?
    if (( rc > 128 )); then
      # Timed out: stop once whoever started us is gone (we were reparented)
      # or the watcher died.
      now_parent=$(ps -o ppid= -p "$self" 2>/dev/null | tr -d ' ')
      [[ -n $parent && $now_parent != "$parent" ]] && exit 0
      kill -0 "$watcher" 2>/dev/null || exit 1
      continue
    fi
    (( rc == 0 )) || break
    if [[ $engine == omapager ]]; then
      [[ $file == "$engine_live" || $file == "$engine_history" ]] || continue
      with_lock ingest_engine_one
      continue
    fi
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
  [[ -s $src ]] || { printf '[]\n'; return; }
  # Do not pipe through head: pipefail would append a second [] after a
  # successful array once the archive is larger than the display limit.
  jq -n --argjson n "$limit" '[inputs] | sort_by(.timestamp // 0) | reverse | .[:$n]' "$src" 2>/dev/null \
    || printf '[]\n'
}

cmd_list() { ensure_store; list_file "$archive" "${1:-200}"; }
cmd_trash_list() { ensure_store; list_file "$trash" "${1:-200}"; }

take_line() {
  local src=$1 key=$2
  jq -Rc --arg key "$key" 'fromjson? // empty | select(.key == $key)' "$src" 2>/dev/null | head -n 1
}

# Rewrite SRC without KEY. Returns 1 (SRC untouched) if jq or the write fails,
# so a failed write can never empty the file.
strip_key() {
  local src=$1 key=$2
  jq -Rc --arg key "$key" 'fromjson? // empty | select(.key != $key)' "$src" > "$src.tmp" 2>/dev/null \
    && mv -f "$src.tmp" "$src" && return 0
  rm -f "$src.tmp"
  return 1
}

# Each move writes the destination first and only then removes the source,
# and stops at the first failure: worst case an entry is in both lists,
# never in neither. Exit 2 = key not found, 1 = I/O failure.
dismiss_key() {
  local key=$1 line now
  line=$(take_line "$archive" "$key")
  [[ -n $line ]] || return 2
  now=$(now_ms)
  printf '%s\n' "$line" | jq -c --argjson trashedAt "$now" '. + {trashedAt: $trashedAt}' >> "$trash" || return 1
  strip_key "$archive" "$key"
}

restore_key() {
  local key=$1 line
  line=$(take_line "$trash" "$key")
  [[ -n $line ]] || return 2
  printf '%s\n' "$line" | jq -c 'del(.trashedAt)' >> "$archive" || return 1
  strip_key "$trash" "$key"
}

purge_key() {
  local key=$1
  have_key_in "$trash" "$key" || return 2
  strip_key "$trash" "$key" || return 1
  drop_images "$key"
}

clear_all() {
  local now
  now=$(now_ms)
  [[ -s $archive ]] || return 0
  jq -Rc --argjson trashedAt "$now" 'fromjson? // empty | objects | . + {trashedAt: $trashedAt}' \
    "$archive" > "$archive.trashing" 2>/dev/null || { rm -f "$archive.trashing"; return 1; }
  cat "$archive.trashing" >> "$trash" || { rm -f "$archive.trashing"; return 1; }
  rm -f "$archive.trashing"
  : > "$archive"
}

empty_trash() {
  local key keys
  keys=$(jq -Rr 'fromjson? // empty | .key // empty' "$trash" 2>/dev/null) || return 1
  : > "$trash" || return 1
  while IFS= read -r key; do
    [[ -n $key ]] || continue
    drop_images "$key"
  done <<< "$keys"
}

cmd_dismiss() {
  ensure_store
  local key=${1:-}
  valid_key "$key" || die "dismiss needs a key"
  local rc=0
  with_lock dismiss_key "$key" || rc=$?
  case $rc in
    0) printf '{"ok":true,"dismissed":%s}\n' "$(json_string "$key")" ;;
    2) die "not in history" ;;
    *) die "cannot write $store" ;;
  esac
}

cmd_restore() {
  ensure_store
  local key=${1:-}
  valid_key "$key" || die "restore needs a key"
  local rc=0
  with_lock restore_key "$key" || rc=$?
  case $rc in
    0) printf '{"ok":true,"restored":%s}\n' "$(json_string "$key")" ;;
    2) die "not in trash" ;;
    *) die "cannot write $store" ;;
  esac
}

cmd_purge() {
  ensure_store
  local key=${1:-}
  valid_key "$key" || die "purge needs a key"
  local rc=0
  with_lock purge_key "$key" || rc=$?
  case $rc in
    0) printf '{"ok":true,"purged":%s}\n' "$(json_string "$key")" ;;
    2) die "not in trash" ;;
    *) die "cannot write $store" ;;
  esac
}

cmd_clear() {
  ensure_store
  with_lock clear_all || die "cannot write $store"
  printf '{"ok":true,"cleared":true}\n'
}

cmd_empty_trash() {
  ensure_store
  with_lock empty_trash || die "cannot write $store"
  printf '{"ok":true,"emptied":true}\n'
}

cmd_seen() {
  ensure_store
  local stamp
  if [[ $# -gt 0 && -n ${1:-} ]]; then
    [[ ${1:-} =~ ^[0-9]{1,16}$ ]] || die "seen needs a millisecond stamp"
    printf '%s\n' "$1" > "$seen_file" || die "cannot write $seen_file"
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
  printf '%s' "$patch" | jq -e 'type == "object"' >/dev/null 2>&1 || die "settings patch must be a JSON object"
  with_lock merge_settings "$patch" || die "cannot save settings"
  cmd_settings_get
}

merge_settings() {
  local patch=$1
  jq -c --argjson patch "$patch" --argjson shared "$(defaults_config | jq -c .)" '
    def S: $shared;
    def clamp(v; lo; hi; fb):
      ((v | tonumber? // fb) | if . < lo then lo elif . > hi then hi else . end);
    def clamp_named(name; v):
      S.limits[name] as $l | clamp(v; $l.min; $l.max; $l.fallback);
    def sound:
      (S.soundAliases[.] // .) as $id
      | if (S.sounds | map(.id) | index($id)) != null then $id else S.defaults.defaultSound end;
    def pick_enum(name):
      . as $v
      | if (S.enums[name] | index($v)) != null then $v else S.defaults[name] end;
    def sounds(obj):
      (obj // {})
      | to_entries
      | map(select(.key | test("^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$")))
      | map({key: .key[0:64], value: (.value | tostring | sound)})
      | from_entries;
    (S.defaults + .) as $cur
    # A key in the patch wins unless it is null; `//` would also skip false.
    | def val(k): if $patch[k] != null then $patch[k] else $cur[k] end;
      def as_bool(k):
        val(k) as $v | if $v == true or $v == false then $v else S.defaults[k] end;
      {
        displayLimit: clamp_named("displayLimit"; val("displayLimit")),
        keepDays: clamp_named("keepDays"; val("keepDays")),
        maxItems: clamp_named("maxItems"; val("maxItems")),
        trashDays: clamp_named("trashDays"; val("trashDays")),
        autoHideMs: clamp_named("autoHideMs"; val("autoHideMs")),
        soundEnabled: as_bool("soundEnabled"),
        defaultSound: (val("defaultSound") | tostring | sound),
        soundLow: (val("soundLow") | tostring | sound),
        soundNormal: (val("soundNormal") | tostring | sound),
        soundCritical: (val("soundCritical") | tostring | sound),
        muteSoundWhenDnd: as_bool("muteSoundWhenDnd"),
        appSounds: sounds(val("appSounds")),
        badge: (val("badge") | tostring | pick_enum("badge")),
        clickAction: (val("clickAction") | tostring | pick_enum("clickAction")),
        showBody: as_bool("showBody"),
        showPreview: as_bool("showPreview")
      }
  ' "$settings_file" > "$settings_file.tmp" 2>/dev/null && mv -f "$settings_file.tmp" "$settings_file" && return 0
  rm -f "$settings_file.tmp"
  return 1
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
  local id=${1:-}
  [[ -n $id ]] || { printf '%s' ""; return; }
  defaults_config | jq -r --arg id "$id" '
    ( .soundAliases[$id] // $id ) as $event
    | if $event == "mute" then empty
      elif (.sounds | map(.id) | index($event)) != null then $event
      else empty end
  '
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
  sync) shift; set_engine "${1:-legacy}"; quiet=1; cmd_sync; printf '{"ok":true,"synced":true}\n' ;;
  watch) shift; cmd_watch "${1:-legacy}" ;;
  capture) shift; cmd_capture "${1:-}" ;;
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
  prune) shift; ensure_store; with_lock prune || die "cannot write $store"; printf '{"ok":true,"pruned":true}\n' ;;
  *)
    cat >&2 <<'USAGE'
yoyo.notification-center store

  watch [ENGINE]     follow Omarchy notifications and archive them
  sync [ENGINE]      catch up, then prune
                     ENGINE: legacy (4.0, default), omapager (4.5), auto
  capture KEY        omapager: file captures/KEY.png as KEY's picture
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
