// Serialization: outerHTML of a 2000-element tree, repeatedly.
({
  setup(window, document) {
    let html = "";
    for (let i = 0; i < 500; i++) html += `<p class="c${i % 5}">a &amp; b <i>${i}</i> <br></p>`;
    document.body.innerHTML = html;
  },
  run(window, document) {
    let len = 0;
    for (let i = 0; i < 10; i++) len += document.body.outerHTML.length;
    return len;
  },
})
