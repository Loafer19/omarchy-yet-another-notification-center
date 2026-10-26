#!/usr/bin/env bash
# Render the marketplace/README previews offscreen with made-up data:
#   tools/render-previews.sh [OUT_DIR]      (default: the repo root)
# Runs the real Service.qml and Panel.qml in Quickshell (QT_QPA_PLATFORM=
# offscreen) on a throwaway XDG_STATE_HOME filled by tests/preview/fixture.sh
# with invented notifications, so nothing from this machine ends up in the
# images and the real history is never read. Needs qs, jq, magick and the
# Omarchy shell (Commons, Ui); skips cleanly without them. Colors follow the
# active Omarchy theme.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(mkdir -p "${1:-$root}" && cd "${1:-$root}" && pwd)
shell_dir=${OMARCHY_PATH:-/usr/share/omarchy}/shell
for tool in qs jq magick; do
  command -v "$tool" >/dev/null 2>&1 || { echo "SKIP  render-previews (no $tool)"; exit 0; }
done
[[ -d $shell_dir/Ui && -d $shell_dir/Commons ]] || { echo "SKIP  render-previews (no Omarchy shell at $shell_dir)"; exit 0; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/nc-previews.XXXXXX")
# The service starts a store watcher (inotifywait) that outlives qs; stop
# everything still running from the temp dir before the next render.
reap() {
  pkill -f -- "$tmp/" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f -- "$tmp/" >/dev/null || return 0; sleep 0.2; done
  pkill -9 -f -- "$tmp/" 2>/dev/null || true
}
trap 'reap; rm -rf "$tmp"' EXIT
cfg=$tmp/cfg
mkdir -p "$cfg/plugin"
ln -s "$shell_dir/Commons" "$cfg/Commons"
# Ui is Omarchy's, except KeyboardPanel: a layer-shell window cannot map
# offscreen, so a stub draws the same card in a plain Item.
mkdir -p "$cfg/Ui"
for f in "$shell_dir"/Ui/*; do ln -s "$f" "$cfg/Ui/"; done
rm -f "$cfg/Ui/KeyboardPanel.qml"
cp "$root/tests/preview/KeyboardPanel.qml" "$cfg/Ui/KeyboardPanel.qml"
tar -C "$root" --exclude=.git --exclude='./preview*.png' --exclude='./docs' -cf - . | tar -C "$cfg/plugin" -xf -
cp "$root/tests/preview/shell.qml" "$cfg/shell.qml"
st=$tmp/state
mkdir -p "$out/docs"

render() { # render FILE ENTRY [VAR=VALUE ...]
  local name=$1 file=$out/$1 entry=$cfg/$2 log=$tmp/${1//\//_}.log
  shift 2
  rm -rf "$st"; bash "$root/tests/preview/fixture.sh" "$st"
  env "$@" XDG_STATE_HOME="$st" YANC_SRC_DIR="$st/omarchy/notifications" \
    YANC_STORE="$st/omarchy/yoyo.notification-center" PREVIEW_OUT="$file" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    QT_SCALE_FACTOR=${PREVIEW_SCALE:-2} timeout 40 qs -p "$entry" > "$log" 2>&1 || true
  reap
  if grep -q '^.*saved ' "$log" && [[ -s $file ]]; then
    echo "saved $file"
  else
    echo "FAIL  render $name" >&2; tail -n 20 "$log" >&2; return 1
  fi
}
render preview.png shell.qml PREVIEW_TAB=history
render docs/trash.png shell.qml PREVIEW_TAB=trash
render docs/settings.png shell.qml PREVIEW_TAB=settings
