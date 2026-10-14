#!/bin/bash
# Builds "Sit Reminder.app" and installs it into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Sit Reminder.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -target "$(uname -m)-apple-macos13" main.swift -o "$APP/Contents/MacOS/SitReminder"
codesign --force -s - "$APP"

mkdir -p ~/Applications
rm -rf ~/Applications/"Sit Reminder.app"
cp -R "$APP" ~/Applications/
echo "Installed to ~/Applications/Sit Reminder.app"
