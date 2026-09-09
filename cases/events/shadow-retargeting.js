// An event crossing a shadow boundary is retargeted: composedPath reveals the
// inner nodes only inside the tree, and `target` is adjusted per listener.
defineCase({
  name: "event retargeting and composedPath across a shadow boundary",
  html: "<div id=outer><div id=host></div></div>",
  run(h) {
    const outer = document.getElementById("outer");
    const host = document.getElementById("host");
    h.tag(outer, "outer");
    h.tag(host, "host");
    const root = host.attachShadow({ mode: "open" });
    h.tag(root, "root");
    root.innerHTML = "<section id=inner><button id=btn>x</button></section>";
    const button = root.getElementById ? root.getElementById("btn") : root.querySelector("#btn");
    h.tag(button, "button");

    const seen = [];
    const record = (where) => (event) => seen.push({
      where,
      target: h.ref(event.target),
      currentTarget: h.ref(event.currentTarget),
      path: h.refs(event.composedPath()),
      phase: event.eventPhase
    });

    button.addEventListener("x", record("button"));
    root.addEventListener("x", record("shadowRoot"));
    host.addEventListener("x", record("host"));
    outer.addEventListener("x", record("outer"));

    button.dispatchEvent(new Event("x", { bubbles: true, composed: true }));
    const composed = seen.slice();

    seen.length = 0;
    button.dispatchEvent(new Event("x", { bubbles: true, composed: false }));
    const notComposed = seen.slice();

    seen.length = 0;
    const slotted = document.createElement("span");
    slotted.id = "light";
    host.appendChild(slotted);
    root.innerHTML = "<slot></slot>";
    const slot = root.querySelector("slot");
    h.tag(slot, "slot");
    return {
      composed, notComposed,
      assigned: { slotOfLight: h.ref(slotted.assignedSlot), assignedNodes: h.refs(slot.assignedNodes()) }
    };
  }
});
