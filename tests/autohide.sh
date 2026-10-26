#!/usr/bin/env bash
# Live auto-hide checks: runs the real Service.qml in Quickshell (offscreen)
# against a fake Omarchy notification service (tests/qml/autohide.qml) and
# checks when each toast leaves (cases run in parallel, ~10 s). Temp store;
# nothing touches real toasts.
#   tests/autohide.sh [PLUGIN_DIR]   (default: this checkout)
#   AH_REPORT=1 tests/autohide.sh DIR  only print, don't check (e.g. master)
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "${1:-$here/..}" && pwd)
if ! command -v qs >/dev/null 2>&1; then echo "SKIP  auto-hide (no qs)"; exit 0; fi
tmp=$(mktemp -d /tmp/yanc-autohide.XXXXXX)
trap 'pkill -f "inotifywait.*$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
pass=0; fail=0
tol=${AH_TOLERANCE:-300}

run() { # run NAME AUTOHIDE_MS EVENTS — prints the harness log
  local name=$1 ms=$2 events=$3 cfg=$tmp/$1/cfg st=$tmp/$1/state
  mkdir -p "$cfg" "$st/omarchy/notifications/history" "$st/omarchy/yoyo.notification-center"
  ln -s "$src" "$cfg/nc"
  cp "$here/qml/autohide.qml" "$cfg/shell.qml"
  printf '{"autoHideMs":%s}\n' "$ms" > "$st/omarchy/yoyo.notification-center/settings.json"
  HOME=$tmp/$1 XDG_STATE_HOME=$st YANC_SRC_DIR=$st/omarchy/notifications \
    YANC_STORE=$st/omarchy/yoyo.notification-center AH_EVENTS="$events" \
    QT_QPA_PLATFORM=offscreen timeout 40 qs -p "$cfg" 2>&1 | sed -n 's/.*\(CFG\|HIDE\|END\)\(.*\)/\1\2/p'
}

cases=()
case_() { # case_ NAME MS EVENTS EXPECT — starts the run in the background
  cases+=("$1|$2|$4")
  run "$1" "$2" "$3" > "$tmp/$1.out" &
}

check() { # check NAME MS EXPECT  (EXPECT: "id@ms@how ..." and "left=ids")
  local name=$1 ms=$2 want=$3 out got item id at how line t items
  out=$(cat "$tmp/$name.out")
  printf '%s\n' "$out" | sed "s/^/      [$name] /"
  [[ ${AH_REPORT:-0} == 1 ]] && return
  local bad=""
  [[ $out == *"CFG autoHideMs=$ms"* ]] || bad+=" settings.json not read;"
  for item in $want; do
    if [[ $item == left=* ]]; then
      [[ $out == *"END "*" $item"* ]] || bad+=" want $item;"
      continue
    fi
    IFS=@ read -r id at how <<< "$item"
    line=$(printf '%s\n' "$out" | grep "^HIDE $id " | head -n1)
    if [[ -z $line ]]; then bad+=" $id never hidden;"; continue; fi
    read -r _ _ t got <<< "$line"
    (( t >= at - 50 && t <= at + tol )) || bad+=" $id at ${t}ms, want ${at}ms;"
    [[ $got == "$how" ]] || bad+=" $id via $got, want $how;"
  done
  local n_hidden n_want
  n_hidden=$(printf '%s\n' "$out" | grep -c '^HIDE ' || true)
  read -ra items <<< "$want"
  n_want=$(printf '%s\n' "${items[@]}" | grep -vc '^left=' || true)
  (( n_hidden == n_want )) || bad+=" hid $n_hidden toasts, want $n_want;"
  if [[ -z $bad ]]; then printf 'PASS  %s\n' "$name"; pass=$((pass + 1))
  else printf 'FAIL  %s:%s\n' "$name" "$bad"; fail=$((fail + 1)); fi
}

case_ single      2000 "0:add:A;3500:end"                                  "A@2000@expire left="
case_ stacked     2000 "0:add:A;1000:add:B;2500:add:C;6000:end"            "A@2000@expire B@3000@expire C@4500@expire left="
case_ critical    2000 "0:add:A:2;3500:end"                                "A@2000@expire left="
case_ replaced    2000 "0:add:A;1500:replace:A:v2;5000:end"                "A@3500@expire left="
case_ edited      2000 "0:add:A;1500:edit:A:v2;5000:end"                   "A@3500@expire left="
case_ swapped     2000 "0:add:A;1900:gone:A;1900:add:B;5000:end"           "B@3900@expire left="
case_ off         0    "0:add:A;3000:end"                                  "left=A"
case_ turned-on   0    "0:add:A;500:set:1000;3000:end"                     "A@1500@expire left="
case_ turned-off  2000 "0:add:A;1000:set:0;3500:end"                       "left=A"
wait
for c in "${cases[@]}"; do
  IFS='|' read -r name ms want <<< "$c"
  check "$name" "$ms" "$want"
done

echo
printf 'RESULT  %d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
