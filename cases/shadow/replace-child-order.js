// ShadowRoot#replaceChild is the same remove-before-insert as everywhere else,
// including when the incoming node is already a sibling or a fragment.
defineCase({
  name: "ShadowRoot replaceChild removes before inserting",
  html: "<div id=h></div><div id=h2></div><div id=h3></div>",
  run(h) {
    const root = document.getElementById("h").attachShadow({ mode: "open" });
    h.tag(root, "root");
    root.innerHTML = "<a><x></x></a><b></b>";

    const iterator = document.createNodeIterator(root);
    iterator.nextNode(); iterator.nextNode(); iterator.nextNode();
    const range = document.createRange();
    range.setStart(root.firstChild.firstChild, 0);
    range.setEnd(root, 2);

    root.replaceChild(document.createElement("z"), root.firstChild);
    const basic = { iterator: h.iterator(iterator), range: h.range(range), tree: h.shape(root) };

    const sibling = document.getElementById("h2").attachShadow({ mode: "open" });
    sibling.innerHTML = "<a></a><b></b><i></i>";
    sibling.replaceChild(sibling.childNodes[1], sibling.childNodes[0]);

    const fragmentHost = document.getElementById("h3").attachShadow({ mode: "open" });
    fragmentHost.innerHTML = "<a></a><b></b>";
    const fragmentObserver = h.observe(fragmentHost, { childList: true });
    const fragment = document.createDocumentFragment();
    fragment.append(document.createElement("p"), document.createElement("q"));
    fragmentHost.replaceChild(fragment, fragmentHost.firstChild);

    return {
      basic,
      incomingSibling: h.shape(sibling),
      withFragment: h.shape(fragmentHost),
      fragmentRecords: h.records(fragmentObserver)
    };
  }
});
