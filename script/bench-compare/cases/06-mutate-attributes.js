// Attribute, class and inline-style churn on existing elements.
({
  setup(window, document) {
    let html = "";
    for (let i = 0; i < 500; i++) html += `<div id="d${i}" class="box">${i}</div>`;
    document.body.innerHTML = html;
  },
  run(window, document) {
    const els = document.body.children;
    for (let pass = 0; pass < 4; pass++) {
      for (let i = 0; i < els.length; i++) {
        const el = els[i];
        el.classList.toggle("active");
        el.setAttribute("aria-selected", String((i + pass) % 2 === 0));
        el.dataset.pass = String(pass);
        el.style.setProperty("width", `${i + pass}px`);
      }
    }
    return document.querySelectorAll(".active").length + els[7].style.width.length;
  },
})
