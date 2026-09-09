// A NodeIterator's referenceNode must never survive as a detached node: every
// path that takes a node out of its parent runs the pre-removing steps.
defineCase({
  name: "NodeIterator reference node after each kind of removal",
  html: "<div id=root><a id=a><b id=b></b></a><i id=i></i></div><div id=other></div>",
  run(h) {
    const root = document.getElementById("root");
    const other = document.getElementById("other");
    h.tag(root, "root");
    h.tag(other, "other");

    const markup = root.innerHTML;
    const atDeepest = () => {
      root.innerHTML = markup;
      const iterator = document.createNodeIterator(root);
      iterator.nextNode(); iterator.nextNode(); iterator.nextNode();
      return iterator;
    };

    let iterator = atDeepest();
    other.appendChild(document.getElementById("a"));
    const afterAppendChildMove = h.iterator(iterator);

    iterator = atDeepest();
    other.insertBefore(document.getElementById("a"), null);
    const afterInsertBeforeMove = h.iterator(iterator);

    iterator = atDeepest();
    root.replaceChildren();
    const afterReplaceChildren = h.iterator(iterator);

    iterator = atDeepest();
    document.getElementById("a").replaceWith(document.createElement("z"));
    const afterReplaceWith = h.iterator(iterator);

    iterator = atDeepest();
    root.textContent = "gone";
    const afterTextContent = h.iterator(iterator);

    const fragment = document.createDocumentFragment();
    const outer = document.createElement("p");
    outer.appendChild(document.createElement("q"));
    fragment.appendChild(outer);
    h.tag(fragment, "fragment");
    const fragmentIterator = document.createNodeIterator(fragment);
    fragmentIterator.nextNode(); fragmentIterator.nextNode(); fragmentIterator.nextNode();
    root.appendChild(fragment);
    const afterFragmentInsertion = h.iterator(fragmentIterator);

    return {
      afterAppendChildMove, afterInsertBeforeMove, afterReplaceChildren,
      afterReplaceWith, afterTextContent, afterFragmentInsertion
    };
  }
});
