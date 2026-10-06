// Flags of the submit event a requestSubmit() fires.
defineCase({
  name: "submit event flags",
  html: "<form id=f><button id=b>x</button></form>",
  run(h) {
    const form = document.getElementById("f");
    let flags = null;
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      flags = { bubbles: e.bubbles, cancelable: e.cancelable, composed: e.composed, trusted: e.isTrusted };
    });
    form.requestSubmit(document.getElementById("b"));
    return flags;
  }
});
