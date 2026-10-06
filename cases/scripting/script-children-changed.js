// Which child mutations of a connected, not-yet-run script prepare it again:
// insertion (an empty script given text), removal, and a text node's data
// changing (DOM's "replace data" also runs children changed steps).
defineCase({
  name: "script children changed: insertion, removal, data change",
  html: "<div id=host></div>",
  run(h) {
    const host = document.getElementById("host");
    const log = [];
    window.__log = log;
    // removal
    const a = document.createElement("script");
    a.type = "0";
    a.textContent = "__log.push('a ran');";
    host.append(a);
    const div = document.createElement("div");
    a.append(div);
    a.type = "";
    div.remove();
    log.push("after a removal");
    // data change on an empty text child
    const b = document.createElement("script");
    const t = document.createTextNode("");
    b.append(t);
    host.append(b);
    t.data = "__log.push('b ran');";
    log.push("after b data change");
    // whitespace-only script runs (and so is started)
    const c = document.createElement("script");
    c.textContent = "  ";
    host.append(c);
    c.textContent = "__log.push('c ran');";
    log.push("after c change");
    // empty script given text by append
    const d = document.createElement("script");
    host.append(d);
    d.append("__log.push('d ran');");
    log.push("after d append");
    // src set on a connected empty script prepares it (data: URL fetch is async)
    return log;
  }
});
