// HTML parsing into a live tree: one innerHTML assignment of a 2000-row table.
({
  setup(window, document) {
    const rows = [];
    for (let i = 0; i < 2000; i++) {
      rows.push(`<tr class="r${i % 7}"><td id="c${i}">cell ${i}</td><td><a href="/item/${i}">link</a></td><td><span>${i * 3}</span></td></tr>`);
    }
    window.__markup = `<table><tbody>${rows.join("")}</tbody></table>`;
  },
  run(window, document) {
    document.body.innerHTML = window.__markup;
    return document.body.getElementsByTagName("td").length;
  },
})
