// Listener registration and bubbling dispatch through a 10-deep tree.
({
  setup(window, document) {
    let node = document.body;
    for (let d = 0; d < 10; d++) {
      const div = document.createElement("div");
      node.appendChild(div);
      node = div;
    }
    window.__leaf = node;
  },
  run(window, document) {
    let hits = 0;
    const handler = () => { hits++; };
    for (let n = window.__leaf; n; n = n.parentNode) n.addEventListener("ping", handler);
    for (let i = 0; i < 2000; i++) {
      window.__leaf.dispatchEvent(new window.Event("ping", { bubbles: true }));
    }
    return hits;
  },
})
