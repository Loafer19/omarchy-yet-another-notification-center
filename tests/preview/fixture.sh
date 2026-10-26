#!/usr/bin/env bash
# Made-up store for tools/render-previews.sh:  fixture.sh STATE_DIR
# Writes a throwaway XDG_STATE_HOME (settings, archive, trash) with invented
# notifications timed relative to now, so the preview never shows a real
# notification and never ages out of the 30-day window.
set -euo pipefail
st=$1
case $st in "${TMPDIR:-/tmp}"/*) ;; *) echo "fixture: refusing $st (not under ${TMPDIR:-/tmp})" >&2; exit 1 ;; esac
s=$st/omarchy/yoyo.notification-center
mkdir -p "$st/omarchy/notifications" "$s/images"
printf '[]\n' > "$st/omarchy/notifications/live.json"
printf '[]\n' > "$st/omarchy/notifications/history.json"
printf '{"dnd":false}\n' > "$st/omarchy/notifications.json"
jq -nc '{displayLimit:50,keepDays:30,maxItems:1000,trashDays:30,autoHideMs:8000,soundEnabled:true,
  defaultSound:"message-new-instant",soundLow:"complete",soundNormal:"message-new-instant",soundCritical:"dialog-warning",
  muteSoundWhenDnd:true,appSounds:{"Chat":"bell"},badge:"Dot",clickAction:"Auto",showBody:true,showPreview:true}' > "$s/settings.json"
ago() { echo $(( ($(date +%s) - $1 * 60) * 1000 )); }   # minutes ago -> ms
printf '%s' "$(ago 1)" > "$s/seen"
magick -size 96x96 gradient:'#4a7fbf-#d9825b' "$s/images/k5-preview.png"
e() { # key app icon summary body urgency minutes-ago preview
  jq -nc --arg key "$1" --arg app "$2" --arg icon "$3" --arg sum "$4" --arg body "$5" --argjson u "$6" \
    --argjson t "$(ago "$7")" --arg prev "$8" \
    '{key:$key,app:$app,appIcon:$icon,summary:$sum,body:$body,image:"",preview:$prev,file:"",glyph:"",urgency:$u,timestamp:$t}'
}
{
  e k1 "Downloads" "" "Download finished" "omarchy.iso · 2.1 GB" 1 2950 ""
  e k2 "Chat" "" "Alex: standup moved to 10:30" "Can everyone make it? Otherwise async notes in #team" 1 1600 ""
  e k3 "Disk" "" "Disk almost full" "/home has 3% free space left" 2 1500 ""
  e k4 "Music" "" "Now playing" "Example Artist — Example Track" 0 300 ""
  e k5 "Screenshot" "" "Screenshot saved" "~/Pictures/screenshot.png" 1 95 "file://$s/images/k5-preview.png"
  e k6 "Messages" "" "Sam" "A longer message body that wraps onto a second line in the card so you can see how the text is clipped." 1 40 ""
  e k7 "Battery" "" "Battery critically low" "5% remaining — plug in now" 2 12 ""
} > "$s/archive.jsonl"
{
  e t1 "Chat" "" "New message in #general" "lol" 1 3000 "" | jq -c --argjson x "$(ago 600)" '. + {trashedAt:$x}'
  e t2 "Updates" "" "12 updates available" "" 0 2900 "" | jq -c --argjson x "$(ago 600)" '. + {trashedAt:$x}'
  e t3 "Mail" "" "Invoice overdue" "Invoice #4411 is 7 days overdue" 2 2800 "" | jq -c --argjson x "$(ago 600)" '. + {trashedAt:$x}'
} > "$s/trash.jsonl"
