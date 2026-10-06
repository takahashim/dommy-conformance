// A script the parser put in a <template>'s content: moved (not cloned) into
// the document, does it run? Cloned (importNode), does it run?
defineCase({
  name: "template content scripts moved vs cloned",
  html: "<template id=t1><script>__log.push('moved ran')</script></template><template id=t2><script>__log.push('cloned ran')</script></template><div id=host></div>",
  run(h) {
    const log = [];
    window.__log = log;
    const host = document.getElementById("host");
    host.appendChild(document.getElementById("t1").content);
    log.push("after move");
    host.appendChild(document.importNode(document.getElementById("t2").content, true));
    log.push("after clone");
    return log;
  }
});
