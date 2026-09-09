# dommy-conformance

Spec-conformance measurement for [dommy](https://github.com/takahashim/dommy),
kept out of the library and out of any single JS-engine binding.

dommy depends on nothing but a parser backend, and `dommy-js-quickjs` is one
engine binding among the several there could be. Conformance measurement is a
third concern with its own weight and its own update cadence — a WPT checkout,
a browser build, third-party library suites — so it lives here, and depends on
dommy and on whichever bindings it is asked to exercise, never the reverse.

## The Chromium differential harness

WPT covers a lot, but a great many real divergences have no WPT test — DOM
mutation ordering, live-Range adjustment on a move, `setProperty` priority
validation, UTF-16 offsets. For those the practical oracle is a real browser.

The harness runs **the same JavaScript** in headless Chromium and in dommy, and
diffs a canonically normalized JSON observation of the result:

```
cases/**/*.js  ──┬──▶  runner/chromium.js  (Playwright)   ──▶  results/chromium.jsonl
                 └──▶  runner/dommy.rb     (dommy-js-quickjs) ──▶ results/dommy.jsonl
                                                                    │
                              expectations/known-divergences.yml ──▶ runner/diff.rb
```

A browser is an *oracle*, not the spec. Where the two disagree and Chromium is
the one departing from the spec text, the divergence is recorded in
`expectations/known-divergences.yml` with the reasoning, and the run stays green.
Everything else is a finding.

## Running

Needs a sibling checkout of dommy and of dommy-js-quickjs (or `DOMMY_PATH` /
`DOMMY_JS_QUICKJS_PATH`), node with Playwright, and a Chromium build.

    rake oracle            # run both sides and diff
    rake oracle:chromium   # refresh the browser side only
    rake oracle:dommy      # refresh the dommy side only
    rake oracle:diff       # re-diff what is already in results/
    rake oracle FILTER=range/

## Does it work?

The seed corpus is drawn from divergences that were actually found and fixed in
dommy, so the harness can be checked against a known-bad revision. Pointed at
dommy's tip, 12 cases agree with Chromium except the one recorded divergence.
Pointed at the revision before the live-Range / mutation-primitive work
(`4f624bf`), the same 12 cases report **25 divergences across 11 of them** —
every fix those changes made, rediscovered from the browser alone:

    range/move-boundary.js  insideMovedSubtree
      chromium: {"start":["@a",0], ...}
      dommy:    {"start":["#document/html[1]/body[1]/div[1]/span[0]/b[0]",0], ...}

A boundary left pointing into a subtree that had been moved away shows up as a
long detached path where the browser reports the vacated position. That is what
this harness is for.

    DOMMY_PATH=/path/to/an/older/dommy rake oracle:dommy && rake oracle:diff

## Writing a case

A case is one file that registers itself and returns a JSON-able observation.
The same source runs in both engines, so it may use only DOM API — no Node, no
test framework. `h` is the harness (see `lib/harness.js`).

```js
defineCase({
  name: "a boundary inside a moved subtree lands on the old parent",
  html: "<div id=a><span id=s><b id=b></b></span><i></i></div><div id=dest></div>",
  run(h) {
    const range = document.createRange();
    range.setStart(document.getElementById("b"), 0);
    range.collapse(true);
    h.tag(document.getElementById("a"), "a");

    document.getElementById("dest").appendChild(document.getElementById("s"));

    return { range: h.range(range) };
  }
});
```

Keys whose values differ between the two engines are the report. Name the keys
for what they mean, not for what you expect — the harness has no expected value
of its own, only the two observations.
