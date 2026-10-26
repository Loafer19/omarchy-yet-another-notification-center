# shellcheck shell=bash
# Notification sounds (freedesktop event names). Sourced by backend.sh.

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
