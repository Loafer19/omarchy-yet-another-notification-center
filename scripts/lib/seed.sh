# shellcheck shell=bash
# Demo rows for screenshots and manual testing. Sourced by backend.sh.

cmd_seed() {
  ensure_store
  local count=${1:-16}
  [[ $count =~ ^[0-9]+$ ]] || count=16
  (( count > 48 )) && count=48
  with_lock seed_entries "$count"
  printf '{"ok":true,"seeded":%s}\n' "$count"
}

# app|icon|summary|body|minutesAgo|urgency (0 low / 1 normal / 2 critical)
readonly SEED_ROWS=(
  "Slack|slack|#design from Mara|Pushed the new empty state|4|1"
  "Signal|signal-desktop|Jules|Are we still on for Thursday?|55|1"
  "Chromium|chromium|Calendar|Standup starts in 10 minutes|38|2"
  "Spotify|spotify|Talk Talk|Life's What You Make It|12|0"
  "omarchy||Reminder|Stand up and walk about|96|0"
  "Thunderbird|thunderbird|Invoice paid|Nova Systems paid invoice 2026-114|190|1"
  "Discord|discord|#homelab|that fan curve fixed it|260|0"
  "Slack|slack|#ops|Deploy is live on production|140|2"
  "Signal|signal-desktop|Mum|Landed, all fine|1180|1"
  "omarchy||Update available|17 packages|520|1"
  "Chromium|chromium|GitHub|CI passed|3300|0"
  "Thunderbird|thunderbird|Domain renewal|renews in 14 days|1580|2"
)

seed_entries() {
  local count=${1:-16} i row stamp key app icon summary body minutes urgency
  local total=${#SEED_ROWS[@]}
  for (( i = 0; i < count; i++ )); do
    row=${SEED_ROWS[$((i % total))]}
    IFS='|' read -r app icon summary body minutes urgency <<< "$row"
    [[ $urgency =~ ^[0-2]$ ]] || urgency=1
    stamp=$(( $(now_ms) - (minutes + (i / total) * 2880) * 60000 ))
    key="seed-$stamp-$i"
    jq -cn \
      --arg key "$key" \
      --arg app "$app" \
      --arg appIcon "$icon" \
      --arg summary "$summary" \
      --arg body "$body" \
      --argjson timestamp "$stamp" \
      --argjson urgency "$urgency" \
      '{key:$key, app:$app, appIcon:$appIcon, summary:$summary, body:$body,
        image:"", preview:"", file:"", glyph:"", urgency:$urgency, timestamp:$timestamp}' >> "$archive"
  done
  jq -sc 'sort_by(.timestamp) | .[]' "$archive" > "$archive.tmp" && mv -f "$archive.tmp" "$archive"
}
