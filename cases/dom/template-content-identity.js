// HTML gives each <template> ONE associated DocumentFragment. innerHTML=
// retargets to that fragment and replaces all of its children, so the content
// object itself is never exchanged and an observer on it sees every assignment.
defineCase({
  name: "template.content identity survives innerHTML assignment",
  html: "",
  run(h) {
    const template = document.createElement("template");
    const content = template.content;
    h.tag(content, "content");
    const observer = h.observe(content, { childList: true });

    template.innerHTML = "<span>x</span>";
    const afterFirst = { sameObject: content === template.content, first: template.content.firstChild.localName };

    template.innerHTML = "<a></a>";
    const held = content.firstChild;
    template.innerHTML = "<b></b>";

    return {
      afterFirst,
      stillSame: content === template.content,
      current: content.firstChild.localName,
      heldNodeDetached: held.parentNode === null,
      records: h.records(observer)
    };
  }
});
