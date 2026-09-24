// Which elements expose a reflected DOMTokenList, and in which namespace. HTML
// gives relList to a / area / link / form, SVG gives it to its own <a>, and
// MathML Core defines no <a> at all — so `relList` there should be undefined
// like it is on a <td>. The namespaces are the point: an element's interface,
// not its local name, decides what it reflects.
defineCase({
  name: "which elements have a reflected DOMTokenList",
  html: "<div id=d></div>",
  run() {
    const HTML = "http://www.w3.org/1999/xhtml";
    const SVG = "http://www.w3.org/2000/svg";
    const MATHML = "http://www.w3.org/1998/Math/MathML";
    const kind = (el, prop) => {
      const v = el[prop];
      return v === undefined ? "undefined" : v === null ? "null" : v.constructor.name;
    };
    const out = {};
    for (const [label, ns] of [["html", HTML], ["svg", SVG], ["mathml", MATHML]]) {
      for (const name of ["a", "area", "link", "form", "td"]) {
        out[`${label}:${name}.relList`] = kind(document.createElementNS(ns, name), "relList");
      }
    }
    out["output.htmlFor"] = kind(document.createElement("output"), "htmlFor");
    out["label.htmlFor"] = kind(document.createElement("label"), "htmlFor");
    out["script.htmlFor"] = kind(document.createElement("script"), "htmlFor");
    out["iframe.sandbox"] = kind(document.createElement("iframe"), "sandbox");
    out["link.sizes"] = kind(document.createElement("link"), "sizes");
    out["img.sizes"] = kind(document.createElement("img"), "sizes");
    return out;
  }
});
