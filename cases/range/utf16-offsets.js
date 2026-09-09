// DOM string offsets are UTF-16 code units, so an astral character counts two.
// "A<emoji>BC" maps as A=[0,1) emoji=[1,3) B=[3,4) C=[4,5), length 5.
defineCase({
  name: "Range offsets into CharacterData are UTF-16 code units",
  html: "<p id=p>A\u{1F600}BC</p>",
  run(h) {
    const fresh = () => {
      document.getElementById("p").textContent = "A\u{1F600}BC";
      return document.getElementById("p").firstChild;
    };
    const rangeOn = (node, start, end) => {
      const range = document.createRange();
      range.setStart(node, start);
      range.setEnd(node, end);
      return range;
    };

    let text = fresh();
    const length = text.length;
    const lastOffsetAccepted = h.attempt(() => { rangeOn(text, 0, 5); return "ok"; });
    const pastEndRejected = h.attempt(() => { rangeOn(text, 0, 6); return "ok"; });

    text = fresh();
    const stringified = rangeOn(text, 1, 4).toString();

    text = fresh();
    const cloned = rangeOn(text, 1, 4).cloneContents().textContent;

    text = fresh();
    const extractRange = rangeOn(text, 3, 5);
    const extracted = { taken: extractRange.extractContents().textContent, left: text.data, offset: extractRange.startOffset };

    text = fresh();
    const deleteRange = rangeOn(text, 1, 3);
    deleteRange.deleteContents();
    const deleted = { left: text.data, start: deleteRange.startOffset, end: deleteRange.endOffset };

    text = fresh();
    const live = rangeOn(text, 3, 5);
    text.deleteData(0, 1);
    const afterDeleteData = { data: text.data, boundaries: [live.startOffset, live.endOffset] };

    text = fresh();
    const splitLive = rangeOn(text, 1, 5);
    const tail = text.splitText(3);
    const afterSplit = {
      head: text.data, tail: tail.data,
      start: splitLive.startOffset,
      endMovedToTail: splitLive.endContainer === tail,
      end: splitLive.endOffset
    };

    // A detached node skips the split steps entirely, so the boundary stays put
    // and is clamped by the truncation instead.
    const detached = document.createTextNode("A\u{1F600}BC");
    const detachedRange = rangeOn(detached, 1, 5);
    detached.splitText(3);
    const afterDetachedSplit = {
      stillOnOriginal: detachedRange.endContainer === detached,
      boundaries: [detachedRange.startOffset, detachedRange.endOffset]
    };

    return {
      length, lastOffsetAccepted, pastEndRejected, stringified, cloned,
      extracted, deleted, afterDeleteData, afterSplit, afterDetachedSplit
    };
  }
});
