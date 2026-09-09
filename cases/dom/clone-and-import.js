// cloneNode / importNode / adoptNode: what carries across, and what the
// resulting node's ownerDocument and identity are.
defineCase({
  name: "cloneNode, importNode and adoptNode",
  html: "<div id=src class=c data-k=v><span>text</span><!--note--></div>",
  run(h) {
    const source = document.getElementById("src");
    h.tag(source, "source");

    const shallow = source.cloneNode(false);
    const deep = source.cloneNode(true);

    const other = document.implementation.createHTMLDocument("other");
    const imported = other.importNode(source, true);
    const shallowImport = other.importNode(source, false);

    const adoptable = document.createElement("p");
    adoptable.appendChild(document.createTextNode("moved"));
    document.body.appendChild(adoptable);
    const adopted = other.adoptNode(adoptable);

    const nsElement = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    nsElement.setAttribute("viewBox", "0 0 2 2");
    const nsClone = nsElement.cloneNode(true);

    const template = document.createElement("template");
    template.innerHTML = "<i>inside</i>";
    const templateClone = template.cloneNode(true);

    return {
      shallow: { dom: h.dom(shallow), sameOwner: shallow.ownerDocument === document, kids: shallow.childNodes.length },
      deep: { dom: h.dom(deep), notSameNode: deep !== source, firstChildIsCopy: deep.firstChild !== source.firstChild },
      imported: { dom: h.dom(imported), ownerIsOther: imported.ownerDocument === other, sourceStillHere: source.isConnected },
      shallowImportKids: shallowImport.childNodes.length,
      adopted: {
        ownerIsOther: adopted.ownerDocument === other,
        detached: adopted.parentNode === null,
        sameObject: adopted === adoptable,
        dom: h.dom(adopted)
      },
      nsClone: { ns: nsClone.namespaceURI, name: nsClone.attributes[0].name, value: nsClone.getAttribute("viewBox") },
      templateClone: {
        contentIsCopy: templateClone.content !== template.content,
        contentDom: h.dom(templateClone.content),
        elementHasNoChildren: templateClone.childNodes.length
      }
    };
  }
});
