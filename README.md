# Pace

A small macOS edge widget for Work and Codex usage. Hover for daily usage, explore models, and keep personal spending targets in view.

**Experimental and independent of OpenAI and Airtable.** Undocumented ChatGPT endpoints can change. Estimates are not invoices; personal targets do not enforce spending limits.

## Install with your agent

Ask your agent to install https://github.com/domingocruz-AT/pace by following AGENTS.md. It can build locally, then ask permission to use your existing Codex sign-in.

## Manual installation

Requires macOS, Xcode Command Line Tools (Swift), and working `/usr/bin/python3`. Node is only needed for tests. Builds target your local architecture. Compatibility beyond the author's Mac is not yet established.

```sh
git clone https://github.com/domingocruz-AT/pace.git
cd pace
sh install.sh
```

The installer does not launch the app. Opening `~/Applications/Pace.app` reads your existing `~/.codex/auth.json` and sends its access token only to `chatgpt.com` for usage requests. Sign in to Codex with ChatGPT first. Launch only if you consent to this access. Credentials are never copied to the repository or web view.

Pace is ad-hoc signed locally, not notarized. Do not disable macOS security protections to run it.

## Update

Quit Pace. From your clean main checkout:

```sh
sh update.sh
```

Reopen ~/Applications/Pace.app. Preferences persist. Updates track main with fast-forward-only pulls and do not discard local edits. There is no background updater or login item.

## Controls and data

- Hover to expand. Drag away from an edge to become a circle; release to dock.
- Day, week, and month have calendar navigation. Last 30/60/90 always end today in UTC.
- Tokens include input, cached input, and output. Switch to estimated cost and inspect models.
- Edit daily/monthly targets in the dashboard. Targets track spending; they do not block it.

Usage refreshes about once per minute. Reporting can lag. Older empty responses cannot distinguish no usage from unavailable history.

## Architecture and checks

Swift/AppKit controls the native shell. SwiftUI hosts bundled HTML/CSS/JavaScript in WKWebView. Python standard-library code retrieves usage with redirect and inherited-proxy blocking. No hosted backend is required. GitHub Pages serves only the marketing site in docs/.

```sh
sh build.sh
node test_pace.cjs
/usr/bin/python3 -m unittest -v test_collector.py
'./Codex Usage.app/Contents/MacOS/CodexUsage' --self-test
'./Codex Usage.app/Contents/MacOS/CodexUsage' --hover-self-test
```

Remove ~/Applications/Pace.app after quitting to uninstall. Preferences remain in the local `local.domingocruz.codex-usage` domain.
