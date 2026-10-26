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
  local not_played='{"ok":true,"played":false}'
  event=$(sound_event "$id")
  [[ -n $event ]] && valid_sound "$event" && [[ $event != mute ]] \
    || { printf '%s\n' "$not_played"; return 0; }
  file="/usr/share/sounds/freedesktop/stereo/${event}.oga"
  if [[ -f $file ]] && command -v pw-play >/dev/null 2>&1; then
    pw-play -- "$file" >/dev/null 2>&1 &
  elif command -v canberra-gtk-play >/dev/null 2>&1; then
    canberra-gtk-play -i "$event" >/dev/null 2>&1 &
  else
    printf '%s\n' "$not_played"; return 0
  fi
  printf '{"ok":true,"played":true,"id":%s}\n' "$(json_string "$event")"
}
