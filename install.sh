#!/bin/bash
# One-line installer: downloads the source, builds "Sit Reminder.app" into ~/Applications and starts it.
set -euo pipefail

if ! command -v swiftc >/dev/null 2>&1; then
    echo "swiftc not found. Install the Xcode Command Line Tools first: xcode-select --install" >&2
    exit 1
fi

SRC="$(mktemp -d)"
trap 'rm -rf "$SRC"' EXIT
curl -fsSL https://github.com/jarzt-pham/sit-too-long/archive/refs/heads/main.tar.gz | tar xz -C "$SRC" --strip-components=1

pkill -x SitReminder 2>/dev/null || true
"$SRC/build.sh"
open ~/Applications/"Sit Reminder.app"
echo "Sit Reminder is running — look for the standing figure in your menu bar."
