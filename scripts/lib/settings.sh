# shellcheck shell=bash
# settings.json: the one copy of the plugin's settings, validated against
# defaults.js. Sourced by backend.sh.

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
  jq -c --argjson patch "$patch" --argjson shared "$(defaults_config | jq -c .)" \
    -f "$lib/settings.jq" "$settings_file" > "$settings_file.tmp" 2>/dev/null \
    && mv -f "$settings_file.tmp" "$settings_file" && return 0
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
