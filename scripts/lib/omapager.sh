# shellcheck shell=bash
# Omarchy 4.5 (Omapager): notifications/live.json (on screen, oldest first)
# and notifications/history.json (closed, newest first). Rows carry key, app,
# appIcon (a theme name), summary, body, glyph, urgency and ts (seconds).
# Pictures are never persisted there: the panel saves a live toast's picture
# (captures/KEY.png) and `capture` files it. Sourced by backend.sh.

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
