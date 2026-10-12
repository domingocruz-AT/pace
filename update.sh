#!/bin/sh
set -eu
cd "$(dirname "$0")"
[ -z "$(git status --porcelain)" ] || { echo 'Commit or stash local changes before updating.'; exit 1; }
[ "$(git branch --show-current)" = main ] || { echo 'Switch to main before updating.'; exit 1; }
git pull --ff-only origin main
sh install.sh
