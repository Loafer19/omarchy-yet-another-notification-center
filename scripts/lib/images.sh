# shellcheck shell=bash
# Picture copies in the store (images/KEY-SLOT.EXT): checked, size-capped,
# never followed outside a real file. Sourced by backend.sh.

copy_image() {
  local src=$1 key=$2 slot=$3
  valid_key "$key" || { printf '%s' ""; return; }
  case $slot in
    appIcon|image|preview) ;;
    *) printf '%s' ""; return ;;
  esac
  src=$(image_source "$src") || { printf '%s' ""; return; }
  command -v file >/dev/null 2>&1 || { printf '%s' ""; return; }
  store_image "$src" "$key" "$slot" || { printf '%s' ""; return; }
}

# The real path of picture SRC (a path or file:// URL), if it is a readable
# file and the path has no "..".
image_source() {
  local src=${1#file://}
  [[ $src == /* ]] || return 1
  [[ $src == *..* ]] && return 1
  src=$(realpath -e -- "$src" 2>/dev/null) || return 1
  [[ -f $src && -r $src ]] || return 1
  printf '%s' "$src"
}

# The extension for a picture's MIME type; fails for anything but an image.
image_ext() {
  case $1 in
    image/jpeg) printf '.jpg' ;;
    image/png) printf '.png' ;;
    image/webp) printf '.webp' ;;
    image/gif) printf '.gif' ;;
    *) return 1 ;;
  esac
}

# Copies SRC (at most 5 MiB, an image) to images/KEY-SLOT.EXT and prints its
# file:// URL; previews are scaled down to 720 px when magick is there.
store_image() {
  local src=$1 key=$2 slot=$3 tmp dest ext
  tmp="$images/$key-$slot.tmp"
  if ! timeout 5 head -c 5242881 -- "$src" > "$tmp" 2>/dev/null \
      || (( $(stat -c%s -- "$tmp" 2>/dev/null || echo 0) > 5242880 )); then
    rm -f -- "$tmp"; return 1
  fi
  ext=$(image_ext "$(file -bL --mime-type -- "$tmp" 2>/dev/null || true)") \
    || { rm -f -- "$tmp"; return 1; }
  if [[ $slot == preview ]] && command -v magick >/dev/null 2>&1; then
    timeout 5 magick "$tmp" -auto-orient -resize '720x720>' -quality 82 "$tmp.resized" 2>/dev/null \
      && mv -f -- "$tmp.resized" "$tmp"
    rm -f -- "$tmp.resized"
  fi
  dest="$images/$key-$slot$ext"
  mv -f -- "$tmp" "$dest"
  printf 'file://%s' "$dest"
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
