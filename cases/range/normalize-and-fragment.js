// normalize() hands a merged-away Text node's boundaries to the survivor at the
// offset its data lands at; a DocumentFragment's children are removed from the
// fragment when it is inserted, so boundaries there follow the removing steps.
defineCase({
  name: "live Range across normalize() and fragment insertion",
  html: "<div id=d></div><div id=host></div>",
  run(h) {
    const div = document.getElementById("d");
    h.tag(div, "div");
    for (const text of ["A", "BB", "CCC", "DDDD"]) div.appendChild(document.createTextNode(text));
    const nodes = [...div.childNodes];

    const spanning = document.createRange();
    spanning.setStart(nodes[1], 1);
    spanning.setEnd(nodes[3], 2);
    const atParentOffset = document.createRange();
    atParentOffset.setStart(div, 2);
    atParentOffset.collapse(true);

    div.normalize();
    const afterNormalize = {
      merged: div.firstChild.data,
      spanning: h.range(spanning),
      atParentOffset: h.range(atParentOffset)
    };

    const host = document.getElementById("host");
    h.tag(host, "host");
    const fragment = document.createDocumentFragment();
    h.tag(fragment, "fragment");
    fragment.append(document.createElement("a"), document.createElement("b"), document.createElement("i"));
    const onFragment = document.createRange();
    onFragment.setStart(fragment, 1);
    onFragment.setEnd(fragment, 3);

    const nested = document.createDocumentFragment();
    h.tag(nested, "nested");
    const child = document.createElement("p");
    const inner = document.createTextNode("hello");
    child.appendChild(inner);
    nested.appendChild(child);
    const insideChild = document.createRange();
    insideChild.setStart(inner, 1);
    insideChild.setEnd(inner, 3);

    host.appendChild(fragment);
    host.appendChild(nested);

    return { afterNormalize, onFragment: h.range(onFragment), insideFragmentChild: h.range(insideChild) };
  }
});
