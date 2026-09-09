// HTML's adopting steps for <template> adopt its template contents along with
// it: the SAME DocumentFragment object, still holding its children. Those
// contents are not in the template's child list, so a subtree walk that only
// follows childNodes never reaches them and the adopted template comes out
// empty.
defineCase({
  name: "template contents follow the template across documents",
  html: "",
  run(h) {
    const other = document.implementation.createHTMLDocument("other");
    const names = node => [...node.childNodes].map(n => n.nodeName);
    const make = html => {
      const template = document.createElement("template");
      template.innerHTML = html;
      return template;
    };

    const adopted = make("<u>hi</u>");
    const adoptedContent = adopted.content;
    other.adoptNode(adopted);

    const inserted = make("<u>x</u>");
    other.body.appendChild(inserted);

    const carried = make("<u>x</u>");
    const fragment = document.createDocumentFragment();
    fragment.appendChild(carried);
    other.body.appendChild(fragment);

    const nested = make("<template><i>deep</i></template>");
    const innerTemplate = nested.content.firstChild;
    other.adoptNode(nested);

    const buried = make("<b>y</b>");
    const buriedContent = buried.content;
    const holder = document.createElement("div");
    holder.appendChild(buried);
    other.adoptNode(holder);

    const importSource = make("<u>hi</u>");
    const importedDeep = other.importNode(importSource, true);
    const importedShallow = other.importNode(importSource, false);

    return {
      adopted: {
        sameContentObject: adopted.content === adoptedContent,
        content: names(adopted.content),
        innerHTML: adopted.innerHTML,
        ownerIsOther: adopted.ownerDocument === other
      },
      crossDocumentInsert: { sameNode: other.body.firstChild === inserted, content: names(inserted.content) },
      carriedInFragment: { stillInTree: carried.ownerDocument === other, content: names(carried.content) },
      nested: {
        outer: names(nested.content),
        sameInner: nested.content.firstChild === innerTemplate,
        inner: names(innerTemplate.content)
      },
      buriedInSubtree: {
        sameElement: holder.firstChild === buried,
        sameContentObject: buried.content === buriedContent,
        content: names(buried.content)
      },
      importDeep: { content: names(importedDeep.content), sourceKeepsItsOwn: names(importSource.content) },
      importShallow: names(importedShallow.content)
    };
  }
});
