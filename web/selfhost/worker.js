// Worker variant of the driver (`index.html?worker=1`): keeps the page responsive but the stack is too small for larger inputs.
import { runSource } from "./driver.js";
self.onmessage = async (ev) => {
  try {
    const code = await runSource({ ...ev.data, onOut: (s) => self.postMessage({ out: s }), onStatus: (s) => self.postMessage({ status: s }) });
    self.postMessage({ done: code });
  } catch (e) {
    self.postMessage({ out: `\n[internal error] ${e && e.stack || e}\n`, done: 1 });
  }
};
