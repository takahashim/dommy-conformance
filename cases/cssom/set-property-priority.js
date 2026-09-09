// CSSOM setProperty step 4: a priority that is neither the empty string nor an
// ASCII case-insensitive "important" abandons the call. Step 3 (an empty value
// removes the declaration) runs BEFORE it — that ordering is the one place
// Chromium and the spec text disagree.
defineCase({
  name: "setProperty priority validation",
  html: "<p id=x></p>",
  run(h) {
    const element = document.getElementById("x");
    const withRedImportant = (apply) => {
      element.setAttribute("style", "color: red !important");
      apply(element.style);
      return element.getAttribute("style");
    };

    const accepted = {};
    for (const priority of ["important", "IMPORTANT", "", "bogus", "important!", " important ", "!important"]) {
      accepted[JSON.stringify(priority)] = withRedImportant((style) => style.setProperty("color", "blue", priority));
    }

    return {
      byPriority: accepted,
      nullPriority: withRedImportant((style) => style.setProperty("color", "blue", null)),
      omittedPriority: withRedImportant((style) => style.setProperty("color", "blue")),
      emptyValueWithInvalidPriority: withRedImportant((style) => style.setProperty("color", "", "bogus"))
    };
  }
});
