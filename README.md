# Yet Another Notification Center

Omarchy bar widget: history, a 30-day trash, sounds, and auto-hide for toasts.

It does **not** replace `omarchy.notifications`. There is always exactly one
D-Bus notification daemon (`org.freedesktop.Notifications`). On Omarchy that
is the first-party service. This plugin watches the files it already writes,
copies each notification out, and keeps it.

Disable another notification-center widget before enabling this one, or you
get two bells.

## Why the default daemon stays

Omarchy's service owns the toasts, Do Not Disturb, action buttons, image
persistence, and the 10-file replay used by `showHistory`. Replacing it means
reimplementing all of that, and a broken plugin would leave the session with
no notifications at all.

You do **not** disable `omarchy.notifications`. If you did, this plugin would
have nothing to archive.

Auto-hide and sound sit on top of the daemon: auto-hide dismisses the live
toast stack after a timeout (including critical, which Omarchy never expires);
sound plays a freedesktop event when a notification is archived.

## Install

```bash
omarchy plugin add https://github.com/Loafer19/omarchy-yet-another-notification-center.git --enable
```

Local checkout (Omarchy refuses plugin symlinks — copy the folder):

```bash
rm -rf ~/.config/omarchy/plugins/yoyo.notification-center
cp -a . ~/.config/omarchy/plugins/yoyo.notification-center
omarchy plugin validate ~/.config/omarchy/plugins/yoyo.notification-center
omarchy plugin enable yoyo.notification-center --section right
omarchy restart shell
```

Open: click the bell, or `omarchy-shell yoyo.notification-center toggle`.
Right-click the bell for Do Not Disturb.

## Tabs

- **History** — newest first, grouped by day. Chips filter Omarchy's
  urgency (`-u low|normal|critical`): All / Critical / Normal / Low.
  Critical cards get a red stripe. `/` search. Dismiss → trash.
  Header: DND, Auto-hide, Clear (everything visible goes to trash).
- **Trash** — 30 days, then purged. Restore or empty.
- **Settings** — General (display limit, retention, click, badge) and Sound
  (master, a clip per urgency, mute while DND, per-app overrides as apps appear).

**Tab** cycles tabs · **h/l** chips · **j/k** rows · **Enter** acts · **x**
trashes / purges · **Esc** closes.

Clicking a card focuses the app, or opens an image path. It never runs the
command the notification arrived with.

## Where it is kept

```
~/.local/state/omarchy/yoyo.notification-center/
```

Mode `0700`. That is every notification you were sent. Removing the plugin
leaves the store:

```bash
omarchy plugin remove yoyo.notification-center
rm -rf ~/.local/state/omarchy/yoyo.notification-center
```

## Requirements

Omarchy with `omarchy.notifications`, plus `jq` and `inotifywait` (already
installed). Sounds use `canberra-gtk-play` or `pw-play`.
