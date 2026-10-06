// A hidden _charset_ input with an explicit value in the entry list.
defineCase({
  name: "hidden _charset_ with a value",
  html: "<form id=f><input type=hidden name=_charset_ value=x><input type=radio id=r required></form>",
  run(h) {
    const fd = new FormData(document.getElementById("f"));
    const r = document.getElementById("r");
    return { charset: fd.get("_charset_"), unnamedRadioMissing: r.validity.valueMissing };
  }
});
