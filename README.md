# Yet Another Notification Center

Omarchy bar widget: notification history, trash, sounds, and auto-hide.

![History tab](preview.png)

Uses Omarchy's `omarchy.notifications` service — leave it enabled. Disable any other notification-center widget first, or you get two bells.

- **History** — search (`/`), urgency chips, DND, auto-hide, dismiss to trash
- **Trash** — restore or empty; keep days from Settings
- **Settings** — General, Sound (Play per clip), Apps

**Tab** cycles tabs · **h/l** chips · **j/k** rows · **Enter** acts · **x** trashes · **Esc** closes

## Requirements

Omarchy with its notification service (`omarchy.notifications`) and
`omarchy-shell`. Most of these ship with Omarchy; Arch package in brackets.

Required:

- `bash`, coreutils (`timeout`, `realpath`, `stat`, `date`, `head`), `awk`, `sed`, `grep`
- `jq` [jq] — the store is JSON
- `flock` [util-linux] — locks the store
- `inotifywait` [inotify-tools] — follows new notifications (`watch` exits without it)

Optional — the feature is skipped or shows an error without it:

- `file` [file] — check notification icons/images before copying them
- `magick` [imagemagick] — shrink large image previews
- `pw-play` [pipewire-audio] + freedesktop sounds [sound-theme-freedesktop],
  or `canberra-gtk-play` [libcanberra] — notification sounds
- `wl-copy` [wl-clipboard] — Copy
- `xdg-open` [xdg-utils] — open a notification's picture
- `omarchy-hyprland-focus-app` (Omarchy) — click a row to focus the app

## Install

```sh
omarchy plugin add https://github.com/Loafer19/omarchy-yet-another-notification-center.git --enable
```

## Usage

Click the bell to open the panel. Right-click toggles Do Not Disturb. Escape closes.

## Configure

```sh
omarchy bar move yoyo.notification-center --section right
```

## Settings

Change settings in the panel's **Settings** tab. They are stored in one place:

```
~/.local/state/omarchy/yoyo.notification-center/settings.json
```

Everything reads and writes that file through the plugin's backend
(`scripts/backend.sh settings-get` / `settings-set`), which fills in defaults
and clamps values using `defaults.js` (shared with the QML). The widget has no
settings in Omarchy's own widget-settings dialog — values there would be a
second copy. You may edit `settings.json` by hand; invalid or out-of-range
values fall back to the defaults in `defaults.js`.

## Development

```sh
tests/run.sh
```

Checks the vendored UI kit, runs the Model.js tests with Node and the
backend tests against a temporary store (your notifications are never
touched). `tests/autohide.sh` runs the real service in Quickshell (`qs`,
offscreen) against a fake toast stack and times auto-hide. Also needs `node`.

## Remove

```sh
omarchy plugin remove yoyo.notification-center
rm -rf ~/.local/state/omarchy/yoyo.notification-center
```
