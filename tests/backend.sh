#!/usr/bin/env bash
# Fixture tests for scripts/backend.sh. Everything runs in a temp dir: HOME,
# XDG_STATE_HOME, the Omarchy source dir (YANC_SRC_DIR) and the store
# (YANC_STORE) all point there, and the sound players are stubs that only log
# their argv. Your real notifications and history are never read or written.
#   tests/backend.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
backend=$here/../scripts/backend.sh
tmp=$(mktemp -d /tmp/yanc-test.XXXXXX)
trap 'chmod -R u+rwX "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
pass=0; fail=0
ok() { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
no() { printf 'FAIL  %s\n      %s\n' "$1" "${2:-}"; fail=$((fail + 1)); }
expect() { if [[ $2 == "$3" ]]; then ok "$1"; else no "$1" "got: $2 | want: $3"; fi; }
expect_has() { if [[ $2 == *"$3"* ]]; then ok "$1"; else no "$1" "missing: $3 in: $2"; fi; }
exists() { if [[ -e $2 ]]; then ok "$1"; else no "$1" "gone: $2"; fi; }
gone() { if [[ ! -e $2 ]]; then ok "$1"; else no "$1" "still there: $2"; fi; }

bin=$tmp/bin; mkdir -p "$bin"
export CALLS=$tmp/calls.log
: > "$CALLS"
stub() { # stub NAME — logs its argv and exits 0
  # shellcheck disable=SC2016  # $* / $CALLS expand in the stub, not here
  printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "%s" "$*" >> "$CALLS"\n' "$1" > "$bin/$1"
  chmod +x "$bin/$1"
}
stub pw-play
stub canberra-gtk-play
export PATH=$bin:$PATH
export HOME=$tmp/home XDG_STATE_HOME=$tmp/state
export YANC_SRC_DIR=$tmp/src YANC_STORE=$tmp/store
unset YANC_SRC_HISTORY YANC_KEEP_DAYS YANC_MAX_ITEMS YANC_HISTORY_LIMIT YANC_TRASH_DAYS YANC_PREVIEWS YANC_NOW_MS
mkdir -p "$HOME" "$YANC_SRC_DIR/history"
store=$YANC_STORE; src=$YANC_SRC_DIR
B() { bash "$backend" "$@"; }
now=$(($(date +%s%N) / 1000000)); day=86400000
keys() { jq -r '.key' "$1" 2>/dev/null | LC_ALL=C sort | paste -sd' '; }
sorted() { printf '%s\n' "$@" | LC_ALL=C sort | paste -sd' '; }
note() { # note FILE KEY JSON-FIELDS — an Omarchy popup/history file
  printf '%s\n' "$3" > "$1/$2.json"
}
png() { magick -size 8x8 xc:'#336699' "$1" 2>/dev/null || printf '\x89PNG\r\n\x1a\n%s' "$(head -c 64 /dev/zero | tr '\0' x)" > "$1"; }

echo "== usage"
B >/dev/null 2>&1; expect "no command -> usage, exit 64" "$?" 64

echo "== settings"
expect "defaults when no file" "$(B settings-get | jq -c '[.displayLimit,.keepDays,.badge,.soundEnabled]')" '[50,30,"Dot",true]'
out=$(B settings-set '{"displayLimit":3,"keepDays":9999,"badge":"Huge","soundCritical":"warning","appSounds":{"Slack":"bell","../x":"bell"}}')
expect "settings-set clamps / validates" "$(jq -c '[.displayLimit,.keepDays,.badge,.soundCritical,.appSounds]' <<< "$out")" \
  '[10,365,"Dot","dialog-warning",{"Slack":"bell"}]'
expect "settings-set persisted" "$(jq -c .displayLimit "$store/settings.json")" 10
out=$(B settings-set 'not json' 2>/dev/null); rc=$?
expect "settings-set invalid JSON -> exit 1" "$rc" 1
expect "settings-set invalid JSON -> ok:false" "$(jq -c . <<< "$out")" '{"ok":false,"error":"invalid JSON"}'
expect "settings-set non-object refused" "$(B settings-set '[1]' 2>/dev/null)" '{"ok":false,"error":"settings patch must be a JSON object"}'
B settings-set '{"soundEnabled":false,"showPreview":false}' >/dev/null
expect "settings-set can turn booleans off (and keep them off)" \
  "$(B settings-set '{"badge":"Count"}' | jq -c '[.soundEnabled,.showPreview,.showBody,.badge]')" '[false,false,true,"Count"]'
B settings-set '{"displayLimit":50,"keepDays":30,"soundEnabled":true,"showPreview":true,"badge":"Dot"}' >/dev/null
expect "store files are private" "$(stat -c %a "$store" "$store/settings.json" | paste -sd' ')" "700 600"

echo "== ingest"
ts1=$((now - 3 * 60000)); ts2=$((now - 2 * 60000))
png "$tmp/icon.png"
note "$src/history" "1001-1" "$(jq -nc --argjson t "$ts1" '{app:"Slack",appIcon:"slack",summary:"Hello",body:"World",urgency:2,timestamp:$t}')"
note "$src/history" "1002-1" "$(jq -nc --argjson t "$ts2" --arg i "$tmp/icon.png" '{app:"Mail",appIcon:$i,summary:("S" * 300),body:"b",urgency:9,timestamp:$t}')"
note "$src" "$((now - 60000))-7" '{"app":"NoStamp","appIcon":"../../etc/passwd","summary":"x","urgency":"low"}'
note "$src" "1004-1" '{not json'
note "$src" "bad key!" '{"app":"x","timestamp":1}'
head -c 300000 /dev/zero | tr '\0' ' ' > "$src/1005-1.json"
before=$(find "$src" -type f -exec sha256sum {} + | sort)
out=$(B sync); rc=$?
expect "sync ok" "$rc:$out" '0:{"ok":true,"synced":true}'
expect "sync archived only valid, safe, small files" "$(keys "$store/archive.jsonl")" "$(sorted "$((now - 60000))-7" 1001-1 1002-1)"
expect "sync never writes into Omarchy's dirs" "$(find "$src" -type f -exec sha256sum {} + | sort)" "$before"
e=$(jq -c 'select(.key=="1002-1")' "$store/archive.jsonl")
expect "summary truncated to 240, urgency clamped" "$(jq -c '[(.summary|length),.urgency,.app]' <<< "$e")" '[240,2,"Mail"]'
expect_has "path icon copied into the store" "$(jq -r .appIcon <<< "$e")" "file://$store/images/1002-1-appIcon"
exists "copied icon exists" "$(jq -r .appIcon <<< "$e" | sed 's|^file://||')"
e=$(jq -c "select(.key==\"$((now - 60000))-7\")" "$store/archive.jsonl")
expect "unsafe themed icon dropped; timestamp from key; text urgency -> normal" \
  "$(jq -c '[.appIcon,.timestamp,.urgency]' <<< "$e")" "[\"\",$((now - 60000)),1]"
expect "themed icon name kept" "$(jq -r 'select(.key=="1001-1") | .appIcon' "$store/archive.jsonl")" slack
B sync >/dev/null
expect "sync is idempotent" "$(wc -l < "$store/archive.jsonl")" 3

echo "== list"
expect "list newest first" "$(B list | jq -r 'map(.key) | join(" ")')" "$((now - 60000))-7 1002-1 1001-1"
expect "list limit" "$(B list 1 | jq -r 'length')" 1
expect "list junk limit -> default" "$(B list abc | jq -r 'length')" 3
expect "trash-list empty" "$(B trash-list)" "[]"
expect "apps" "$(B apps | jq -c 'map(.app)')" '["Mail","NoStamp","Slack"]'

echo "== dismiss / restore / purge"
out=$(B dismiss 1001-1); expect "dismiss ok" "$out" '{"ok":true,"dismissed":"1001-1"}'
expect "dismissed -> trash with trashedAt" "$(jq -c 'select(.key=="1001-1") | (.trashedAt > 0)' "$store/trash.jsonl")" true
expect "dismissed gone from history" "$(keys "$store/archive.jsonl")" "$(sorted "$((now - 60000))-7" 1002-1)"
out=$(B dismiss 1001-1 2>/dev/null); rc=$?
expect "dismiss missing -> exit 1, ok:false" "$rc $out" '1 {"ok":false,"error":"not in history"}'
out=$(B dismiss '../etc' 2>/dev/null); rc=$?
expect "dismiss bad key refused" "$rc $out" '1 {"ok":false,"error":"dismiss needs a key"}'
expect "error also goes to stderr" "$(B dismiss nope 2>&1 >/dev/null)" "yoyo.notification-center: not in history"
out=$(B restore 1001-1); expect "restore ok" "$out" '{"ok":true,"restored":"1001-1"}'
expect "restored without trashedAt" "$(jq -c 'select(.key=="1001-1") | has("trashedAt")' "$store/archive.jsonl")" false
expect "restore missing" "$(B restore 1001-1 2>/dev/null)" '{"ok":false,"error":"not in trash"}'
B dismiss 1002-1 >/dev/null
icon=$(jq -r 'select(.key=="1002-1") | .appIcon' "$store/trash.jsonl" | sed 's|^file://||')
out=$(B purge 1002-1); expect "purge ok" "$out" '{"ok":true,"purged":"1002-1"}'
gone "purge deletes the copied pictures" "$icon"
expect "purge missing" "$(B purge 1002-1 2>/dev/null)" '{"ok":false,"error":"not in trash"}'

echo "== clear / empty trash"
png "$tmp/icon2.png"
note "$src/history" "1003-1" "$(jq -nc --argjson t "$now" --arg i "$tmp/icon2.png" '{app:"Pic",appIcon:$i,summary:"p",timestamp:$t}')"
B sync >/dev/null
n=$(wc -l < "$store/archive.jsonl")
expect "clear ok" "$(B clear)" '{"ok":true,"cleared":true}'
expect "clear empties history" "$(wc -c < "$store/archive.jsonl")" 0
expect "clear moves every row to trash" "$(jq -s 'map(select(.trashedAt > 0)) | length' "$store/trash.jsonl")" "$n"
icon=$(jq -r 'select(.key=="1003-1") | .appIcon' "$store/trash.jsonl" | sed 's|^file://||')
exists "trashed picture still kept" "$icon"
expect "empty-trash ok" "$(B empty-trash)" '{"ok":true,"emptied":true}'
expect "empty-trash empties trash" "$(wc -c < "$store/trash.jsonl")" 0
gone "empty-trash deletes trashed pictures" "$icon"
B sync >/dev/null
# Known behaviour: Omarchy's own files are still there, so a later sync
# imports them again. Pinned here so a change to it is deliberate.
expect "sync re-imports source files still present after empty-trash" "$(wc -l < "$store/archive.jsonl")" 4

echo "== failures leave data intact"
cp "$store/archive.jsonl" "$tmp/archive.before"
mv "$store/trash.jsonl" "$tmp/trash.saved"; mkdir "$store/trash.jsonl"   # trash cannot be written
out=$(B clear 2>/dev/null); rc=$?
expect "clear fails when trash is unwritable" "$rc $(jq -r .ok <<< "$out")" "1 false"
expect "history untouched after failed clear" "$(cat "$store/archive.jsonl")" "$(cat "$tmp/archive.before")"
out=$(B dismiss 1001-1 2>/dev/null); rc=$?
expect "dismiss fails when trash is unwritable" "$rc $(jq -r .error <<< "$out")" "1 cannot write $store"
expect "history untouched after failed dismiss" "$(cat "$store/archive.jsonl")" "$(cat "$tmp/archive.before")"
rmdir "$store/trash.jsonl"; mv "$tmp/trash.saved" "$store/trash.jsonl"
cp "$store/settings.json" "$tmp/settings.before"
mkdir "$store/settings.json.tmp"
out=$(B settings-set '{"badge":"Count"}' 2>/dev/null); rc=$?
expect "settings-set fails when it cannot write" "$rc $out" '1 {"ok":false,"error":"cannot save settings"}'
expect "settings untouched" "$(cat "$store/settings.json")" "$(cat "$tmp/settings.before")"
rmdir "$store/settings.json.tmp"
mkdir "$store/seen"
out=$(B seen 123 2>/dev/null); rc=$?
expect "seen fails when it cannot write" "$rc $(jq -r .ok <<< "$out")" "1 false"
rmdir "$store/seen"
out=$(PATH=/usr/bin/nonexistent:/nonexistent "$(command -v bash)" "$backend" list 2>/dev/null); rc=$?
expect "missing jq -> exit 1 with JSON error (no jq needed)" "$rc $out" '1 {"ok":false,"error":"jq is not installed"}'

echo "== seen / unread"
expect "seen default" "$(B seen)" '{"ok":true,"seen":0}'
expect "unread = all" "$(B unread)" '{"ok":true,"unread":4}'
B seen "$((now - 90000))" >/dev/null
expect "unread after seen" "$(B unread | jq .unread)" 2
expect "seen rejects junk" "$(B seen abc 2>/dev/null)" '{"ok":false,"error":"seen needs a millisecond stamp"}'

echo "== sounds (stubs)"
: > "$CALLS"
out=$(B play-sound warning)
if [[ -f /usr/share/sounds/freedesktop/stereo/dialog-warning.oga ]]; then
  expect "play-sound alias -> pw-play" "$out" '{"ok":true,"played":true,"id":"dialog-warning"}'
  sleep 0.2; expect_has "pw-play called with the freedesktop file" "$(cat "$CALLS")" "pw-play -- /usr/share/sounds/freedesktop/stereo/dialog-warning.oga"
else
  expect "play-sound alias -> canberra" "$out" '{"ok":true,"played":true,"id":"dialog-warning"}'
fi
expect "play-sound mute" "$(B play-sound mute)" '{"ok":true,"played":false}'
expect "play-sound unknown" "$(B play-sound '../../x')" '{"ok":true,"played":false}'

echo "== prune"
d=$tmp/prune; mkdir -p "$d"
YANC_STORE=$d B settings-set '{"keepDays":2,"trashDays":1,"displayLimit":10}' >/dev/null
for i in $(seq 1 14); do
  jq -nc --arg k "p$i" --argjson t "$((now - (15 - i) * 60000))" '{key:$k,app:"A",timestamp:$t}'
done > "$d/archive.jsonl"
jq -nc --argjson t "$((now - 3 * day))" '{key:"old",app:"A",timestamp:$t}' >> "$d/archive.jsonl"
printf '%s\n' 'not json' >> "$d/archive.jsonl"
jq -nc --argjson t "$((now - 2 * day))" '{key:"stale",timestamp:1,trashedAt:$t}' > "$d/trash.jsonl"
jq -nc --argjson t "$((now - 60000))" '{key:"fresh",timestamp:1,trashedAt:$t}' >> "$d/trash.jsonl"
mkdir -p "$d/images"; png "$d/images/stale-image.png"; png "$d/images/fresh-image.png"
expect "prune ok" "$(YANC_STORE=$d B prune)" '{"ok":true,"pruned":true}'
expect "history capped at displayLimit (newest kept)" "$(jq -r .key "$d/archive.jsonl" | paste -sd' ')" "p5 p6 p7 p8 p9 p10 p11 p12 p13 p14"
expect "older than keepDays deleted, not trashed" "$(grep -c '"old"' "$d/trash.jsonl")" 0
expect "overflow moved to trash" "$(jq -r 'select(.key|startswith("p")) | .key' "$d/trash.jsonl" | paste -sd' ')" "p1 p2 p3 p4"
expect "trash older than trashDays purged" "$(jq -r .key "$d/trash.jsonl" | grep -c stale)" 0
gone "purged trash pictures deleted" "$d/images/stale-image.png"
exists "fresh trash pictures kept" "$d/images/fresh-image.png"

echo "== seed (demo data stays in the temp store)"
s=$tmp/seed
expect "seed" "$(YANC_STORE=$s B seed 5)" '{"ok":true,"seeded":5}'
expect "seed sorted oldest first" "$(jq -s '[.[].timestamp] == ([.[].timestamp] | sort)' "$s/archive.jsonl")" true

echo "== watch"
if command -v inotifywait >/dev/null 2>&1; then
  w=$tmp/watch; mkdir -p "$w/src/history"
  YANC_STORE=$w/store YANC_SRC_DIR=$w/src timeout 6 bash "$backend" watch > "$w/out" 2>/dev/null &
  wpid=$!
  sleep 1.5
  jq -nc --argjson t "$now" '{app:"Live",summary:"new",timestamp:$t}' > "$w/src/2001-1.json.part"
  mv "$w/src/2001-1.json.part" "$w/src/2001-1.json"
  for _ in $(seq 1 30); do grep -q 2001-1 "$w/out" 2>/dev/null && break; sleep 0.1; done
  kill "$wpid" 2>/dev/null; wait "$wpid" 2>/dev/null
  pkill -f "inotifywait.*$w/src" 2>/dev/null
  expect "watch prints the new entry" "$(jq -r .key "$w/out" 2>/dev/null | head -n1)" 2001-1
  expect "watch archived it" "$(jq -r .key "$w/store/archive.jsonl")" 2001-1
else
  echo "SKIP  watch (no inotifywait)"
fi

echo
printf 'RESULT  %d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
