#!/bin/bash
# Builds PeripheralConformanceCentral.app (a macOS app, so that it can ask for the Bluetooth
# permission) into the given directory (default: ./build) and runs it, printing its output.
#
# Usage: build-peripheral-conformance-central.sh [output-dir] [all]
#   all - scan without a service filter and log all advertisements
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$DIR/build}"
APP="$OUT/PeripheralConformanceCentral.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -o "$APP/Contents/MacOS/PeripheralConformanceCentral" "$DIR/PeripheralConformanceCentral.swift" -framework CoreBluetooth
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.nordicsemi.PeripheralConformanceCentral</string>
<key>CFBundleName</key><string>PeripheralConformanceCentral</string>
<key>CFBundleExecutable</key><string>PeripheralConformanceCentral</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSBluetoothAlwaysUsageDescription</key><string>Plays the central role in the peripheral conformance tests.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
rm -f "$OUT/central.log"
open -W -n --stdout "$OUT/central.log" --stderr "$OUT/central.log" "$APP" --args $2
cat "$OUT/central.log"
