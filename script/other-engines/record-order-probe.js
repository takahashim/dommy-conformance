// The #23 and #24 probes, plus the control that separates a splitText-specific
// deviation from a general MutationRecord ordering difference.
(function () {
  const out = {};

  // --- #23: splitText's MutationRecord order -------------------------------
  {
    const b = document.createElement("b");
    b.textContent = "abcdef";
    document.body.appendChild(b);
    const o = new MutationObserver(() => {});
    o.observe(b, { childList: true, characterData: true, subtree: true });
    b.firstChild.splitText(3);
    out.splitText = o.takeRecords().map(r => r.type);
    out.splitTextResult = [...b.childNodes].map(n => n.data);
    o.disconnect();
    b.remove();
  }

  // --- control: the same two mutations, done explicitly, in order ----------
  {
    const d = document.createElement("div");
    const t = document.createTextNode("abcdef");
    d.appendChild(t);
    document.body.appendChild(d);
    const o = new MutationObserver(() => {});
    o.observe(d, { childList: true, characterData: true, subtree: true });
    d.appendChild(document.createTextNode("def"));  // childList
    t.replaceData(3, 3, "");                        // characterData
    out.control = o.takeRecords().map(r => r.type);
    o.disconnect();
    d.remove();
  }

  // --- #24: normalize()'s characterData record count -----------------------
  {
    const n = document.createElement("div");
    document.body.appendChild(n);
    for (const s of ["A", "BB", "CCC", "DDDD"]) n.appendChild(document.createTextNode(s));
    const o = new MutationObserver(() => {});
    o.observe(n, { childList: true, characterData: true, subtree: true });
    n.normalize();
    out.normalize = o.takeRecords().map(r => r.type);
    out.normalizeResult = [...n.childNodes].map(x => x.data);
    o.disconnect();
    n.remove();
  }

  out.ua = navigator.userAgent;
  return out;
})()
