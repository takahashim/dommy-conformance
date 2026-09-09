// The removing steps run for the implicit removal a MOVE performs, so a
// boundary inside the moved subtree lands on the position it vacated.
defineCase({
  name: "appendChild move relocates a boundary inside the moved subtree",
  html: "<div id=a><span id=s><b id=b></b></span><i id=i></i></div><div id=dest></div>",
  run(h) {
    const a = document.getElementById("a");
    const span = document.getElementById("s");
    h.tag(a, "a");
    h.tag(document.getElementById("dest"), "dest");

    const inside = document.createRange();
    inside.setStart(document.getElementById("b"), 0);
    inside.collapse(true);

    const onOldParent = document.createRange();
    onOldParent.setStart(a, 2);
    onOldParent.collapse(true);

    document.getElementById("dest").appendChild(span);

    return {
      insideMovedSubtree: h.range(inside),
      onOldParent: h.range(onOldParent),
      tree: h.shape(document.body)
    };
  }
});
