// One-shot CDP client: evaluate a single JS expression inside the running Electron
// renderer and print the result. Good for quick state checks (e.g. "data.bands.length").
//
// Usage:
//   node tools/cdp-eval.js "<JS expression>"
//   (requires env var CDP_WS_URL — see tools/README.md for how to get it)
const wsUrl = process.env.CDP_WS_URL;
const expr = process.argv[2];

if (!wsUrl || !expr) {
  console.error('Usage: CDP_WS_URL=ws://... node tools/cdp-eval.js "<expression>"');
  process.exit(1);
}

const ws = new WebSocket(wsUrl);
let id = 1;

ws.addEventListener('open', () => {
  ws.send(JSON.stringify({ id: id++, method: 'Runtime.evaluate', params: { expression: expr, returnByValue: true, awaitPromise: true } }));
});

ws.addEventListener('message', (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.id) {
    if (msg.result && msg.result.result) {
      console.log(JSON.stringify(msg.result.result.value ?? msg.result.result.description, null, 2));
    } else if (msg.result && msg.result.exceptionDetails) {
      console.error(JSON.stringify(msg.result.exceptionDetails, null, 2));
    } else {
      console.log(JSON.stringify(msg, null, 2));
    }
    ws.close();
    process.exit(0);
  }
});

ws.addEventListener('error', (e) => { console.error('WS error', e.message); process.exit(1); });
setTimeout(() => { console.error('timeout'); process.exit(1); }, 5000);
