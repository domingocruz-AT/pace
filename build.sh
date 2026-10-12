#!/bin/sh
set -eu
cd "$(dirname "$0")"
app="$(pwd)/Codex Usage.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -O -whole-module-optimization -parse-as-library Island.swift PaceWeb.swift -o "$app/Contents/MacOS/CodexUsage" -framework AppKit -framework SwiftUI -framework Charts -framework WebKit -module-cache-path /tmp/codex-usage-swift-cache
cp pace.html pace.js "$app/Contents/Resources/"
cp collector.py "$app/Contents/Resources/collector.py"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexUsage</string>
<key>CFBundleIdentifier</key><string>local.domingocruz.codex-usage</string>
<key>CFBundleName</key><string>Codex Usage</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
