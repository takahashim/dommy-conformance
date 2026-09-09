// Range.insertNode splits the boundary text node and lands the node in the gap;
// surroundContents extracts, wraps, and re-inserts. Both reposition the range.
defineCase({
  name: "Range insertNode and surroundContents",
  html: "<div id=d><p id=p>hello world</p><p id=q>second</p></div>",
  run(h) {
    const div = document.getElementById("d");
    h.tag(div, "div");
    const markup = div.innerHTML;
    const reset = () => { div.innerHTML = markup; return div; };

    const rangeIn = (nodeId, start, end) => {
      const text = document.getElementById(nodeId).firstChild;
      const range = document.createRange();
      range.setStart(text, start);
      range.setEnd(text, end);
      return range;
    };

    reset();
    let range = rangeIn("p", 5, 5);
    range.insertNode(document.createElement("b"));
    const intoTextMiddle = { dom: h.dom(document.getElementById("p")), range: h.range(range) };

    reset();
    range = rangeIn("p", 0, 0);
    range.insertNode(document.createElement("b"));
    const atTextStart = { dom: h.dom(document.getElementById("p")), range: h.range(range) };

    reset();
    range = rangeIn("p", 11, 11);
    range.insertNode(document.createElement("b"));
    const atTextEnd = { dom: h.dom(document.getElementById("p")), range: h.range(range) };

    reset();
    range = rangeIn("p", 2, 8);
    range.surroundContents(document.createElement("em"));
    const surrounded = { dom: h.dom(document.getElementById("p")), range: h.range(range) };

    reset();
    range = document.createRange();
    range.setStart(document.getElementById("p").firstChild, 3);
    range.setEnd(document.getElementById("q").firstChild, 2);
    const partiallyContained = h.attempt(() => { range.surroundContents(document.createElement("em")); return "ok"; });

    reset();
    range = document.createRange();
    range.selectNode(document.getElementById("p"));
    const comparisons = {
      selectNode: h.range(range),
      startToStart: range.compareBoundaryPoints(Range.START_TO_START, range),
      endToStart: range.compareBoundaryPoints(Range.END_TO_START, range),
      intersects: range.intersectsNode(document.getElementById("q")),
      comparePointBefore: range.comparePoint(div, 0),
      comparePointAfter: range.comparePoint(div, 2),
      isPointInRange: range.isPointInRange(div, 0)
    };

    return { intoTextMiddle, atTextStart, atTextEnd, surrounded, partiallyContained, comparisons };
  }
});
