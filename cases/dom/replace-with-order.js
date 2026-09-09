// "Replace a child within a parent" removes the old child BEFORE inserting the
// replacements. The order is observable: a NodeIterator anchored inside the old
// child falls back to the parent, not to a node that was not yet in the tree.
defineCase({
  name: "replaceWith removes before inserting",
  html: "<div id=root><a id=a><b id=b></b></a><i id=i></i></div>",
  run(h) {
    const root = document.getElementById("root");
    h.tag(root, "root");

    const iterator = document.createNodeIterator(root);
    iterator.nextNode(); // root
    iterator.nextNode(); // a
    iterator.nextNode(); // b

    const range = document.createRange();
    range.setStart(document.getElementById("b"), 0);
    range.setEnd(root, 2);

    document.getElementById("a").replaceWith(document.createElement("z"));

    return { iterator: h.iterator(iterator), range: h.range(range), tree: h.shape(root) };
  }
});
