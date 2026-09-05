.pragma library

var CONFIG = {
  "defaults": {
    "displayLimit": 50,
    "keepDays": 30,
    "maxItems": 1000,
    "trashDays": 30,
    "autoHideMs": 0,
    "soundEnabled": true,
    "defaultSound": "message-new-instant",
    "soundLow": "complete",
    "soundNormal": "message-new-instant",
    "soundCritical": "dialog-warning",
    "muteSoundWhenDnd": true,
    "appSounds": {},
    "badge": "Dot",
    "clickAction": "Auto",
    "showBody": true,
    "showPreview": true
  },
  "sounds": [
    { "id": "mute", "label": "Mute" },
    { "id": "message-new-instant", "label": "Message" },
    { "id": "dialog-warning", "label": "Warning" },
    { "id": "dialog-error", "label": "Error" },
    { "id": "complete", "label": "Complete" },
    { "id": "bell", "label": "Bell" },
    { "id": "camera-shutter", "label": "Camera" },
    { "id": "alarm-clock-elapsed", "label": "Alarm" },
    { "id": "phone-incoming-call", "label": "Call" }
  ],
  "soundAliases": {
    "email": "message-new-instant",
    "message": "message-new-instant",
    "warning": "dialog-warning",
    "camera": "camera-shutter"
  },
  "limits": {
    "displayLimit": { "min": 10, "max": 500, "step": 10, "fallback": 50 },
    "keepDays": { "min": 1, "max": 365, "step": 1, "fallback": 30 },
    "trashDays": { "min": 1, "max": 365, "step": 1, "fallback": 30 },
    "maxItems": { "min": 50, "max": 10000, "step": 50, "fallback": 1000 },
    "autoHideMs": { "min": 0, "max": 30000, "step": 1000, "fallback": 0 }
  },
  "enums": {
    "badge": ["Dot", "Highlight", "Count", "None"],
    "clickAction": ["Auto", "Focus the app", "Nothing"]
  }
}
