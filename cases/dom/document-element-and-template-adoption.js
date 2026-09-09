// documentElement is the document's first ELEMENT child, so it is null once
// that element is gone — and head / body / title, which resolve through it,
// go with it.
defineCase({
  name: "documentElement is null without a root element",
  html: "<div id=c></div>",
  run(h) {
    const html = document.documentElement;
    const comment = document.createComment("z");
    const removed = document.replaceChild(comment, html);

    const withoutRoot = {
      documentElement: document.documentElement === null ? "null" : document.documentElement.nodeName,
      head: document.head === null ? "null" : document.head.nodeName,
      body: document.body === null ? "null" : document.body.nodeName,
      title: document.title,
      removed: removed.nodeName,
      children: [...document.childNodes].map(n => n.nodeName + ":" + n.nodeType)
    };

    document.replaceChild(html, comment);

    return {
      withoutRoot,
      restored: document.documentElement === html,
      bodyBack: document.body !== null
    };
  }
});
