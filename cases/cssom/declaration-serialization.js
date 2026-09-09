// A declaration block round-trips through cssText, and the shorthand/longhand
// relationship is visible in both directions.
defineCase({
  name: "inline style declaration serialization",
  html: "<p id=x></p>",
  run(h) {
    const style = document.getElementById("x").style;
    const snapshot = () => ({
      cssText: style.cssText,
      attribute: document.getElementById("x").getAttribute("style"),
      length: style.length,
      items: Array.from({ length: style.length }, (_, i) => style.item(i))
    });

    style.cssText = "color: red; margin-top: 1px";
    const afterCssText = snapshot();

    style.setProperty("color", "blue");
    style.setProperty("background-color", "green", "important");
    const afterSetProperty = snapshot();

    const removed = style.removeProperty("margin-top");
    const afterRemove = { removed, ...snapshot() };

    style.cssText = "";
    const afterClear = snapshot();

    style.cssText = "color: red !important; color: blue";
    const laterWins = { ...snapshot(), priority: style.getPropertyPriority("color"), value: style.getPropertyValue("color") };

    style.cssText = "color:; width: 10px; : ; bogus";
    const invalidDropped = snapshot();

    style.cssText = "--custom: 1px; color: var(--custom)";
    const customProperty = {
      ...snapshot(),
      custom: style.getPropertyValue("--custom"),
      unknown: style.getPropertyValue("--missing")
    };

    return { afterCssText, afterSetProperty, afterRemove, afterClear, laterWins, invalidDropped, customProperty };
  }
});
