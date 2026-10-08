// No DOM at all: what the JS engine itself costs. QuickJS interprets, V8 JITs,
// so this row is the yardstick for reading every other row — a DOM row slower
// than this ratio is the DOM's cost, not the engine's.
({
  setup() {},
  run() {
    let acc = 0;
    const words = [];
    for (let i = 0; i < 200000; i++) {
      acc = (acc + i * 31) % 1000003;
      if (i % 100 === 0) words.push("w" + i);
    }
    return acc + words.join(",").length;
  },
})
