#!/usr/bin/env bash
# Copy keeps notification text out of argv: runs the real RowOpener.qml and
# ActionRunner.qml in Quickshell (offscreen) with a stub wl-copy first on
# PATH that records its argv and stdin. The text must arrive on stdin only,
# byte for byte, and stdin is closed after it (EOF, no hang); calls without
# input still work; failures still reach their callback. Temp dir only; the real clipboard is untouched.
#   tests/stdin.sh [PLUGIN_DIR]   (default: this checkout)
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "${1:-$here/..}" && pwd)
if ! command -v qs >/dev/null 2>&1; then echo "SKIP  copy via stdin (no qs)"; exit 0; fi
tmp=$(mktemp -d /tmp/yanc-stdin.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ok() { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
no() { printf 'FAIL  %s\n      %s\n' "$1" "${2:-}"; fail=$((fail + 1)); }
expect() { if [[ $2 == "$3" ]]; then ok "$1"; else no "$1" "got: $2 | want: $3"; fi; }

mkdir -p "$tmp/cfg" "$tmp/bin"
ln -s "$src" "$tmp/cfg/nc"
cp "$here/qml/stdin.qml" "$tmp/cfg/shell.qml"
# Stub wl-copy: argv and stdin of every call, one file each.
cat > "$tmp/bin/wl-copy" <<STUB
#!/usr/bin/env bash
n=\$(ls "$tmp" | grep -c '^argv\.' || true)
printf '%s\n' "\$@" > "$tmp/argv.\$n"
cat > "$tmp/stdin.\$n"
STUB
chmod +x "$tmp/bin/wl-copy"

secret='Тест копіювання: секрет123 $(id) `x` "q" '\''s'\'' -- --help'
out=$(PATH="$tmp/bin:$PATH" STDIN_SECRET="$secret" QT_QPA_PLATFORM=offscreen \
  timeout 30 qs -p "$tmp/cfg" 2>&1)
res=$(printf '%s\n' "$out" | sed -n 's/.*\(RES .*\|END\)$/\1/p')

expect "harness finished" "$(printf '%s\n' "$res" | tail -n1)" "END"
expect "copy: Copied only after wl-copy succeeds" "$(grep '^RES copy ' <<< "$res")" "RES copy true -"
expect "copy: text arrives on stdin, trimmed, byte for byte" "$(cat "$tmp/stdin.0" 2>/dev/null)" "$secret"
expect "copy: no trailing newline added" "$(tail -c 4 "$tmp/stdin.0" 2>/dev/null | od -An -c | tr -d ' ')" "help"
expect "copy: argv is only the mime type" "$(tr '\n' ' ' < "$tmp/argv.0" 2>/dev/null)" "--type text/plain;charset=utf-8 "
if grep -rqF 'секрет123' "$tmp"/argv.* 2>/dev/null; then no "copy: secret never in argv" "found in argv"; else ok "copy: secret never in argv"; fi
expect "copy: summary when the body is empty" "$(cat "$tmp/stdin.1" 2>/dev/null)" "Тільки заголовок"
expect "run without input still works" "$(grep '^RES plain ' <<< "$res")" "RES plain true -"
expect "run with input: failure still reported (stdin hit EOF)" "$(grep '^RES fail ' <<< "$res")" "RES fail false nope"
if grep -q 'ReferenceError\|TypeError\|is not a type\|Cannot assign' <<< "$out"; then
  no "no QML errors" "$(grep 'ReferenceError\|TypeError\|is not a type\|Cannot assign' <<< "$out" | head -n3)"
else ok "no QML errors"; fi

echo
printf 'RESULT  %d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
