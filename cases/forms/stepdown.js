// stepDown()/stepUp() from an empty value with a min/max the step leaves.
defineCase({
  name: "stepping from an empty value",
  html: "<input id=a type=number min=7><input id=b type=number max=-7><input id=c type=number min=7 value=3>",
  run(h) {
    const a = document.getElementById("a"); a.stepDown();
    const b = document.getElementById("b"); b.stepUp();
    const c = document.getElementById("c"); c.stepDown();
    return { a: a.value, b: b.value, c: c.value };
  }
});
