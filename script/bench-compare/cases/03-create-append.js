// Building a tree from script, the way a client-side renderer does.
({
  setup() {},
  run(window, document) {
    const list = document.createElement("ul");
    document.body.appendChild(list);
    for (let i = 0; i < 3000; i++) {
      const li = document.createElement("li");
      li.setAttribute("data-id", String(i));
      li.className = i % 2 ? "odd" : "even";
      li.appendChild(document.createTextNode("item " + i));
      list.appendChild(li);
    }
    return list.childNodes.length + list.lastChild.textContent.length;
  },
})
