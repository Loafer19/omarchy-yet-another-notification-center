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

  # watcher_of PID — the inotifywait watching $w/src that PID started, if any
  # (directly, or through setpriv/a subshell).
  watcher_of() {
    local p pp
    for p in $(pgrep -f "inotifywait .*$w/src"); do
      pp=$(ps -o ppid= -p "$p" | tr -d ' ')
      [[ $pp == "$1" || $(ps -o ppid= -p "$pp" 2>/dev/null | tr -d ' ') == "$1" ]] && echo "$p"
    done
    return 0
  }
  has_watcher() { [[ -n $(watcher_of "$1") ]]; }
  dead() { local p; for p; do [[ -z $p ]] || ! kill -0 "$p" 2>/dev/null || return 1; done; }
  wait_for() { local n=$1; shift; for _ in $(seq 1 "$n"); do "$@" && return 0; sleep 0.1; done; return 1; }
  for mode in pdeathsig guard; do
    unset YANC_NO_PDEATHSIG; [[ $mode == guard ]] && export YANC_NO_PDEATHSIG=1
    YANC_STORE=$w/store YANC_SRC_DIR=$w/src bash "$backend" watch > /dev/null 2>&1 &
    wpid=$!
    wait_for 50 has_watcher "$wpid"
    iw=$(watcher_of "$wpid")
    kill -9 "$wpid"; wait "$wpid" 2>/dev/null
    if [[ -n $iw ]] && wait_for 40 dead "$iw"; then ok "SIGKILLed backend takes its inotifywait along ($mode)"
    else no "SIGKILLed backend takes its inotifywait along ($mode)" "watcher=${iw:-none} still alive: $(pgrep -af "inotifywait .*$w/src")"; fi
    pkill -f "inotifywait .*$w/src" 2>/dev/null
  done
  unset YANC_NO_PDEATHSIG
  # Its parent SIGKILLed (the shell dying): the backend notices and leaves.
  # shellcheck disable=SC2016  # $1/$2/$! belong to the inner bash
  YANC_WATCH_CHECK=1 YANC_STORE=$w/store YANC_SRC_DIR=$w/src setsid bash -c 'bash "$1" watch >/dev/null 2>&1 & echo $! > "$2"; wait' _ "$backend" "$w/bpid" &
  holder=$!
  wait_for 50 test -s "$w/bpid"; bpid=$(cat "$w/bpid")
  wait_for 50 has_watcher "$bpid"; iw=$(watcher_of "$bpid")
  kill -9 "$holder"; wait "$holder" 2>/dev/null
  if [[ -n $iw ]] && wait_for 50 dead "$bpid" "$iw"; then ok "orphaned backend exits and its watcher goes"
  else no "orphaned backend exits and its watcher goes" "backend $bpid / watcher ${iw:-none} still alive"; kill "$bpid" 2>/dev/null; fi
  pkill -f "inotifywait .*$w/src" 2>/dev/null
else
  echo "SKIP  watch (no inotifywait)"
fi

echo "== omapager (Omarchy 4.5: live.json / history.json)"
fx=$here/fixtures/omapager
o=$tmp/omapager
O() { YANC_SRC_DIR=$o/src YANC_STORE=$o/store bash "$backend" "$@"; }
mkdir -p "$o/src" "$o/home/Pictures/Screenshots"
# The fixture's screenshot path made real, so a picture *could* be copied.
shot=$o/home/Pictures/Screenshots/screenshot-2026-10-26_10-45-13-google-chrome.png
printf '\x89PNG\r\n\x1a\n\0\0\0\rIHDR\0\0\0\1\0\0\0\1\x08\x06\0\0\0\x1f\x15\xc4\x89\0\0\0\rIDATx\x9cc\xf8\xff\xff?\0\x05\xfe\x02\xfe\xa7\x35\x81\x84\0\0\0\0IEND\xaeB`\x82' > "$shot"
sed "s#/home/user/#$o/home/#g" "$fx/history.json" > "$o/src/history.json"
cp "$fx/live.json" "$fx/quiet.json" "$o/src/"
expect "sync omapager" "$(O sync omapager)" '{"ok":true,"synced":true}'
a=$o/store/archive.jsonl
expect "every history and live row archived once" "$(wc -l < "$a")" 11
expect "oldest first (history reversed, then live)" "$(jq -r .key "$a" | paste -sd' ')" \
  "nmvo4b91g11 nmvozwuon1 nmvp0h2bc5 nmvp105ca7 nmvp10elc9 nmvp1dkmza nmvp1dn8xb nmvp2hef8e nmvp4z4h67 nmvp5a1b2c nmvp5a3d4e"
expect "ts (s) -> timestamp (ms)" "$(jq -r 'select(.key == "nmvp1dn8xb") | .timestamp' "$a")" 1793005833201
expect "fields as the 4.0 path writes them" "$(jq -c 'select(.key == "nmvp10elc9")' "$a")" \
  "$(jq -nc --arg g "$(jq -r '.[] | select(.key == "nmvp10elc9") | .glyph' "$fx/history.json")" \
    '{key:"nmvp10elc9",app:"omarchy-action",appIcon:"battery-caution",summary:"Fixture summary 5",body:"Fixture body 5",image:"",preview:"",file:"",glyph:$g,urgency:1,timestamp:1793005215456}')"
expect "urgencies kept (low / critical)" "$(jq -r 'select(.key == "nmvp2hef8e" or .key == "nmvo4b91g11") | .urgency' "$a" | paste -sd' ')" "2 0"
expect "no pictures archived, even for a real screenshot path" \
  "$(jq -r 'select(.key == "nmvp0h2bc5") | .image + .preview' "$a")|$(find "$o/store/images" -type f | wc -l)" "|0"
gone "the old history/ folder is not created" "$o/src/history"
expect "the ledger holds the keys both files hold" "$(LC_ALL=C sort "$o/store/engine-keys" | paste -sd' ')" \
  "$(jq -r '.[].key' "$o/src/history.json" "$o/src/live.json" | LC_ALL=C sort | paste -sd' ')"
O sync omapager > /dev/null
expect "a second sync adds nothing" "$(wc -l < "$a")" 11
# A live row that closes moves to history.json under the same key.
jq -c '[.[0] + {closed_ts: 1793012010, closed_reason: "expired"}] + input' "$o/src/live.json" "$o/src/history.json" > "$o/h.json"
mv "$o/h.json" "$o/src/history.json"; jq -c '.[1:]' "$fx/live.json" > "$o/src/live.json"
O sync omapager > /dev/null
expect "closing a live row does not archive it twice" "$(jq -r 'select(.key == "nmvp5a1b2c") | .key' "$a" | wc -l)" 1
# Empty Trash forgets rows; history.json still has them for 24 h.
O clear > /dev/null; O empty-trash > /dev/null
O sync omapager > /dev/null
expect "rows emptied from Trash do not come back" "$(wc -l < "$a")" 0
jq -nc '[{key:"nnew1",app:"New",summary:"fresh",ts:1793012100}]' > "$o/src/live.json"
O sync omapager > /dev/null
expect "a new row after that still arrives" "$(jq -r .key "$a")" nnew1
# History expiring rows shrinks the ledger with it.
jq -c '.[:2]' "$o/src/history.json" > "$o/h.json"; mv "$o/h.json" "$o/src/history.json"
O sync omapager > /dev/null
expect "ledger follows the files" "$(wc -l < "$o/store/engine-keys")" 3
# Hostile or broken files.
printf '%s\n' '[{"key":"../x","summary":"bad"},{"key":5},"str",null,{"summary":"no key"},{"key":"ok1","summary":"good","appIcon":"../etc","app":"'"$(printf 'A%.0s' $(seq 1 80))"'","ts":"x","closed_ts":1793012200}]' > "$o/src/history.json"
O sync omapager > /dev/null
expect "only valid keys taken" "$(jq -r 'select(.key != "nnew1") | .key' "$a")" ok1
expect "unsafe icon dropped, app cut, ts falls back to closed_ts" \
  "$(jq -c 'select(.key == "ok1") | [.appIcon, (.app | length), .timestamp]' "$a")" '["",64,1793012200000]'
for bad in '{"key":"x"}' 'not json' ''; do
  printf '%s' "$bad" > "$o/src/history.json"
  out=$(O sync omapager)
  expect "history.json '${bad:-empty}': sync still ok" "$out" '{"ok":true,"synced":true}'
done
expect "...and nothing added" "$(wc -l < "$a")" 2
expect "unknown engine is an error" "$(O sync nonsense 2>/dev/null | jq -r .error)" "unknown engine: nonsense"
# auto: omapager when its files are there, else the 4.0 layout.
a2=$tmp/auto; mkdir -p "$a2/src"; cp "$fx/live.json" "$a2/src/"
YANC_SRC_DIR=$a2/src YANC_STORE=$a2/store bash "$backend" sync auto > /dev/null
expect "auto picks omapager when live.json is there" "$(wc -l < "$a2/store/archive.jsonl")" 2
gone "...and makes no history/" "$a2/src/history"
# legacy (no engine) ignores the 4.5 files, as before.
YANC_SRC_DIR=$a2/src YANC_STORE=$a2/legacy bash "$backend" sync > /dev/null 2>&1
expect "legacy sync ignores live.json/history.json" "$(wc -l < "$a2/legacy/archive.jsonl")" 0
if command -v inotifywait >/dev/null 2>&1; then
  ow=$tmp/owatch; mkdir -p "$ow/src"; cp "$fx/history.json" "$ow/src/"
  YANC_STORE=$ow/store YANC_SRC_DIR=$ow/src timeout 8 bash "$backend" watch omapager > "$ow/out" 2>/dev/null &
  wpid=$!
  for _ in $(seq 1 30); do [[ -s $ow/store/engine-keys ]] && break; sleep 0.1; done
  sleep 0.5
  expect "watch: startup sync is quiet" "$(wc -c < "$ow/out")" 0
  # Omarchy writes atomically: a temp file renamed over live.json.
  jq -c '.[0:1]' "$fx/live.json" > "$ow/src/.live.json.tmp"; mv "$ow/src/.live.json.tmp" "$ow/src/live.json"
  for _ in $(seq 1 30); do grep -q nmvp5a1b2c "$ow/out" 2>/dev/null && break; sleep 0.1; done
  expect "watch prints a new live row" "$(jq -r .key "$ow/out" 2>/dev/null)" nmvp5a1b2c
  printf '{"dnd":false}\n' > "$ow/src/quiet.json"
  jq -c '[.[0] + {closed_ts: 1793012010, closed_reason: "expired"}] + input' "$fx/live.json" "$fx/history.json" > "$ow/src/.h.tmp"
  mv "$ow/src/.h.tmp" "$ow/src/history.json"; printf '[]\n' > "$ow/src/live.json"
  sleep 1
  kill "$wpid" 2>/dev/null; wait "$wpid" 2>/dev/null
  pkill -f "inotifywait.*$ow/src" 2>/dev/null
  expect "watch: the same row closing is not announced again" "$(jq -r .key "$ow/out" | paste -sd' ')" nmvp5a1b2c
  expect "watch archived history + the live row" "$(wc -l < "$ow/store/archive.jsonl")" 10
  gone "watch omapager makes no history/" "$ow/src/history"
else
  echo "SKIP  watch omapager (no inotifywait)"
fi

echo
printf 'RESULT  %d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
