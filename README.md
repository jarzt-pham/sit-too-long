# Sit Too Long

A tiny macOS menu bar app that reminds you to stand up and walk around after sitting at your Mac for too long.

The menu bar shows a standing figure and the minutes left until your next break (e.g. `🧍 32m`). When time is up, you hear a sound and get a notification: *"Time to stand up — walk around for a few minutes."*

## How it works

- It counts how long you have been **actively using** your Mac.
- No keyboard/mouse input for **5 minutes**, or the Mac goes to sleep → it assumes you got up and resets the counter.
- When the counter reaches your interval (default **40 minutes**), it plays a sound, shows a notification and starts counting again.

## Menu

| Item | What it does |
| --- | --- |
| Sitting for N min | Current sitting time |
| Remind every | Pick 20 / 30 / 40 / 45 / 60 / 90 min, or **Custom…** (1–480 min). Saved across restarts |
| Test reminder now | Fire a reminder immediately |
| I just stood up (reset) | Reset the counter to 0 |
| Pause / Resume | Stop or continue counting |
| Quit | Exit the app |

## Install

Requires macOS 12+ and the Xcode Command Line Tools (`xcode-select --install`).

```bash
curl -fsSL https://raw.githubusercontent.com/jarzt-pham/sit-too-long/main/install.sh | bash
```

This downloads the source, builds `Sit Reminder.app` into `~/Applications` and starts it. Run the same command again to update.

On first launch, click **Allow** when macOS asks for notification permission.

### Build from a clone

```bash
git clone https://github.com/jarzt-pham/sit-too-long.git
cd sit-too-long
./build.sh
open ~/Applications/"Sit Reminder.app"
```

### Start at login

System Settings → General → Login Items → **+** → choose `~/Applications/Sit Reminder.app`.

## Troubleshooting

**I hear the sound but no banner appears.** A Focus mode (Do Not Disturb, Work, …) is holding the notification in Notification Center. Allow the app: System Settings → Focus → *your Focus* → Allowed Notifications → Apps → Add → **Sit Reminder**.

**No notification at all.** Check System Settings → Notifications → Sit Reminder: notifications allowed, style **Banners** or **Alerts**. If notifications are turned off, the app shows a dialog instead.

## Uninstall

```bash
pkill -x SitReminder; rm -rf ~/Applications/"Sit Reminder.app"; defaults delete local.sitreminder
```
