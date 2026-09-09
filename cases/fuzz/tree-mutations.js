// Deterministic random mutation sequences. See lib/fuzz.js: both engines run
// the identical sequence, and everything a live Range, a NodeIterator and a
// MutationObserver can see is recorded after every step.
//
// The committed defaults are what CI runs; a deeper hunt is
// `rake fuzz SEEDS=200 STEPS=300`.
defineCase({
  name: "random DOM mutation sequences under a live Range, NodeIterator and MutationObserver",
  html: "<div id=root><section id=a><p id=p1>alpha</p><p id=p2>beta<b id=b>bold</b></p></section>" +
        "<section id=c><span id=s>gamma</span><!--note--><i id=i></i></section></div>",
  run(h) {
    const seeds = h.config("seeds", 12);
    const steps = h.config("steps", 60);
    // OPS_EXCLUDE=splitText keeps the hunt going past an outstanding divergence.
    const exclude = h.config("opsExclude", "");
    const root = document.getElementById("root");
    h.tag(root, "root");

    const out = {};
    const markup = root.innerHTML;
    for (let seed = 1; seed <= seeds; seed++) {
      // Each seed starts from the same tree, so a divergence is attributable to
      // the sequence alone.
      root.innerHTML = markup;
      out["seed-" + String(seed).padStart(4, "0")] = runFuzzSeed(h, root, seed, steps, exclude);
    }
    return out;
  }
});
