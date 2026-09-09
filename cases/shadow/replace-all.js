// A ShadowRoot is a DocumentFragment, so its textContent setter is WHATWG
// "string replace all": one childList record for the whole swap, and an empty
// value leaves no children rather than an empty Text node.
defineCase({
  name: "ShadowRoot textContent is a string-replace-all",
  html: "<div id=h></div>",
  run(h) {
    const host = document.getElementById("h");
    const root = host.attachShadow({ mode: "open" });
    h.tag(root, "root");
    root.innerHTML = "<a></a><b></b>";

    const atChildOffset = document.createRange();
    atChildOffset.setStart(root, 1);
    atChildOffset.setEnd(root, 2);
    const insideRemoved = document.createRange();
    insideRemoved.setStart(root.firstChild, 0);
    insideRemoved.collapse(true);

    const observer = h.observe(root, { childList: true });
    root.textContent = "hello";

    const afterText = {
      childCount: root.childNodes.length,
      firstIsText: root.firstChild.nodeType === 3,
      text: root.textContent,
      records: h.records(observer),
      atChildOffset: h.range(atChildOffset),
      insideRemoved: h.range(insideRemoved)
    };

    root.textContent = "";
    return { afterText, emptyLeavesNoChildren: root.childNodes.length };
  }
});
