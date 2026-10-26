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
# Builtins only up to the jq check, so a broken PATH still gets a JSON error.
here=${BASH_SOURCE[0]%/*}
[[ $here == "${BASH_SOURCE[0]}" ]] && here=.
plugin_root=$(cd "$here/.." && pwd)
lib=$plugin_root/scripts/lib
# shellcheck source=lib/common.sh
. "$lib/common.sh"
command -v jq >/dev/null 2>&1 || die "jq is not installed"
[[ -f $defaults_js ]] || die "defaults.js is missing"
# shellcheck source=lib/images.sh
. "$lib/images.sh"
# shellcheck source=lib/legacy.sh
. "$lib/legacy.sh"
# shellcheck source=lib/omapager.sh
. "$lib/omapager.sh"
# shellcheck source=lib/store.sh
. "$lib/store.sh"
# shellcheck source=lib/watch.sh
. "$lib/watch.sh"
# shellcheck source=lib/settings.sh
. "$lib/settings.sh"
# shellcheck source=lib/sound.sh
. "$lib/sound.sh"
# shellcheck source=lib/seed.sh
. "$lib/seed.sh"

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
