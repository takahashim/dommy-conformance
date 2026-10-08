// The cascade: getComputedStyle against a 60-rule sheet.
({
  setup(window, document) {
    let css = "";
    for (let i = 0; i < 30; i++) css += `.k${i} { color: rgb(${i}, 0, 0); } .k${i} span { margin-left: ${i}px; }\n`;
    const style = document.createElement("style");
    style.textContent = css;
    document.head.appendChild(style);
    let html = "";
    for (let i = 0; i < 300; i++) html += `<div class="k${i % 30}"><span>${i}</span></div>`;
    document.body.innerHTML = html;
  },
  run(window, document) {
    let acc = 0;
    const spans = document.querySelectorAll("span");
    for (let i = 0; i < spans.length; i++) {
      acc += window.getComputedStyle(spans[i]).marginLeft.length;
      acc += window.getComputedStyle(spans[i].parentNode).color.length;
    }
    return acc;
  },
})
