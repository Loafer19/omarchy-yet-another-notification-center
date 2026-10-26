#!/usr/bin/env bash
# Omarchy 4.5 (Omapager) checks: the real Service.qml and backend in Quickshell
# (offscreen) against a fake 4.5 notification service (tests/qml/omapager.qml):
# engine detection, auto-hide through closeToasts(key, "expired"), archiving
# from live.json/history.json, Do Not Disturb, and no old history/ folder.
# Temp HOME and store; nothing touches real toasts.
#   tests/omapager.sh [PLUGIN_DIR]   (default: this checkout)
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "${1:-$here/..}" && pwd)
if ! command -v qs >/dev/null 2>&1; then echo "SKIP  omapager (no qs)"; exit 0; fi
if ! command -v inotifywait >/dev/null 2>&1; then echo "SKIP  omapager (no inotifywait)"; exit 0; fi
tmp=$(mktemp -d /tmp/yanc-omapager.XXXXXX)
trap 'pkill -f "inotifywait.*$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
pass=0; fail=0
tol=${AH_TOLERANCE:-300}

run() { # run NAME AUTOHIDE_MS EVENTS
  local name=$1 ms=$2 events=$3 cfg=$tmp/$1/cfg st=$tmp/$1/state
  mkdir -p "$cfg" "$st/omarchy/notifications" "$st/omarchy/yoyo.notification-center"
  ln -s "$src" "$cfg/nc"
  cp "$here/qml/omapager.qml" "$cfg/shell.qml"
  printf '{"autoHideMs":%s}\n' "$ms" > "$st/omarchy/yoyo.notification-center/settings.json"
  printf '[]\n' > "$st/omarchy/notifications/live.json"
  printf '[]\n' > "$st/omarchy/notifications/history.json"
  HOME=$tmp/$1 XDG_STATE_HOME=$st YANC_SRC_DIR=$st/omarchy/notifications \
    YANC_STORE=$st/omarchy/yoyo.notification-center AH_EVENTS="$events" \
    QT_QPA_PLATFORM=offscreen timeout 40 qs -p "$cfg" 2>&1 \
    | sed -n 's/.*\(CFG\|ENGINE\|HIDE\|USERCLOSE\|ARCHIVED\|SETDND\|DND svc\|END\)\(.*\)/\1\2/p'
}

cases=()
case_() { # case_ NAME MS EVENTS EXPECT
  cases+=("$1|$2|$4")
  run "$1" "$2" "$3" > "$tmp/$1.out" &
}

# EXPECT items: id@ms@reason[@tolerance] (HIDE), left=ids, has=TEXT (a line
# containing TEXT, "_" for spaces), archived=id, nohistorydir.
check() {
  local name=$1 ms=$2 want=$3 out got item id at how t line bad="" n_hidden n_want=0 itol
  out=$(cat "$tmp/$name.out")
  printf '%s\n' "$out" | sed "s/^/      [$name] /"
  [[ $out == *"CFG autoHideMs=$ms"* ]] || bad+=" settings.json not read;"
  [[ $out == *"ENGINE omapager args=watch,omapager"* ]] || bad+=" engine not detected;"
  for item in $want; do
    case $item in
      left=*) [[ $out == *"END "*" $item"* ]] || bad+=" want $item;" ;;
      has=*) [[ $out == *"${item#has=}"* || $out == *"$(printf '%s' "${item#has=}" | tr _ ' ')"* ]] || bad+=" missing '${item#has=}';" ;;
      archived=*) grep -q "^ARCHIVED ${item#archived=} " <<< "$out" || bad+=" ${item#archived=} not archived;"
        jq -e --arg k "${item#archived=}" 'select(.key == $k)' "$tmp/$name/state/omarchy/yoyo.notification-center/archive.jsonl" >/dev/null 2>&1 \
          || bad+=" ${item#archived=} not in archive.jsonl;" ;;
      nohistorydir) [[ ! -e $tmp/$name/state/omarchy/notifications/history ]] || bad+=" history/ was created;" ;;
      *)
        n_want=$((n_want + 1))
        IFS=@ read -r id at how itol <<< "$item"
        itol=${itol:-$tol}
        line=$(grep "^HIDE $id " <<< "$out" | head -n1)
        if [[ -z $line ]]; then bad+=" $id never hidden;"; continue; fi
        read -r _ _ t got <<< "$line"
        (( t >= at - 50 && t <= at + itol )) || bad+=" $id at ${t}ms, want ${at}ms;"
        [[ $got == "$how" ]] || bad+=" $id via $got, want $how;"
        ;;
    esac
  done
  n_hidden=$(grep -c '^HIDE ' <<< "$out" || true)
  (( n_hidden == n_want )) || bad+=" hid $n_hidden toasts, want $n_want;"
  if [[ -z $bad ]]; then printf 'PASS  %s\n' "$name"; pass=$((pass + 1))
  else printf 'FAIL  %s:%s\n' "$name" "$bad"; fail=$((fail + 1)); fi
}

case_ single     2000 "0:add:A;3500:end"                          "A@2000@expired left= nohistorydir"
case_ critical   2000 "0:add:A:2;3500:end"                        "A@2000@expired left="
case_ stacked    2000 "0:add:A;1000:add:B;5000:end"               "A@2000@expired B@3000@expired left="
case_ updated    2000 "0:add:A;1500:update:A:v2;5000:end"         "A@3500@expired left="
case_ user-closed 2000 "0:add:A;1000:gone:A;1000:add:B;4000:end"  "B@3000@expired left="
case_ held       2000 "0:add:A;1000:hold;3000:release;5000:end"   "A@3000@expired@500 left="
case_ off        0    "0:add:A;3000:end"                          "left=A"
case_ turned-on  0    "0:add:A;500:set:1000;3000:end"             "A@1500@expired left="
# Archive + DND: the backend archives the live row and the closed one only
# once; DND follows the service both ways.
case_ store      0    "0:add:S1;800:add:S2;2500:gone:S1;3000:dnd:on;3500:probe;3600:setdnd:off;4000:probe;5000:end" \
  "archived=S1 archived=S2 has=DND_svc=true_fake=true has=SETDND_false has=DND_svc=false_fake=false left=S2 nohistorydir"
wait
for c in "${cases[@]}"; do
  IFS='|' read -r name ms want <<< "$c"
  check "$name" "$ms" "$want"
done
# Each key announced (and archived) once, though S1 went live -> history.
s1=$(grep -c '^ARCHIVED S1 ' "$tmp/store.out" || true)
rows=$(jq -r .key "$tmp/store/state/omarchy/yoyo.notification-center/archive.jsonl" 2>/dev/null | sort | paste -sd' ')
if [[ $s1 == 1 && $rows == "S1 S2" ]]; then printf 'PASS  store: one archive row per key\n'; pass=$((pass + 1))
else printf 'FAIL  store: one archive row per key: announced S1 %s times, archive: %s\n' "$s1" "$rows"; fail=$((fail + 1)); fi

echo
printf 'RESULT  %d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
