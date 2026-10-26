# A legacy notification file -> archive entry (backend.sh ingest_file).
# $key, $appIcon, $image, $preview come from the backend; every text is cut
# to a fixed length, urgency clamped to 0..2, and a missing timestamp taken
# from the key (MS-…).
{
  key: $key,
  app: ((.app // "") | tostring | .[0:64]),
  appIcon: $appIcon,
  summary: ((.summary // "") | tostring | .[0:240]),
  body: ((.body // "") | tostring | .[0:500]),
  image: $image,
  preview: $preview,
  file: "",
  glyph: ((.glyph // "") | tostring | .[0:8]),
  urgency: (if (.urgency | tonumber? // 1) >= 2 then 2
            elif (.urgency | tonumber? // 1) <= 0 then 0
            else 1 end),
  timestamp: (.timestamp // 0)
}
| .timestamp = (if .timestamp > 0 then .timestamp
                else ((.key | split("-")[0] | tonumber?) // 0) end)
