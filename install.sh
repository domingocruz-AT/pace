#!/bin/sh
set -eu
cd "$(dirname "$0")"
[ "$(uname -s)" = Darwin ] || { echo 'Pace requires macOS.'; exit 1; }
xcrun --find swiftc >/dev/null 2>&1 || { echo 'Install Xcode Command Line Tools first.'; exit 1; }
/usr/bin/python3 --version >/dev/null 2>&1 || { echo 'System Python 3 is required.'; exit 1; }
sh build.sh
codesign --verify --deep --strict 'Codex Usage.app'
mkdir -p "$HOME/Applications"
ditto 'Codex Usage.app' "$HOME/Applications/Pace.app"
echo 'Installed ~/Applications/Pace.app. Read README.md before launching with your Codex sign-in.'
