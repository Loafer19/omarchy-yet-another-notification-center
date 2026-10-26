#!/usr/bin/env bash
# prune() equivalence: the single-pass prune in scripts/backend.sh must leave
# the same archive.jsonl, trash.jsonl and pictures as the v1.3.1 prune
# (tests/legacy/prune-v1.3.1.sh) for every fixture in tests/fixtures/prune.
# Both run on copies in a temp dir with the clock pinned (YANC_NOW_MS).
#   tests/prune.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
backend=$here/../scripts/backend.sh
fixtures=$here/fixtures/prune
tmp=$(mktemp -d /tmp/yanc-prune.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ok() { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
no() { printf 'FAIL  %s\n%s\n' "$1" "${2:-}"; fail=$((fail + 1)); }

# The legacy backend = today's backend with prune() swapped for the old one,
# so both share every other helper (limits, drop_images, locking, clock).
mkdir -p "$tmp/legacy/scripts"
cp "$here/../defaults.js" "$tmp/legacy/defaults.js"   # backend reads ../defaults.js
legacy=$tmp/legacy/scripts/backend.sh
awk -v ref="$here/legacy/prune-v1.3.1.sh" '
  /^prune\(\) \{/ { skip = 1; while ((getline l < ref) > 0) if (l !~ /^#/) print l; next }
  skip && /^\}/ { skip = 0; next }
  !skip' "$backend" > "$legacy"
grep -q "one jq per overflow line\|printf '%s\\\\n' \"\$line\" | jq -c" "$legacy" \
  || { no "legacy backend built" "prune() was not replaced"; exit 1; }

export YANC_NOW_MS; YANC_NOW_MS=$(cat "$fixtures/NOW")
export HOME=$tmp/home XDG_STATE_HOME=$tmp/state YANC_SRC_DIR=$tmp/src
mkdir -p "$HOME" "$YANC_SRC_DIR"
unset YANC_KEEP_DAYS YANC_MAX_ITEMS YANC_HISTORY_LIMIT YANC_TRASH_DAYS

stage() { # stage CASE DIR — copy a fixture into a store
  local c=$fixtures/$1 d=$2 name
  mkdir -p "$d/images"
  for name in archive.jsonl trash.jsonl settings.json; do
    [[ -f $c/$name ]] && cp "$c/$name" "$d/$name"
  done
  if [[ -f $c/images.list ]]; then
    while IFS= read -r name; do printf 'img %s\n' "$name" > "$d/images/$name"; done < "$c/images.list"
  fi
}
run() { # run BACKEND CASE DIR
  local envs=()
  [[ -f $fixtures/$2/env ]] && read -ra envs < "$fixtures/$2/env"
  env "${envs[@]}" YANC_STORE="$3" bash "$1" prune
}
snapshot() { # files the user would see afterwards
  local d=$1
  printf -- '--- archive\n'; cat "$d/archive.jsonl" 2>/dev/null
  printf -- '--- trash\n'; cat "$d/trash.jsonl" 2>/dev/null
  printf -- '--- images\n'; (cd "$d/images" && find . -type f | LC_ALL=C sort)
}

compare() { # compare CASE
  local c=$1 a=$tmp/$1/old b=$tmp/$1/new out
  stage "$c" "$a"; stage "$c" "$b"
  run "$legacy" "$c" "$a" >/dev/null 2>&1
  out=$(run "$backend" "$c" "$b" 2>&1)
  if [[ $out != '{"ok":true,"pruned":true}' ]]; then no "$c: prune ok" "$out"; return; fi
  if diff -u <(snapshot "$a") <(snapshot "$b") > "$tmp/$c.diff"; then
    ok "$c: same archive, trash and pictures as v1.3.1"
  else
    no "$c: differs from v1.3.1" "$(cat "$tmp/$c.diff")"
  fi
}

for c in "$fixtures"/*/; do
  c=$(basename "$c")
  [[ $c == corrupt ]] && continue
  compare "$c"
done

# A bigger generated store: 600 rows over 40 days, 300 trash rows over 60.
mkdir -p "$tmp/gen"
now=$YANC_NOW_MS
jq -nc --argjson now "$now" 'range(600) as $i
  | {key: "g\($i)", app: "App \($i % 7)", summary: "row \($i) ✓", urgency: ($i % 3),
     timestamp: ($now - (($i * 7919) % (40 * 86400)) * 1000)}' > "$tmp/gen.archive"
jq -nc --argjson now "$now" 'range(300) as $i
  | {key: "h\($i % 250)", timestamp: 1, trashedAt: ($now - (($i * 104729) % (60 * 86400)) * 1000)}' > "$tmp/gen.trash"
for setting in '{"displayLimit":500,"keepDays":20,"trashDays":30}' '{"displayLimit":10,"keepDays":365,"trashDays":1}'; do
  for side in old new; do
    d=$tmp/gen/$side; rm -rf "$d"; mkdir -p "$d/images"
    cp "$tmp/gen.archive" "$d/archive.jsonl"; cp "$tmp/gen.trash" "$d/trash.jsonl"
    printf '%s\n' "$setting" > "$d/settings.json"
    for i in $(seq 0 25 249); do : > "$d/images/h$i-image.png"; done
  done
  YANC_STORE=$tmp/gen/old bash "$legacy" prune >/dev/null 2>&1
  YANC_STORE=$tmp/gen/new bash "$backend" prune >/dev/null 2>&1
  if diff -u <(snapshot "$tmp/gen/old") <(snapshot "$tmp/gen/new") > "$tmp/gen.diff"; then
    ok "generated 600+300 rows $setting: same as v1.3.1"
  else
    no "generated $setting differs" "$(head -n 40 "$tmp/gen.diff")"
  fi
done

# Corrupt lines: History and Trash text match v1.3.1. One deliberate fix:
# v1.3.1 listed trash keys with a strict jq parse, so a corrupt line in
# trash.jsonl stopped it and pictures of purged entries were left behind.
c=corrupt a=$tmp/$c/old b=$tmp/$c/new
stage "$c" "$a"; stage "$c" "$b"
run "$legacy" "$c" "$a" >/dev/null 2>&1
run "$backend" "$c" "$b" >/dev/null 2>&1
if diff <(snapshot "$a" | sed '/^--- images/,$d') <(snapshot "$b" | sed '/^--- images/,$d') >/dev/null; then
  ok "corrupt: same archive and trash as v1.3.1"
else
  no "corrupt: archive/trash differ" "$(diff <(snapshot "$a") <(snapshot "$b"))"
fi
want=$'./t1-image.png'
got=$(cd "$b/images" && find . -type f | LC_ALL=C sort)
if [[ $got == "$want" ]]; then ok "corrupt: pictures of purged t2/t3 are deleted"; else no "corrupt: pictures" "got: $got"; fi
got=$(cd "$a/images" && find . -type f | LC_ALL=C sort | paste -sd' ')
if [[ $got == './t1-image.png ./t2-image.png ./t3-appIcon' ]]; then ok "corrupt: (v1.3.1 left them behind)"; else no "corrupt: legacy pictures" "got: $got"; fi

# Failures: if History or Trash cannot be written nothing changes and prune
# says so.
d=$tmp/fail; stage basic "$d"; cp -r "$d" "$tmp/fail.before"
mkdir "$d/archive.jsonl.tmp"
out=$(YANC_STORE=$d bash "$backend" prune 2>/dev/null); rc=$?
rmdir "$d/archive.jsonl.tmp"
if [[ $rc == 1 && $(jq -r .ok <<< "$out") == false ]]; then ok "unwritable store -> prune reports failure"; else no "prune failure" "$rc $out"; fi
if cmp -s "$tmp/fail.before/archive.jsonl" "$d/archive.jsonl" \
   && cmp -s "$tmp/fail.before/trash.jsonl" "$d/trash.jsonl"; then
  ok "unwritable store -> History and Trash unchanged"
else
  no "History changed after failed prune"
fi
d=$tmp/fail2; stage basic "$d"; cp -r "$d" "$tmp/fail2.before"
mv "$d/trash.jsonl" "$tmp/fail2.trash"; mkdir "$d/trash.jsonl"
out=$(YANC_STORE=$d bash "$backend" prune 2>/dev/null); rc=$?
rmdir "$d/trash.jsonl"; mv "$tmp/fail2.trash" "$d/trash.jsonl"
if [[ $rc == 1 ]] && cmp -s "$tmp/fail2.before/archive.jsonl" "$d/archive.jsonl" \
   && [[ ! -e $d/archive.jsonl.tmp ]]; then
  ok "unwritable Trash -> nothing moved out of History"
else
  no "unwritable Trash" "$rc $out"
fi

echo
printf 'RESULT  %d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
