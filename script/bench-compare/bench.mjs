// The Node side of bench-compare: runs every case under one library and
// prints one JSON object. See README.md.
//
//   node bench.mjs <jsdom|happydom|linkedom> [--samples N] [--filter S]
//   node --expose-gc bench.mjs <engine> --memory     (in a fresh process)
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const BASE = "<!DOCTYPE html><html><head></head><body></body></html>";
const args = process.argv.slice(2);
const engine = args[0];
const opt = (name, dflt) => { const i = args.indexOf(name); return i < 0 ? dflt : args[i + 1]; };
const samples = Number(opt("--samples", 7));
const filter = opt("--filter", "");
const memory = args.includes("--memory");
const MEMORY_WINDOWS = Number(opt("--memory-windows", 20));

const factories = {
  async jsdom() {
    const { JSDOM } = await import("jsdom");
    return () => {
      const dom = new JSDOM(BASE, { url: "http://localhost/", pretendToBeVisual: true });
      return { window: dom.window, document: dom.window.document, close: () => dom.window.close() };
    };
  },
  async happydom() {
    const { Window } = await import("happy-dom");
    return () => {
      const window = new Window({ url: "http://localhost/" });
      window.document.write(BASE);
      return { window, document: window.document, close: () => window.happyDOM.close() };
    };
  },
  async linkedom() {
    const { parseHTML } = await import("linkedom");
    return () => {
      const { window, document } = parseHTML(BASE);
      return { window, document, close() {} };
    };
  },
};
if (!factories[engine]) throw new Error(`unknown engine ${engine}`);
const open = await factories[engine]();
const version = JSON.parse(fs.readFileSync(path.join(HERE, "node_modules", engine === "happydom" ? "happy-dom" : engine, "package.json"))).version;

const now = () => Number(process.hrtime.bigint()) / 1e6;
const median = (xs) => { const s = [...xs].sort((a, b) => a - b); return s[s.length >> 1]; };
const gc = () => { if (global.gc) { global.gc(); global.gc(); } };
const rssMB = () => process.memoryUsage().rss / 1048576;
// What the JS heap itself retains (V8 heap + external buffers): RSS is the
// cross-runtime yardstick, this is the allocator-independent cross-check.
const heapMB = () => { const m = process.memoryUsage(); return (m.heapUsed + m.external) / 1048576; };

function runCase(file) {
  // One indirect eval per case, so the case's functions live in this realm
  // (as they do for jsdom's own outside-only scripts) and reach the document
  // only through the window/document they are handed.
  const kase = (0, eval)(fs.readFileSync(file, "utf8"));
  const times = [];
  let checksum;
  for (let i = 0; i <= samples; i++) {        // sample 0 is the warm-up
    const ctx = open();
    try {
      kase.setup(ctx.window, ctx.document);
      const t0 = now();
      const value = kase.run(ctx.window, ctx.document);
      const dt = now() - t0;
      if (i > 0) times.push(dt);
      checksum = value;
    } catch (e) {
      return { error: String(e && e.message || e).split("\n")[0].slice(0, 80) };
    } finally {
      ctx.close();
    }
  }
  return { ms: median(times), min: Math.min(...times), checksum };
}

// Window cost, in its own fresh process (`--memory`) so the heap the timing
// runs grew cannot absorb it: opening a window, then the memory one holds —
// empty, and with the 2000-row table of 02-parse-innerhtml (about 18k nodes) —
// as the RSS growth of keeping MEMORY_WINDOWS of them alive.
function windowCost() {
  const table = (0, eval)(fs.readFileSync(path.join(HERE, "cases/02-parse-innerhtml.js"), "utf8"));
  const perWindowMB = (fill) => {
    gc();
    const before = rssMB();
    const heapBefore = heapMB();
    const kept = [];
    for (let i = 0; i < MEMORY_WINDOWS; i++) {
      const c = open();
      if (fill) { table.setup(c.window, c.document); table.run(c.window, c.document); delete c.window.__markup; }
      kept.push(c);
    }
    gc();
    const mb = (rssMB() - before) / MEMORY_WINDOWS;
    const heap = (heapMB() - heapBefore) / MEMORY_WINDOWS;
    kept.forEach((c) => c.close());
    return [mb, heap];
  };
  const baseline_mb = rssMB();
  const [empty_mb, empty_heap_mb] = perWindowMB(false);
  const [table_mb, table_heap_mb] = perWindowMB(true);
  const boot = [];
  for (let i = 0; i < samples; i++) { const t0 = now(); const c = open(); boot.push(now() - t0); c.close(); }
  return { boot_ms: median(boot), baseline_mb, empty_mb, table_mb, empty_heap_mb, table_heap_mb };
}

const result = { engine, version, runtime: `node ${process.version}` };
if (memory) {
  result.window = windowCost();
} else {
  result.cases = {};
  for (const f of fs.readdirSync(path.join(HERE, "cases")).sort()) {
    if (!f.endsWith(".js") || !f.includes(filter)) continue;
    result.cases[f.replace(/\.js$/, "")] = runCase(path.join(HERE, "cases", f));
  }
}
process.stdout.write(JSON.stringify(result) + "\n");
process.exit(0);
