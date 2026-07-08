# Calendar testing tools

Scripts for driving and inspecting the running Electron app without relying on
fragile OS-level pixel-coordinate clicking. Written while building this app;
see `../CLAUDE.md` for why this exists and the `ELECTRON_RUN_AS_NODE` gotcha.

## 1. Launch with a debug port

```bash
cd Calendar
env -u ELECTRON_RUN_AS_NODE ./node_modules/electron/dist/electron.exe --remote-debugging-port=9222 . &
```

Get the page's WebSocket debugger URL:

```bash
curl -s http://localhost:9222/json | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{console.log(JSON.parse(d)[0].webSocketDebuggerUrl)})"
```

**Always confirm exactly one `Calendar`-titled process is running before trusting
this URL** — a leftover process from a previous run can keep an old debug
server bound to the same port, silently serving stale (pre-edit) code:

```powershell
Get-Process | Where-Object { $_.ProcessName -like "*electron*" } | Stop-Process -Force -ErrorAction SilentlyContinue
# ...then relaunch, then:
Get-Process | Where-Object { $_.MainWindowTitle -eq "Calendar" }   # should show exactly one
```

## 2. Inspect state / call functions directly

```bash
export CDP_WS_URL="ws://localhost:9222/devtools/page/<id-from-above>"
node tools/cdp-eval.js "data.bands.length"
node tools/cdp-eval.js "monthLabelEl.textContent"
```

Any expression the app's own script scope can see works here — including
calling its internal functions directly (`jumpToMonth(2026, 9)`,
`getSingles('2026-07-15')`, etc.), which is often faster than driving the UI
when you just need to check data-layer logic.

## 3. Drive real gestures (click / long-press / drag / scroll)

Write a scenario file that exports `async function(cdp) { ... }`, then:

```bash
node tools/cdp-drive.js path/to/scenario.js
```

`cdp` gives you `eval`, `mouseMove/mouseDown/mouseUp(x, y)`, `wheel(x, y, dx, dy)`,
and `sleep(ms)`. Real `Input.dispatchMouseEvent` calls are essential for
anything gesture-timing-sensitive (this app's long-press vs. click vs.
drag-to-create-band all hinge on a 450ms/4px threshold) — synthetic
`dispatchEvent(new MouseEvent(...))` calls don't reliably exercise the same
code path.

Example scenario (click a cell, type text, confirm):

```js
module.exports = async function (cdp) {
  const rect = await cdp.eval(`
    (() => {
      const cell = document.querySelector('.dayCell[data-date="2026-07-15"]');
      const r = cell.getBoundingClientRect();
      return { left: r.left, top: r.top, width: r.width, height: r.height };
    })()
  `);
  const x = rect.left + rect.width / 2, y = rect.top + rect.height / 2;
  await cdp.mouseMove(x, y);
  await cdp.mouseDown(x, y);
  await cdp.sleep(80);   // short — stays under the long-press threshold
  await cdp.mouseUp(x, y);
  await cdp.sleep(150);
  return cdp.eval(`!!document.querySelector('.quickInput')`);
};
```

## 4. Debugging "a value is changing and I don't know why"

If your own instrumentation (wrapping a function to log before/after) looks
clean but the observed behavior still doesn't match, something *outside your
code* may be mutating the same value (a browser heuristic, not a bug in your
JS). Intercept the DOM property itself instead of the function:

```js
let proto = Object.getPrototypeOf(gridScroll);
let desc = null;
while (proto) { desc = Object.getOwnPropertyDescriptor(proto, 'scrollTop'); if (desc) break; proto = Object.getPrototypeOf(proto); }
const nativeGet = desc.get, nativeSet = desc.set;
Object.defineProperty(gridScroll, 'scrollTop', {
  get() { return nativeGet.call(this); },
  set(v) { console.log('scrollTop set to', v, new Error().stack); nativeSet.call(this, v); },
  configurable: true
});
```

This is exactly how the month-header scroll-flip bug (2026-07-09) was traced to
Chromium's scroll-anchoring feature double-adjusting `scrollTop` — see the
Calendar entry in the Obsidian 学習記録 for the full story.

## 5. Screenshots (visual sanity check, not for precise interaction)

```powershell
. .\tools\screenshot-helpers.ps1
Take-CalScreenshot "C:\path\to\out.png"
```

`Send-CalWheel`/`Click-CalAt` also exist for OS-level input, but prefer the CDP
route above for anything where exact timing or coordinates matter — OS-level
`SetForegroundWindow`/`mouse_event` proved unreliable for pinpoint clicks
(button positions shift with content, DPI scaling confuses coordinates) during
this app's own testing.
