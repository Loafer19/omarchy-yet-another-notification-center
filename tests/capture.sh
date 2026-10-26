#!/usr/bin/env bash
# Omarchy 4.5 live captures, end to end: the real Service.qml and backend in
# Quickshell (offscreen) on a private D-Bus whose notification server plays
# Omapager (tests/qml/capture.qml). Real senders (gdbus) send an inline
# image-data picture with actions, an image-path picture whose file is gone
# by the time the toast closes (Chromium's temp avatars), a secret, one under
# Do Not Disturb (released at once) and one with "Show pictures" off. Checks
# what lands in the archive, the saved pixels, and that a sender action runs
# while the toast is up and not after. Temp HOME, store and bus; nothing
# touches the real session or toasts.
#   tests/capture.sh [PLUGIN_DIR]   (default: this checkout)
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "${1:-$here/..}" && pwd)
for tool in qs gdbus dbus-run-session dbus-monitor inotifywait magick jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "SKIP  capture (no $tool)"; exit 0; }
done
tmp=$(mktemp -d /tmp/yanc-capture.XXXXXX)
trap 'pkill -f "inotifywait.*$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
pass=0; fail=0
ok() { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
no() { printf 'FAIL  %s\n      %s\n' "$1" "${2:-}"; fail=$((fail + 1)); }
expect() { if [[ $2 == "$3" ]]; then ok "$1"; else no "$1" "got: $2 | want: $3"; fi; }

cfg=$tmp/cfg st=$tmp/state
store=$st/omarchy/yoyo.notification-center
mkdir -p "$cfg" "$st/omarchy/notifications" "$store"
ln -s "$src" "$cfg/nc"
cp "$here/qml/capture.qml" "$cfg/shell.qml"
printf '[]\n' > "$st/omarchy/notifications/live.json"
printf '[]\n' > "$st/omarchy/notifications/history.json"
# A bus with nothing to activate: no portals or other services start.
cat > "$tmp/bus.conf" <<CONF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:path=$tmp/bus</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
CONF
magick -size 6x3 xc:'#00ff00' "$tmp/avatar.png"

cat > "$tmp/inner.sh" <<'INNER'
set -u
tmp=$1 cfg=$2
notify() { # notify SUMMARY ACTIONS HINTS -> id
  gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.Notify test 0 "" "$1" "body of $1" "$2" "$3" 0 \
    | sed -n 's/^(uint32 \([0-9]*\),)$/\1/p'
}
ctl() { notify "CTL $*" '[]' '{}' > /dev/null; sleep 0.4; }
dbus-monitor --session "type='signal',interface='org.freedesktop.Notifications'" > "$tmp/signals" 2>/dev/null &
mon=$!
HOME=$tmp/home XDG_STATE_HOME=$tmp/state YANC_SRC_DIR=$tmp/state/omarchy/notifications \
  YANC_STORE=$tmp/state/omarchy/yoyo.notification-center QT_QPA_PLATFORM=offscreen \
  timeout 60 qs -p "$cfg" > "$tmp/qs.log" 2>&1 &
qsp=$!
for _ in $(seq 1 100); do grep -q READY "$tmp/qs.log" && break; sleep 0.1; done
sleep 0.5
# 4x2 RGBA: red, then blue; rowstride 16.
px=$(printf 'byte 0xff, byte 0x00, byte 0x00, byte 0xff, %.0s' 1 2 3 4; printf 'byte 0x00, byte 0x00, byte 0xff, byte 0xff, %.0s' 1 2 3 4)
notify Pic '["default","Open","reply","Reply"]' "{'image-data': <(4, 2, 16, true, 8, 4, [${px%, }])>}" > "$tmp/pic.id"
notify Path '["default","Open"]' "{'image-path': <'$tmp/avatar.png'>}" > /dev/null
notify "Your code 482913" '[]' "{'image-data': <(4, 2, 16, true, 8, 4, [${px%, }])>}" > /dev/null
sleep 1.5
ctl actions Pic
ctl invoke Pic default
ctl invoke Pic reply
rm -f "$tmp/avatar.png"   # the sender drops its temp file
ctl expire Path
ctl dnd on
notify Quiet '[]' "{'image-data': <(4, 2, 16, true, 8, 4, [${px%, }])>}" > /dev/null
sleep 0.5
ctl dnd off
ctl previews off
sleep 1
notify Off '[]' "{'image-data': <(4, 2, 16, true, 8, 4, [${px%, }])>}" > /dev/null
sleep 3
ctl end
wait "$qsp"
kill "$mon" 2>/dev/null; wait "$mon" 2>/dev/null
INNER
dbus-run-session --config-file="$tmp/bus.conf" -- bash "$tmp/inner.sh" "$tmp" "$cfg"
log=$(grep -E 'READY|NOTIFIED|ACTIONS|INVOKE|CLOSED|ARCHIVED|PATCHED|END|yoyo|ReferenceError|TypeError|rror' "$tmp/qs.log")
printf '%s\n' "$log" | sed 's/^/      /'

a=$store/archive.jsonl
img() { jq -r --arg s "$1" 'select(.summary == $s) | .image' "$a" 2>/dev/null | sed 's#^file://##'; }
expect "service found the fake Omapager and the bar host" "$(grep -o 'READY.*' <<< "$log" | head -n1)" "READY engine=omapager host=true"
pic=$(img Pic)
expect "inline image-data picture archived" "$pic" "$store/images/$(jq -r 'select(.summary == "Pic") | .key' "$a")-image.png"
if [[ -f $pic ]]; then
  expect "...pixels as sent (4x2, red over blue)" "$(magick "$pic" -format '%wx%h %[pixel:p{0,0}] %[pixel:p{0,1}]' info:)" "4x2 srgba(255,0,0,1) srgba(0,0,255,1)"
else no "...pixels as sent" "no file"; fi
path=$(img Path)
if [[ -n $path && -f $path ]]; then
  expect "image-path picture kept after the sender deleted it (6x3 green)" "$(magick "$path" -format '%wx%h %[pixel:p{1,1}]' info:)" "6x3 srgba(0,255,0,1)"
else no "image-path picture kept after the sender deleted it" "image: '$path'"; fi
quiet=$(img Quiet)
if [[ -n $quiet && -f $quiet ]]; then ok "Do Not Disturb: picture saved though the toast was let go at once"
else no "Do Not Disturb: picture saved though the toast was let go at once" "image: '$quiet'"; fi
expect "secret: archived as the placeholder, no picture" \
  "$(jq -r 'select(.summary == "Verification notification") | .body + "|" + .image' "$a")" "[redacted]|"
expect "Show pictures off: no picture" "$(jq -r 'select(.summary == "Off") | .image' "$a")" ""
expect "nothing else in images/, nothing left in captures/" \
  "$(find "$store/images" -type f | wc -l) $(find "$store/captures" -type f 2>/dev/null | wc -l)" "3 0"
expect "live actions listed while the toast is up" "$(grep -o 'ACTIONS Pic .*' <<< "$log")" \
  'ACTIONS Pic [{"id":"default","text":"Open"},{"id":"reply","text":"Reply"}]'
expect "default action runs while the toast is up" "$(grep -o 'INVOKED Pic default .*' <<< "$log")" "INVOKED Pic default true"
expect "...not after it closed" "$(grep -o 'INVOKED Pic reply .*' <<< "$log")" "INVOKED Pic reply false"
pid=$(cat "$tmp/pic.id")
if grep -A2 'member=ActionInvoked' "$tmp/signals" | tr -s ' \n' ' ' | grep -q "uint32 $pid string \"default\""; then
  ok "the sender got ActionInvoked(default) on D-Bus"
else no "the sender got ActionInvoked(default) on D-Bus" "$(grep -A2 ActionInvoked "$tmp/signals" | tr -s ' \n' ' ')"; fi
expect "and only that one" "$(grep -c 'member=ActionInvoked' "$tmp/signals")" 1
if grep -qE 'ReferenceError|TypeError|Cannot invoke|unknown handle' "$tmp/qs.log"; then
  no "no QML errors" "$(grep -E 'ReferenceError|TypeError|Cannot invoke|unknown handle' "$tmp/qs.log" | head -n3)"
else ok "no QML errors"; fi

echo
printf 'RESULT  %d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
