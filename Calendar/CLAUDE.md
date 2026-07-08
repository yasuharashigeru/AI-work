# Calendar — notes for Claude Code

Personal calendar app, Electron + vanilla JS, single-file style matching
`../Traqr/index.html`'s conventions (white background, gray gridlines, Meiryo
font, no framework). Spec lives at the Obsidian vault's
`Claude\⚪︎App-Idea\カレンダー.md`.

## This is NOT a web app like Traqr

`index.html` here `require('electron')`, `require('fs')`, and
`require('japanese-holidays')` directly in its inline `<script>` — it only
works loaded inside Electron (via `main.js`, which enables
`nodeIntegration`/disables `contextIsolation` for exactly this reason). Opening
this file in a plain browser will throw immediately (`require is not
defined`). Always launch through `main.js`, never just open the HTML.

## Launching for testing (this sandboxed shell)

The Bash/PowerShell tool environment in this Claude Code setup has
`ELECTRON_RUN_AS_NODE=1` set (inherited from the host), which makes
`electron.exe` run as plain Node — `app`/`BrowserWindow`/`ipcMain` are all
`undefined` and nothing visibly launches. Always unset it first:

```bash
cd Calendar
env -u ELECTRON_RUN_AS_NODE ./node_modules/electron/dist/electron.exe .
```

(Confirmed: `electron.exe --version` prints a Node version with the var set,
the real Electron version once unset.) A normal terminal the user opens
themselves does not have this set — plain `npm start` is correct advice for
the user.

## Testing interactions

See `tools/README.md` — drive the app over Chrome DevTools Protocol
(`--remote-debugging-port=9222` + Node's built-in `WebSocket`) rather than
OS-level pixel-coordinate clicking, which proved fragile here (DPI scaling,
layout-dependent button positions). The `tools/` scripts are the reusable
harness that came out of building this app; extend them rather than
reinventing a CDP client each session.

## Known-tricky area: the virtualized week scroll

`prependWeeks`/`appendWeeks` in `index.html` compensate `gridScroll.scrollTop`
manually to keep the infinite-scroll illusion jump-free. The row-height reflow
they trigger (`applyRowHeights`, called from `insertFront`/`insertBack`) can
provoke Chromium's scroll-anchoring heuristic into applying its *own*
competing scrollTop correction — this caused a real bug (month header briefly
snapping back after correctly advancing) fixed 2026-07-09 by adding
`overflow-anchor: none` to `#gridScroll`. If you ever touch this virtualization
logic again, re-verify with `tools/cdp-drive.js` driving real wheel events
across several month boundaries in both directions, checking a computed
absolute date position never regresses — the bug did not reproduce with
simple before/after snapshot testing, only with a continuous fine-grained
trace.

## Status

M0–M7 done (grid, scroll, single events, detail modal, band events, palette
recolor, polish). M8 (electron-builder packaging into a distributable .exe)
not started.
