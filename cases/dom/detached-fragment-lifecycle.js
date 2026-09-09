// A DocumentFragment is never connected, so a custom element parsed into a
// <template>'s content gets no connectedCallback until it is inserted into a
// document — and exactly one then.
defineCase({
  name: "custom element lifecycle across template content and insertion",
  html: "",
  run(h) {
    let connected = 0;
    let disconnected = 0;
    customElements.define("x-oracle-child", class extends HTMLElement {
      connectedCallback() { connected++; }
      disconnectedCallback() { disconnected++; }
    });

    const template = document.createElement("template");
    template.innerHTML = "<x-oracle-child></x-oracle-child>";
    const inTemplate = { connected, contentIsConnected: template.content.isConnected };

    document.body.appendChild(template.content);
    const afterInsertion = { connected };

    const fragment = document.createDocumentFragment();
    const detachedChild = document.createElement("div");
    fragment.appendChild(detachedChild);

    document.body.querySelector("x-oracle-child").remove();

    return {
      inTemplate,
      afterInsertion,
      afterRemoval: { disconnected },
      fragmentIsConnected: fragment.isConnected,
      fragmentChildIsConnected: detachedChild.isConnected
    };
  }
});
