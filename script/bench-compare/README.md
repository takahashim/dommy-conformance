# bench-compare

Speed and memory of Dommy (with dommy-js-quickjs) next to the JS-capable DOM
libraries people would otherwise reach for in Node: **jsdom**, **happy-dom**
and **linkedom**. The correctness counterpart is the WPT corpus; `wpt-compare/`
next door runs an older slice of it under jsdom and happy-dom.

```
(cd script/bench-compare && npm install)    # jsdom, happy-dom, linkedom
rake bench                                  # or: ruby script/bench-compare/run.rb
rake bench ENGINES=dommy,jsdom SAMPLES=11 FILTER=events
```

It prints a Markdown table and writes `results/bench-compare.{json,md}`.

## What is measured

Every case in `cases/` is one plain JS object, run unchanged by every library:

```js
({
  setup(window, document) { /* untimed: build the fixture */ },
  run(window, document)   { /* timed; returns a checksum */ },
})
```

- Each sample gets a **fresh window**. Sample 0 is a warm-up, and the table
  shows the median of the rest (7 by default).
- `run` is timed by the host, around one call: a direct call in Node, and one
  `evaluate` from Ruby for Dommy (tens of microseconds of overhead).
- Every engine must return the **same checksum**. A cell marked `≠` did
  different work, so its time is not comparable. `n/a` means the library lacks
  an API the case uses (linkedom has no `getComputedStyle`).
- **Window cost** is measured in a separate fresh process, after a GC:
  - the time to open a window;
  - the RSS growth per window from keeping 20 windows alive, each either empty
    or holding the `02-parse-innerhtml` table (~18k nodes).
  - The Node side also records the V8 heap figure as a cross-check of the RSS
    number (`results/bench-compare.json`).

## Reading the numbers

- `01-js-baseline` touches no DOM. It shows what QuickJS (an interpreter)
  costs against V8 (a JIT). A row whose `dommy ÷ jsdom` ratio is well above
  that one is DOM cost, not engine cost.
- Dommy keeps the DOM in Ruby, so every DOM call from a script crosses the
  QuickJS↔Ruby boundary:
  - Cases that do a lot of work per call (parsing, selector matching,
    serialization, the cascade) favour Dommy.
  - Cases made of many small calls (creating nodes one by one, dispatching
    events, reading properties in a loop) measure that crossing.
- All of this is wall time on whatever machine runs it. Compare numbers from
  one run, not across machines; re-run before trusting a small difference.
