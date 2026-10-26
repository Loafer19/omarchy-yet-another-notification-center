# shellcheck shell=bash
# Omarchy 4.0.x: one JSON file per notification in notifications/ (on
# screen) and notifications/history/. Sourced by backend.sh.

ingest_file() {
  local file=$1 announce_existing=${2:-0}
  local key entry icon_copy="" image_copy="" preview_copy=""
  is_under "$file" "$src_dir" || is_under "$file" "$src_history" || return 0
  key=$(basename -- "$file"); key=${key%.json}
  valid_key "$key" || return 0
  if have_key "$key"; then
    (( announce_existing )) && grep -F "\"key\":\"$key\"" "$archive" | head -n 1
    return 0
  fi
  legacy_file_ok "$file" || return 0
  legacy_pictures "$file" "$key"
  entry=$(jq -c --arg key "$key" --arg appIcon "$icon_copy" --arg image "$image_copy" \
      --arg preview "$preview_copy" -f "$lib/legacy-entry.jq" "$file" 2>/dev/null) || return 0
  [[ -n $entry ]] || return 0

  printf '%s\n' "$entry" >> "$archive"
  printf '%s\n' "$entry"
}

# A notification file worth reading: non-empty, at most 256 KiB, valid JSON.
legacy_file_ok() {
  local file=$1 size
  [[ -s $file ]] || return 1
  size=$(stat -c%s -- "$file" 2>/dev/null || echo 0)
  (( size > 0 && size <= 262144 )) || return 1
  jq -e . "$file" >/dev/null 2>&1
}

# Copies the pictures of notification FILE for KEY into the store and sets
# the caller's icon_copy, image_copy and preview_copy.
legacy_pictures() {
  local file=$1 key=$2 app_icon image_src exec_src file_src
  app_icon=$(jq -r '.appIcon // ""' "$file")
  image_src=$(jq -r '.image // ""' "$file")
  exec_src=$(jq -c '.execArgv // .exec // empty' "$file" 2>/dev/null || true)
  if is_path "$app_icon"; then
    icon_copy=$(copy_image "$app_icon" "$key" "appIcon")
  else
    icon_copy=$(themed_icon "$app_icon")
  fi
  is_path "$image_src" && image_copy=$(copy_image "$image_src" "$key" "image")
  file_src=$(preview_source "$exec_src")
  if (( previews )) && [[ -n $file_src ]]; then
    preview_copy=$(copy_image "$file_src" "$key" "preview")
  fi
  return 0
}

sync_all() {
  local file
  for file in "$src_history"/*.json "$src_dir"/*.json; do
    [[ -e $file ]] || continue
    ingest_file "$file"
  done
}
