// Reflected numeric IDL attributes: what a `long` or an `unsigned long` reads
// back as, for the values a content attribute can actually hold. HTML §2.6.1
// gives the getter, and it rests on the "rules for parsing integers", which
// collect a run of digits and return — WITHOUT requiring that the run reach the
// end of the string. So "12abc" is 12 rather than an error, and the default
// only applies when no digits are found at all. That distinction is the whole
// point of this case: it decides the answer for four of the six inputs below,
// no WPT file in the corpus exercises it, and reading it off the spec text is
// exactly the kind of inference a browser should be asked to confirm.
//
// The parameters differ per attribute and come from the IDL: colSpan clamps to
// [1, 1000] and rowSpan to [0, 65534] ([ReflectRange]), ol.start defaults to 1
// ([ReflectDefault=1]), li.value has no default, and select.size defaults to 0.
//
// img.width is deliberately absent: its getter is prose, not a reflection — it
// reports the rendered or natural size when there is one, which a browser has
// and a headless DOM never will.
defineCase({
  name: "long and unsigned long reflection, and the integer parsing under it",
  html: [
    "<table><tr>",
    '<td id="cell"></td>',
    "</tr></table>",
    '<ol id="ol"><li id="li"></li></ol>',
    '<select id="select"></select>',
    '<video id="video"></video>'
  ].join(""),
  run() {
    const INPUTS = ["7", "12abc", "1e3", "-5", "  9  ", "+4", "0", "abc", "3000000000", ""];

    // Each attribute reads back through its own parameters, so every one of
    // them sees every input.
    const read = (id, attr, prop) => {
      const el = document.getElementById(id);
      const out = {};
      for (const value of INPUTS) {
        el.setAttribute(attr, value);
        out[JSON.stringify(value)] = el[prop];
      }
      el.removeAttribute(attr);
      out.absent = el[prop];
      return out;
    };

    return {
      colSpan: read("cell", "colspan", "colSpan"),
      rowSpan: read("cell", "rowspan", "rowSpan"),
      olStart: read("ol", "start", "start"),
      liValue: read("li", "value", "value"),
      selectSize: read("select", "size", "size"),
      videoWidth: read("video", "width", "width"),
      // The setter's own conversion: out of range becomes the default, and a
      // negative unsigned long wraps through WebIDL before any of this.
      setterRoundTrip: (() => {
        const cell = document.getElementById("cell");
        const out = {};
        for (const value of [5, 0, 5000, 3000000000, -1]) {
          cell.colSpan = value;
          out[String(value)] = [cell.getAttribute("colspan"), cell.colSpan];
        }
        return out;
      })()
    };
  }
});
