# shellcheck shell=bash disable=SC2154
# prune() as shipped in v1.3.1 (one jq per overflow line). Kept only as the
# reference for tests/prune.sh, which checks the single-pass prune() in
# scripts/backend.sh produces byte-identical stores. Not used at runtime.

prune() {
  load_runtime_limits
  local cutoff trash_cutoff kept overflow now count limit

  cutoff=$(( $(now_ms) - keep_days * 86400000 ))
  trash_cutoff=$(( $(now_ms) - trash_days * 86400000 ))
  now=$(now_ms)

  if [[ -s $archive ]]; then
    # Drop entries older than keepDays (past retention — gone for good).
    if kept=$(jq -Rc --argjson cutoff "$cutoff" \
        'fromjson? // empty | select((.timestamp // 0) >= $cutoff)' "$archive" 2>/dev/null); then
      kept=$(printf '%s
' "$kept" | grep -v '^$' || true)

      # Cap History at displayLimit: oldest overflow goes to Trash, not a
      # hidden archive slice. Newest stay in History.
      count=$(printf '%s
' "$kept" | grep -c . || true)
      limit=$history_limit
      (( limit < 1 )) && limit=1
      if (( count > limit )); then
        overflow=$(printf '%s
' "$kept" | head -n $(( count - limit )))
        kept=$(printf '%s
' "$kept" | tail -n "$limit")
        while IFS= read -r line; do
          [[ -n $line ]] || continue
          printf '%s
' "$line" | jq -c --argjson trashedAt "$now" '. + {trashedAt: $trashedAt}' >> "$trash"
        done <<< "$overflow"
      fi

      # Absolute ceiling: if still over maxItems, trash oldest again.
      count=$(printf '%s
' "$kept" | grep -c . || true)
      if (( count > max_items )); then
        overflow=$(printf '%s
' "$kept" | head -n $(( count - max_items )))
        kept=$(printf '%s
' "$kept" | tail -n "$max_items")
        while IFS= read -r line; do
          [[ -n $line ]] || continue
          printf '%s
' "$line" | jq -c --argjson trashedAt "$now" '. + {trashedAt: $trashedAt}' >> "$trash"
        done <<< "$overflow"
      fi

      printf '%s
' "$kept" | grep -v '^$' > "$archive.tmp" || : > "$archive.tmp"
      mv -f "$archive.tmp" "$archive"
    fi
  fi

  if [[ -s $trash ]]; then
    if kept=$(jq -Rc --argjson cutoff "$trash_cutoff" \
        'fromjson? // empty | select((.trashedAt // .timestamp // 0) >= $cutoff)' "$trash" 2>/dev/null); then
      local dropped
      dropped=$(comm -23 \
        <(jq -r '.key // empty' "$trash" 2>/dev/null | sort -u) \
        <(printf '%s
' "$kept" | jq -r 'select(.key) | .key' 2>/dev/null | sort -u))
      printf '%s
' "$kept" | grep -v '^$' > "$trash.tmp" || : > "$trash.tmp"
      mv -f "$trash.tmp" "$trash"
      local key
      while IFS= read -r key; do
        [[ -n $key ]] || continue
        drop_images "$key"
      done <<< "$dropped"
    fi
  fi
}
