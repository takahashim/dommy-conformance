// WebIDL's string conversions (DOMString, USVString, ByteString), made of a
// script's values before an operation, a constructor or an attribute setter
// sees them: ToString on an object runs its own toString, a Symbol throws, a
// nullable type takes null and undefined as null, [LegacyNullToEmptyString]
// takes null as "", an optional argument passed as undefined takes its default,
// a USVString replaces lone surrogates, and a ByteString rejects a code unit
// above U+00FF. The arguments are converted in order, and all of them before
// the operation runs, so a toString that throws leaves nothing done.
//
// WPT tests these one interface at a time; here the same values go through
// every kind of entry point, which is where a binding that converts some of
// them and not others shows.
defineCase({
  name: "WebIDL string conversions at every entry point",
  url: "http://oracle.test/dir/page.html",
  html: '<div id="target"></div><input id="input"><textarea id="area"></textarea>' +
    '<select id="select"><option id="option">x</option></select>',
  run(h) {
    const named = (text) => ({ toString() { return text; } });
    const target = () => {
      const element = document.createElement("span");
      document.getElementById("target").appendChild(element);
      return element;
    };
    const codeUnits = (s) => (s === null ? null : Array.from(s, (c) => c.charCodeAt(0).toString(16)).join(" "));

    // Operations: an object, null, undefined, a number and a Symbol as a
    // DOMString argument, and a nullable one.
    const operations = {
      objectName: h.attempt(() => { const e = target(); e.setAttribute(named("data-o"), named("v")); return e.getAttribute("data-o"); }),
      nullValue: h.attempt(() => { const e = target(); e.setAttribute("data-n", null); return e.getAttribute("data-n"); }),
      undefinedValue: h.attempt(() => { const e = target(); e.setAttribute("data-u", undefined); return e.getAttribute("data-u"); }),
      numberValue: h.attempt(() => { const e = target(); e.setAttribute("data-num", 1.50); return e.getAttribute("data-num"); }),
      symbolName: h.attempt(() => target().setAttribute(Symbol("s"), "v")),
      objectSelector: h.attempt(() => h.ref(document.querySelector(named("#target")))),
      nullableNamespaceUndefined: h.attempt(() => { const e = target(); e.setAttributeNS(undefined, "plain", "v"); return [e.getAttributeNS(null, "plain"), e.attributes[0].namespaceURI]; }),
      variadicTokens: h.attempt(() => { const e = target(); e.classList.add(named("a"), 2, null); return e.className; })
    };

    // Every argument is converted, in order, before the operation does
    // anything: the second toString throwing leaves no attribute behind.
    const order = [];
    const throwing = h.attempt(() => {
      const e = target();
      e.setAttribute(
        { toString() { order.push("name"); return "data-t"; } },
        { toString() { order.push("value"); throw new RangeError("from toString"); } }
      );
    });
    const leftBehind = document.getElementById("target").lastChild.hasAttribute("data-t");

    // Attribute setters: a plain DOMString, [LegacyNullToEmptyString], and a
    // DOMString that is NOT null-to-empty on a neighbouring interface.
    const set = (element, attribute, value) => h.attempt(() => { element[attribute] = value; return element[attribute]; });
    const attributes = {
      idNull: set(target(), "id", null),
      idObject: set(target(), "id", named("named")),
      idSymbol: set(target(), "id", Symbol("s")),
      titleUndefined: set(target(), "title", undefined),
      innerHTMLNull: set(target(), "innerHTML", null),
      inputValueNull: set(document.getElementById("input"), "value", null),
      textareaValueNull: set(document.getElementById("area"), "value", null),
      optionValueNull: set(document.getElementById("option"), "value", null),
      datasetNull: h.attempt(() => { const e = target(); e.dataset.x = null; return e.dataset.x; }),
      styleTextNull: h.attempt(() => { const e = target(); e.style.cssText = "color: red"; e.style.cssText = null; return e.getAttribute("style"); })
    };

    // Optional arguments passed as undefined take their default.
    const optional = {
      commentUndefined: h.attempt(() => new Comment(undefined).data),
      textObject: h.attempt(() => new Text(named("t")).data),
      priorityUndefined: h.attempt(() => { const e = target(); e.style.setProperty("color", "red", undefined); return e.style.getPropertyPriority("color"); }),
      eventTypeObject: h.attempt(() => new Event(named("ping")).type)
    };

    // USVString: the URL API, which takes nothing else.
    const usv = {
      constructorObjects: h.attempt(() => new URL(named("y"), named("https://a.test/x/")).href),
      constructorLocationBase: h.attempt(() => new URL("y", location).href),
      staticObject: h.attempt(() => URL.canParse(named("https://a.test/"))),
      searchLoneSurrogate: h.attempt(() => { const u = new URL("https://a.test/"); u.search = "\uD800x"; return u.search; }),
      hashObject: h.attempt(() => { const u = new URL("https://a.test/"); u.hash = named("h"); return u.hash; }),
      paramsSetObject: h.attempt(() => { const p = new URLSearchParams(); p.set(named("k"), named("v")); return p.toString(); }),
      paramsHasObject: h.attempt(() => new URLSearchParams("k=1").has(named("k"))),
      paramsAppendSymbol: h.attempt(() => new URLSearchParams().append(Symbol("s"), "v")),
      paramsGetLoneSurrogate: h.attempt(() => { const p = new URLSearchParams(); p.append("\uDC00", "v"); return codeUnits(p.toString()); })
    };

    // ByteString: Headers, whose names and values are bytes.
    const bytes = {
      latin1: h.attempt(() => { const headers = new Headers(); headers.append("x-a", "café"); return codeUnits(headers.get("x-a")); }),
      aboveLatin1: h.attempt(() => new Headers().append("x-a", "Ā")),
      object: h.attempt(() => { const headers = new Headers(); headers.set(named("x-b"), named("v")); return headers.get("x-b"); })
    };

    return { operations, throwing, order, leftBehind, attributes, optional, usv, bytes };
  }
});
