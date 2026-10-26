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
