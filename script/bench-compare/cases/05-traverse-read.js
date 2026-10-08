// Walking the tree and reading: the read-heavy side of test assertions.
({
  setup(window, document) {
    let html = "";
    for (let i = 0; i < 400; i++) {
      html += `<div class="card" data-k="${i}"><p title="t${i}">para ${i}</p><b>${i}</b></div>`;
    }
    document.body.innerHTML = html;
  },
  run(window, document) {
    let acc = 0;
    for (let pass = 0; pass < 5; pass++) {
      for (let el = document.body.firstElementChild; el; el = el.nextElementSibling) {
        acc += el.getAttribute("data-k").length;
        acc += el.children.length;
        const p = el.firstElementChild;
        acc += p.textContent.length + p.title.length;
        acc += el.lastElementChild.tagName.length;
      }
    }
    return acc;
  },
})
