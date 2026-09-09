// Attributes are an ordered list, and a namespaced attribute is identified by
// (namespace, localName) — not by its qualified name. Setting one through the
// non-NS API touches a different attribute from the NS one with the same
// qualified name.
defineCase({
  name: "attribute order, namespaces, and Attr node identity",
  html: "<div id=d class=one data-x=1></div>",
  run(h) {
    const div = document.getElementById("d");
    h.tag(div, "div");

    const listed = () => [...div.attributes].map((a) => [a.name, a.namespaceURI, a.prefix, a.localName, a.value]);

    div.setAttribute("title", "t");
    div.setAttribute("class", "two");           // replaces in place, keeps position
    const afterSets = listed();

    div.setAttributeNS("http://www.w3.org/1999/xlink", "xlink:href", "#a");
    div.setAttributeNS("http://example.test/ns", "data-x", "ns-value");
    const withNamespaces = listed();

    const byQualified = div.getAttribute("data-x");
    const byNamespace = div.getAttributeNS("http://example.test/ns", "data-x");
    const nullNamespace = div.getAttributeNS(null, "data-x");

    const node = div.getAttributeNode("class");
    const detachedAttr = h.attempt(() => {
      const removed = div.removeAttributeNode(node);
      return [removed.name, removed.value, removed.ownerElement === null];
    });

    const uppercaseOnHtml = h.attempt(() => {
      div.setAttribute("DATA-Y", "y");
      return [div.getAttribute("data-y"), div.hasAttribute("DATA-Y"), listed().map((a) => a[0])];
    });

    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("viewBox", "0 0 1 1");
    const caseSensitiveInSvg = [svg.getAttribute("viewBox"), svg.getAttribute("viewbox"), svg.attributes[0].name];

    return {
      afterSets, withNamespaces, byQualified, byNamespace, nullNamespace,
      detachedAttr, uppercaseOnHtml, caseSensitiveInSvg,
      finalOrder: listed().map((a) => a[0])
    };
  }
});
