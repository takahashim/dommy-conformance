#!/usr/bin/env node
// The browser side of the differential harness: run every case in headless
// Chromium and write one JSON line per case.
//
//   node runner/chromium.js [--filter substring] [--out results/chromium.jsonl]
//
// Playwright is resolved from wherever it is installed (a local node_modules, a
// global install, or PLAYWRIGHT_PATH) so the repo needs no package.json of its
// own; the browser comes from PLAYWRIGHT_BROWSERS_PATH or Playwright's default.
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");

function loadPlaywright() {
  const candidates = [
    process.env.PLAYWRIGHT_PATH,
    "playwright",
    "/opt/node22/lib/node_modules/playwright",
    "/usr/lib/node_modules/playwright",
    "/usr/local/lib/node_modules/playwright"
  ].filter(Boolean);
  for (const candidate of candidates) {
    try {
      return require(candidate);
    } catch (error) {
      if (error.code !== "MODULE_NOT_FOUND") throw error;
    }
  }
  throw new Error(
    "playwright not found. Install it (npm i -g playwright) or set PLAYWRIGHT_PATH."
  );
}

function parseArgs(argv) {
  const args = { filter: null, out: path.join(ROOT, "results/chromium.jsonl") };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--filter") args.filter = argv[++i];
    else if (argv[i] === "--out") args.out = argv[++i];
  }
  return args;
}

// Every *.js under cases/, as repo-relative ids so both runners agree on names.
function caseFiles(filter) {
  const out = [];
  (function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith(".js")) out.push(path.relative(path.join(ROOT, "cases"), full));
    }
  })(path.join(ROOT, "cases"));
  return filter ? out.filter((id) => id.includes(filter)) : out;
}

const BLANK = "<!DOCTYPE html><html><head></head><body></body></html>";

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const { chromium } = loadPlaywright();
  const harness = fs.readFileSync(path.join(ROOT, "lib/harness.js"), "utf8");
  const ids = caseFiles(args.filter);

  const browser = await chromium.launch({ args: ["--no-sandbox"] });
  const lines = [];
  try {
    for (const id of ids) {
      const source = harness + "\n" + fs.readFileSync(path.join(ROOT, "cases", id), "utf8");
      let record;
      try {
        const page = await browser.newPage();
        // setContent navigates, so the case's own document is a real parse of
        // its own markup rather than markup injected into a blank one.
        await page.setContent(BLANK);
        const html = await page.evaluate(`(() => { ${source}\n; return __oracleHtml(); })()`);
        await page.setContent("<!DOCTYPE html><html><head></head><body>" + html + "</body></html>");
        record = await page.evaluate(`(async () => { ${source}\n; return __oracleRun(); })()`);
        await page.close();
      } catch (error) {
        record = { error: "runner: " + (error && error.message ? error.message : String(error)) };
      }
      lines.push(JSON.stringify({ case: id, engine: "chromium", ...record }));
      process.stderr.write(`  ${record.error ? "!" : "."} ${id}\n`);
    }
  } finally {
    await browser.close();
  }

  fs.mkdirSync(path.dirname(args.out), { recursive: true });
  fs.writeFileSync(args.out, lines.join("\n") + (lines.length ? "\n" : ""));
  process.stderr.write(`wrote ${args.out}: ${lines.length} cases\n`);
}

main().catch((error) => {
  process.stderr.write(String((error && error.stack) || error) + "\n");
  process.exit(1);
});
