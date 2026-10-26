# shellcheck shell=bash
# History (archive.jsonl) and Trash (trash.jsonl): limits, moves, reads.
# Sourced by backend.sh.

prune() {
  load_runtime_limits
  local cutoff trash_cutoff now limit tagged key

  now=$(now_ms)
  cutoff=$(( now - keep_days * 86400000 ))
  trash_cutoff=$(( now - trash_days * 86400000 ))
  limit=$history_limit
  (( limit < 1 )) && limit=1

  if [[ -s $archive ]]; then
    # One jq pass over History, in file order:
    # - entries older than keepDays are dropped for good;
    # - History keeps the newest displayLimit (and never more than maxItems);
    #   the oldest overflow goes to Trash with trashedAt = now.
    # Lines are tagged "A\t" (stay) / "T\t" (to Trash); compact JSON never
    # contains a raw tab. If jq fails nothing is written.
    tagged=$(jq -Rnr --argjson cutoff "$cutoff" --argjson limit "$limit" \
        --argjson max "$max_items" --argjson now "$now" '
      [inputs | fromjson? // empty | select((.timestamp // 0) >= $cutoff)] as $kept
      | ([$limit, $max] | min | if . < 0 then 0 else . end) as $cap
      | ([($kept | length) - $cap, 0] | max) as $drop
      | ($kept[:$drop][] | "T\t" + (. + {trashedAt: $now} | tojson)),
        ($kept[$drop:][] | "A\t" + tojson)
    ' "$archive" 2>/dev/null) || return 1
    # New History first, so a failed write changes nothing; then Trash.
    if ! printf '%s\n' "$tagged" | sed -n 's/^A\t//p' > "$archive.tmp"; then
      rm -f "$archive.tmp"; return 1
    fi
    if [[ $tagged == *$'T\t'* ]] \
        && ! printf '%s\n' "$tagged" | sed -n 's/^T\t//p' >> "$trash"; then
      rm -f "$archive.tmp"; return 1
    fi
    mv -f "$archive.tmp" "$archive" || { rm -f "$archive.tmp"; return 1; }
  fi

  if [[ -s $trash ]]; then
    # One jq pass over Trash: keep entries newer than trashDays, list the keys
    # that are gone (no kept entry with that key) so their pictures go too.
    tagged=$(jq -Rnr --argjson cutoff "$trash_cutoff" '
      [inputs | fromjson? // empty] as $all
      | ($all | map(select((.trashedAt // .timestamp // 0) >= $cutoff))) as $kept
      | ($kept | map(.key // empty | tostring) | unique) as $keep
      | ($kept[] | "A\t" + tojson),
        ($all | map(.key // empty | tostring) | unique - $keep | .[] | "D\t" + .)
    ' "$trash" 2>/dev/null) || return 1
    if ! printf '%s\n' "$tagged" | sed -n 's/^A\t//p' > "$trash.tmp" \
        || ! mv -f "$trash.tmp" "$trash"; then
      rm -f "$trash.tmp"; return 1
    fi
    while IFS= read -r key; do
      [[ -n $key ]] && drop_images "$key"
    done < <(printf '%s\n' "$tagged" | sed -n 's/^D\t//p')
  fi
  return 0
}

list_file() {
  local src=$1 limit
  limit=$(clamp_limit "${2:-200}")
  [[ -s $src ]] || { printf '[]\n'; return; }
  # Do not pipe through head: pipefail would append a second [] after a
  # successful array once the archive is larger than the display limit.
  jq -n --argjson n "$limit" '[inputs] | sort_by(.timestamp // 0) | reverse | .[:$n]' "$src" 2>/dev/null \
    || printf '[]\n'
}

cmd_list() { ensure_store; list_file "$archive" "${1:-200}"; }

cmd_trash_list() { ensure_store; list_file "$trash" "${1:-200}"; }

take_line() {
  local src=$1 key=$2
  jq -Rc --arg key "$key" 'fromjson? // empty | select(.key == $key)' "$src" 2>/dev/null | head -n 1
}

# Rewrite SRC without KEY. Returns 1 (SRC untouched) if jq or the write fails,
# so a failed write can never empty the file.
strip_key() {
  local src=$1 key=$2
  jq -Rc --arg key "$key" 'fromjson? // empty | select(.key != $key)' "$src" > "$src.tmp" 2>/dev/null \
    && mv -f "$src.tmp" "$src" && return 0
  rm -f "$src.tmp"
  return 1
}

# Each move writes the destination first and only then removes the source,
# and stops at the first failure: worst case an entry is in both lists,
# never in neither. Exit 2 = key not found, 1 = I/O failure.
dismiss_key() {
  local key=$1 line now
  line=$(take_line "$archive" "$key")
  [[ -n $line ]] || return 2
  now=$(now_ms)
  printf '%s\n' "$line" | jq -c --argjson trashedAt "$now" '. + {trashedAt: $trashedAt}' >> "$trash" || return 1
  strip_key "$archive" "$key"
}

restore_key() {
  local key=$1 line
  line=$(take_line "$trash" "$key")
  [[ -n $line ]] || return 2
  printf '%s\n' "$line" | jq -c 'del(.trashedAt)' >> "$archive" || return 1
  strip_key "$trash" "$key"
}

purge_key() {
  local key=$1
  have_key_in "$trash" "$key" || return 2
  strip_key "$trash" "$key" || return 1
  drop_images "$key"
}

clear_all() {
  local now
  now=$(now_ms)
  [[ -s $archive ]] || return 0
  jq -Rc --argjson trashedAt "$now" 'fromjson? // empty | objects | . + {trashedAt: $trashedAt}' \
    "$archive" > "$archive.trashing" 2>/dev/null || { rm -f "$archive.trashing"; return 1; }
  cat "$archive.trashing" >> "$trash" || { rm -f "$archive.trashing"; return 1; }
  rm -f "$archive.trashing"
  : > "$archive"
}

empty_trash() {
  local key keys
  keys=$(jq -Rr 'fromjson? // empty | .key // empty' "$trash" 2>/dev/null) || return 1
  : > "$trash" || return 1
  while IFS= read -r key; do
    [[ -n $key ]] || continue
    drop_images "$key"
  done <<< "$keys"
}

cmd_dismiss() {
  ensure_store
  local key=${1:-}
  valid_key "$key" || die "dismiss needs a key"
  local rc=0
  with_lock dismiss_key "$key" || rc=$?
  case $rc in
    0) printf '{"ok":true,"dismissed":%s}\n' "$(json_string "$key")" ;;
    2) die "not in history" ;;
    *) die "cannot write $store" ;;
  esac
}

cmd_restore() {
  ensure_store
  local key=${1:-}
  valid_key "$key" || die "restore needs a key"
  local rc=0
  with_lock restore_key "$key" || rc=$?
  case $rc in
    0) printf '{"ok":true,"restored":%s}\n' "$(json_string "$key")" ;;
    2) die "not in trash" ;;
    *) die "cannot write $store" ;;
  esac
}

cmd_purge() {
  ensure_store
  local key=${1:-}
  valid_key "$key" || die "purge needs a key"
  local rc=0
  with_lock purge_key "$key" || rc=$?
  case $rc in
    0) printf '{"ok":true,"purged":%s}\n' "$(json_string "$key")" ;;
    2) die "not in trash" ;;
    *) die "cannot write $store" ;;
  esac
}

cmd_clear() {
  ensure_store
  with_lock clear_all || die "cannot write $store"
  printf '{"ok":true,"cleared":true}\n'
}

cmd_empty_trash() {
  ensure_store
  with_lock empty_trash || die "cannot write $store"
  printf '{"ok":true,"emptied":true}\n'
}

cmd_seen() {
  ensure_store
  local stamp
  if [[ $# -gt 0 && -n ${1:-} ]]; then
    [[ ${1:-} =~ ^[0-9]{1,16}$ ]] || die "seen needs a millisecond stamp"
    printf '%s\n' "$1" > "$seen_file" || die "cannot write $seen_file"
    printf '{"ok":true,"seen":%s}\n' "$1"
    return
  fi
  stamp=$(cat "$seen_file" 2>/dev/null || echo 0)
  [[ $stamp =~ ^[0-9]+$ ]] || stamp=0
  printf '{"ok":true,"seen":%s}\n' "$stamp"
}

cmd_unread() {
  ensure_store
  local seen
  seen=$(cat "$seen_file" 2>/dev/null || echo 0)
  [[ $seen =~ ^[0-9]+$ ]] || seen=0
  printf '{"ok":true,"unread":%s}\n' \
    "$(jq -Rc --argjson seen "$seen" 'fromjson? // empty | select((.timestamp // 0) > $seen)' "$archive" 2>/dev/null \
      | grep -c . || echo 0)"
}
