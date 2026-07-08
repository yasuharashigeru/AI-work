// CDP client that can both Runtime.evaluate and dispatch real Input events
// (mousedown/move/up, wheel), so gesture timing (click vs long-press vs drag) and
// real scrolling can be exercised the same way a human would, instead of faking it
// with synthetic DOM events.
//
// Usage:
//   node tools/cdp-drive.js path/to/scenario.js
//   (requires env var CDP_WS_URL — see tools/README.md; scenario.js must
//   `module.exports = async function(cdp) { ... return someResult; }`)
//
// cdp.eval(expr)                     -> Runtime.evaluate, returns the value
// cdp.mouseMove/mouseDown/mouseUp(x,y) -> real Input.dispatchMouseEvent
// cdp.wheel(x, y, deltaX, deltaY)    -> real mouse wheel scroll
// cdp.sleep(ms)
const wsUrl = process.env.CDP_WS_URL;
const script = process.argv[2];

if (!wsUrl || !script) {
  console.error('Usage: CDP_WS_URL=ws://... node tools/cdp-drive.js path/to/scenario.js');
  process.exit(1);
}

const ws = new WebSocket(wsUrl);
let id = 1;
const pending = new Map();

function send(method, params) {
  return new Promise((resolve, reject) => {
    const mid = id++;
    pending.set(mid, { resolve, reject });
    ws.send(JSON.stringify({ id: mid, method, params }));
  });
}

ws.addEventListener('message', (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.id && pending.has(msg.id)) {
    const { resolve, reject } = pending.get(msg.id);
    pending.delete(msg.id);
    if (msg.error) reject(new Error(JSON.stringify(msg.error)));
    else resolve(msg.result);
  }
});

ws.addEventListener('open', async () => {
  try {
    const cdp = {
      eval: async (expression) => {
        const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
        if (r.exceptionDetails) throw new Error(JSON.stringify(r.exceptionDetails));
        return r.result.value;
      },
      mouseMove: (x, y) => send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y }),
      mouseDown: (x, y) => send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 }),
      mouseUp: (x, y) => send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 }),
      wheel: (x, y, deltaX, deltaY) => send('Input.dispatchMouseEvent', { type: 'mouseWheel', x, y, deltaX, deltaY }),
      sleep: (ms) => new Promise(r => setTimeout(r, ms)),
    };
    const fn = require(require('path').resolve(script));
    const result = await fn(cdp);
    console.log(JSON.stringify(result, null, 2));
  } catch (e) {
    console.error('ERROR', e.message);
    process.exitCode = 1;
  } finally {
    ws.close();
    process.exit();
  }
});

ws.addEventListener('error', (e) => { console.error('WS error', e.message); process.exit(1); });
setTimeout(() => { console.error('timeout'); process.exit(1); }, 15000);
