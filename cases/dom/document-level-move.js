// Moving an existing node under the Document itself is a removal from its old
// parent followed by an insertion — both parents observe it, and a live Range
// on the old parent follows the removing steps.
defineCase({
  name: "moving a node to the document notifies both parents",
  html: "<div id=c></div>",
  run(h) {
    const container = document.getElementById("c");
    h.tag(container, "container");
    h.tag(document, "document");

    const comment = document.createComment("x");
    container.appendChild(comment);

    const onOldParent = document.createRange();
    onOldParent.setStart(container, 1);
    onOldParent.collapse(true);

    const containerObserver = h.observe(container, { childList: true });
    const documentObserver = h.observe(document, { childList: true });

    document.appendChild(comment);

    return {
      parentIsDocument: comment.parentNode === document,
      onOldParent: h.range(onOldParent),
      containerRecords: h.records(containerObserver),
      documentRecords: h.records(documentObserver)
    };
  }
});
