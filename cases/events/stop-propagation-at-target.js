// The target appears twice in the event path traversal, and "invoke" returns
// early once the stop-propagation flag is set — so stopPropagation() in an
// at-target CAPTURE listener also skips that target's bubble listeners, while
// leaving the remaining capture listeners on the same target alone.
defineCase({
  name: "stopPropagation and stopImmediatePropagation at the target",
  html: "<div id=outer><button id=btn>X</button></div>",
  run(h) {
    const outer = document.getElementById("outer");

    const run = (setup) => {
      const button = document.createElement("button");
      outer.appendChild(button);
      const seen = [];
      setup(button, seen);
      outer.addEventListener("click", () => seen.push("ancestor"));
      button.dispatchEvent(new Event("click", { bubbles: true }));
      button.remove();
      return seen;
    };

    return {
      stopPropagationInCapture: run((button, seen) => {
        button.addEventListener("click", (e) => { seen.push("capture"); e.stopPropagation(); }, true);
        button.addEventListener("click", () => seen.push("bubble"));
      }),
      stopPropagationKeepsSiblingListeners: run((button, seen) => {
        button.addEventListener("click", (e) => { seen.push("capture1"); e.stopPropagation(); }, true);
        button.addEventListener("click", () => seen.push("capture2"), true);
        button.addEventListener("click", () => seen.push("bubble"));
      }),
      stopImmediateSkipsSiblings: run((button, seen) => {
        button.addEventListener("click", (e) => { seen.push("capture1"); e.stopImmediatePropagation(); }, true);
        button.addEventListener("click", () => seen.push("capture2"), true);
        button.addEventListener("click", () => seen.push("bubble"));
      }),
      fullOrderAcrossAncestors: run((button, seen) => {
        outer.addEventListener("click", () => seen.push("outerCapture"), true);
        button.addEventListener("click", () => seen.push("targetBubble"));
        button.addEventListener("click", () => seen.push("targetCapture"), true);
      })
    };
  }
});
