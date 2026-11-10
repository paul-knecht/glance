#!/bin/bash
# Builds Glance and installs it into /Applications, replacing an older copy.
# Run from the project folder:  ./scripts/install.sh
set -e
cd "$(dirname "$0")/.."

echo "Building…"
xcodebuild -project Glance.xcodeproj -scheme Glance -configuration Release \
    -derivedDataPath build build > build-install.log 2>&1 || {
    echo "The build failed. See build-install.log."; exit 1; }
rm -f build-install.log

# Stop a running copy, then replace the installed app.
pkill -x Glance || true
sleep 1
rm -rf /Applications/Glance.app
cp -R build/Build/Products/Release/Glance.app /Applications/Glance.app

# Remove the built copies from the project folder. Otherwise Spotlight
# offers several apps called Glance, and it is easy to start the wrong one.
rm -rf build/Build/Products/Release/Glance.app build/Build/Products/Debug/Glance.app

open /Applications/Glance.app
echo "Installed and started /Applications/Glance.app"
echo "macOS treats a new build as a new app. If the hotkey only shows the"
echo "permission message, run:  tccutil reset Accessibility local.glance"
echo "and switch Glance on again under Privacy & Security > Accessibility."
