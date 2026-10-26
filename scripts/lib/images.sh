# shellcheck shell=bash
# Picture copies in the store (images/KEY-SLOT.EXT): checked, size-capped,
# never followed outside a real file. Sourced by backend.sh.

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
