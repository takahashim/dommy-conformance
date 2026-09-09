// normalize() merges a run of adjacent Text nodes one sibling at a time: the
// sibling's data is appended to the survivor (a characterData record) and then
// the sibling is removed (a childList record), per sibling, interleaved.
//
// Read literally the spec concatenates every sibling's data first (steps 3-4,
// one "replace data") and removes them afterwards (step 7), which would queue
// ONE characterData record per run. Every shipping engine merges pairwise
// instead, so takahashim/dommy#24 followed the engines — and nothing pinned the
// shape deterministically afterwards: the fuzzer found it, but only when a seed
// happened to reach a normalize.
defineCase({
  name: "normalize() queues a characterData record per absorbed sibling",
  html: "<div id=root></div>",
  run(h) {
    const root = document.getElementById("root");
    h.tag(root, "root");

    const build = (parts) => {
      root.textContent = "";
      const host = document.createElement("p");
      for (const part of parts) {
        if (part === null) host.appendChild(document.createElement("b"));
        else host.appendChild(document.createTextNode(part));
      }
      root.appendChild(host);
      return host;
    };

    const normalized = (parts, options) => {
      const host = build(parts);
      const observer = h.observe(host, Object.assign({ childList: true, characterData: true, subtree: true }, options || {}));
      host.normalize();
      return { records: h.records(observer), dom: h.dom(host) };
    };

    return {
      // Four non-empty siblings: three absorbed, so three pairs.
      run: normalized(["A", "BB", "CCC", "DDDD"]),
      // An absorbed sibling that carries no data changes nothing about the
      // survivor, so there is nothing for a characterData record to report.
      withEmpties: normalized(["A", "", "BB", "", ""]),
      // A lone empty Text node is dropped outright — a removal with no merge.
      loneEmpty: normalized([""]),
      // An element between two runs keeps them separate.
      twoRuns: normalized(["A", "BB", null, "CCC", "DDDD"]),
      // oldValue is the survivor's data at the moment of each append, so it
      // grows as the run is absorbed.
      oldValues: (() => {
        const host = build(["A", "BB", "CCC"]);
        const observer = h.observe(host, { childList: true, characterData: true, characterDataOldValue: true, subtree: true });
        host.normalize();
        return h.records(observer);
      })(),
      // Nothing to merge: no records at all.
      alreadyNormal: normalized(["A", null, "B"])
    };
  }
});
