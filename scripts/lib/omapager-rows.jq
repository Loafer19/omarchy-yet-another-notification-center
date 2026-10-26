# New omapager rows -> archive entries (backend.sh ingest_engine).
# Input: rows of live.json/history.json (jq -n, one object each).
# $have: keys already known (archive, trash, ledger); each key is taken once.
# link: the first web address in the text, else the site a browser
# notification came from (its source). _exec: the click command, for the
# screenshot preview (dropped again by engine_finish).
def icon: tostring | if test("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$") and (contains("..") | not)
                     then . else "" end;
def ms: (tonumber? // 0) | if . > 0 then (. * 1000 | round) else 0 end;
def weburl: if type == "string" and length <= 2048
               and test("^https?://[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*(:[0-9]{1,5})?([/?#][^\\s<>\"'\\\\]*)?$")
               and (explode | any(. < 32 or (. >= 127 and . < 160)) | not)
            then . else "" end;
def link: . as $row | ((($row.rawBody // "") | tostring) + " " + (($row.body // "") | tostring)) as $b
  | ([ ($b | [scan("href=[\"'](https?://[^\"'<>\\s]+)[\"']")] | map(.[0]) | .[]),
       ($b | gsub("<[^>]*>"; " ") | [scan("https?://[^\\s<>\"']+")] | .[]
           | sub("[).,;:!?]+$"; "")) ]
     | map(gsub("&amp;"; "&") | weburl) | map(select(. != "")) | first) // ""
  | if . != "" then .
    else (($row.source // "") | tostring | ascii_downcase
          | if test("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$")
            then "https://" + . + "/" else "" end)
    end;
def redacted: .summary == "Verification notification" and .body == "[redacted]";
reduce inputs as $r ({k: ($have | map({(.): true}) | add // {}), out: []};
  if .k[$r.key] then . else .k[$r.key] = true | .out += [$r] end)
| .out[]
| (if redacted then "" else link end) as $link
| ((.execArgv // "") | if type == "string" then . elif type == "array" then tojson else "" end) as $exec
| {
    key: .key,
    app: ((.app // "") | tostring | .[0:64]),
    appIcon: ((.appIcon // "") | icon),
    summary: ((.summary // "") | tostring | .[0:240]),
    body: ((.body // "") | tostring | .[0:500]),
    image: "",
    preview: "",
    file: "",
    glyph: ((.glyph // "") | tostring | .[0:8]),
    urgency: (if (.urgency | tonumber? // 1) >= 2 then 2
              elif (.urgency | tonumber? // 1) <= 0 then 0
              else 1 end),
    timestamp: (((.ts // 0) | ms) as $t
                | if $t > 0 then $t else ((.closed_ts // 0) | ms) end)
  }
| if $link != "" then .link = $link else . end
| ._exec = $exec
