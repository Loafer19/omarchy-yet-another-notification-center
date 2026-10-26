# shellcheck shell=bash
# Omarchy 4.0.x: one JSON file per notification in notifications/ (on
# screen) and notifications/history/. Sourced by backend.sh.

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
