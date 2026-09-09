// DOMTokenList is a live, ordered, de-duplicating view over one attribute, and
// every mutation writes the whole serialization back.
defineCase({
  name: "classList mutation, ordering and serialization",
  html: "<div id=d class='  a   b  a c '></div>",
  run(h) {
    const div = document.getElementById("d");
    const list = div.classList;
    const state = () => [div.getAttribute("class"), list.length, [...list], list.value];

    const initial = state();
    list.add("d", "b");
    const afterAdd = state();
    list.remove("a");
    const afterRemove = state();
    const toggled = [list.toggle("b"), list.toggle("z"), list.toggle("q", false), list.toggle("q", true)];
    const afterToggle = state();
    const replaced = list.replace("c", "e");
    const missingReplace = list.replace("nope", "f");
    const afterReplace = state();

    div.setAttribute("class", "x  y");
    const afterAttributeWrite = state();

    const errors = {
      empty: h.attempt(() => list.add("")),
      whitespace: h.attempt(() => list.add("a b")),
      containsEmpty: h.attempt(() => list.contains(""))
    };

    return { initial, afterAdd, afterRemove, toggled, afterToggle, replaced, missingReplace, afterReplace, afterAttributeWrite, errors };
  }
});
