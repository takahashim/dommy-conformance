// Moving nodes around: remove, insertBefore and replaceChildren churn.
({
  setup(window, document) {
    let html = "";
    for (let i = 0; i < 300; i++) html += `<li>${i}</li>`;
    document.body.innerHTML = `<ul id="a">${html}</ul><ul id="b"></ul>`;
  },
  run(window, document) {
    const a = document.getElementById("a");
    const b = document.getElementById("b");
    for (let pass = 0; pass < 6; pass++) {
      const [from, to] = pass % 2 ? [b, a] : [a, b];
      while (from.firstChild) to.insertBefore(from.lastChild, to.firstChild);
    }
    const kept = Array.from(a.children).filter((_, i) => i % 3 === 0);
    a.replaceChildren(...kept);
    return a.children.length * 1000 + Number(a.firstElementChild.textContent);
  },
})
