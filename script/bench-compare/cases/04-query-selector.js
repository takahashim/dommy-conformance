// Selector matching over a 1500-element tree, simple and combinator selectors.
({
  setup(window, document) {
    let html = "";
    for (let i = 0; i < 300; i++) {
      html += `<section class="s${i % 10}" id="s${i}"><h2>t</h2><ul><li class="a">x</li><li class="b"><em>y</em></li></ul></section>`;
    }
    document.body.innerHTML = html;
  },
  run(window, document) {
    let n = 0;
    for (let i = 0; i < 200; i++) {
      n += document.querySelectorAll(".s3 li.b > em").length;
      n += document.querySelector(`#s${i}`) ? 1 : 0;
      n += document.querySelectorAll("section:nth-child(3n) h2").length;
      n += document.querySelector("li.a + li.b em") ? 1 : 0;
    }
    return n;
  },
})
