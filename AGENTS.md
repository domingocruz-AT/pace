# Pace agent guide

Install with `sh install.sh` on macOS with Xcode Command Line Tools and working /usr/bin/python3. This builds locally and installs ~/Applications/Pace.app without launching.

Before launching, get explicit permission to read the user's existing ~/.codex/auth.json and send its access token only to chatgpt.com for usage retrieval. Never print, copy, or commit credentials. An install request alone does not grant credential access. Do not bypass macOS security protections.

Update from a clean main checkout with `sh update.sh`. Quit the app first, then relaunch after installation. Existing credential authorization persists. Settings remain in UserDefaults. No background updater or login item is installed.

Validate using `sh build.sh`, `node test_pace.cjs`, `/usr/bin/python3 -m unittest -v test_collector.py`, and the built executable with `--self-test` and `--hover-self-test`. Tests must not use live credentials. Preserve origin restrictions, redirect blocking, sanitized errors, and the embedded page's network restrictions.

Never publish generated apps, local diagnostics, personal screenshots, usage snapshots, or auth files. The docs site uses fictional sample data. Pace is independent of OpenAI and Airtable.
