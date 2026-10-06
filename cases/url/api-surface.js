// The URL Standard's API as WebIDL shapes it, beyond what url/*.any.js in WPT
// asserts: the members are on the interface prototypes (where feature
// detection looks), a prototype member called on the wrong object throws,
// URLSearchParams is a pair iterable whose @@iterator IS entries and whose
// iterators inherit from %IteratorPrototype%, forEach takes a thisArg and
// rejects a non-callable, a call with too few arguments is a TypeError, an
// ASCII "xn--" label is validated as Punycode, and a blob: URL from
// createObjectURL carries the creating document's origin.
defineCase({
  name: "the URL API's WebIDL surface",
  url: "http://oracle.test/dir/page.html",
  html: "",
  run(h) {
    const has = (proto, names) => names.filter((name) => !(name in proto));
    const surface = {
      urlMissing: has(URL.prototype, ["href", "origin", "protocol", "username", "password", "host", "hostname",
        "port", "pathname", "search", "searchParams", "hash", "toJSON", "toString"]),
      paramsMissing: has(URLSearchParams.prototype, ["append", "delete", "get", "getAll", "has", "set", "sort",
        "toString", "size", "entries", "keys", "values", "forEach"]),
      hrefDescriptor: (() => {
        const d = Object.getOwnPropertyDescriptor(URL.prototype, "href");
        return d ? [typeof d.get, typeof d.set, d.enumerable, d.configurable] : null;
      })(),
      paramsLength: "length" in new URLSearchParams("a=1"),
      staticLengths: [URL.length, URLSearchParams.length, URL.parse.length, URL.canParse.length]
    };

    const receivers = {
      hrefOnPrototype: h.attempt(() => URL.prototype.href),
      toJSONOnObject: h.attempt(() => URL.prototype.toJSON.call({})),
      appendOnURL: h.attempt(() => URLSearchParams.prototype.append.call(new URL("http://a.test/"), "a", "b")),
      appendViaPrototype: h.attempt(() => {
        const p = new URLSearchParams();
        URLSearchParams.prototype.append.call(p, "a", "b");
        return p.toString();
      })
    };

    const params = new URLSearchParams("a=1&b=2&c=3");
    const iteratorPrototype = Object.getPrototypeOf(Object.getPrototypeOf([][Symbol.iterator]()));
    const forEachThis = [];
    params.forEach(function (value, key, self) { forEachThis.push([key, value, this.tag, self === params]); }, { tag: "t" });
    const iteration = {
      iteratorIsEntries: URLSearchParams.prototype[Symbol.iterator] === URLSearchParams.prototype.entries,
      iteratorTag: Object.prototype.toString.call(params.keys()),
      inheritsIteratorPrototype: Object.getPrototypeOf(Object.getPrototypeOf(params.values())) === iteratorPrototype,
      nextOnObject: h.attempt(() => params.entries().next.call({})),
      live: (() => {
        const live = new URLSearchParams("a=1&b=2&c=3");
        const seen = [];
        for (const [key] of live) {
          seen.push(key);
          if (key === "a") live.delete("b");
        }
        return seen;
      })(),
      forEachThis,
      forEachNonCallable: h.attempt(() => params.forEach(1))
    };

    const arity = {
      parse: h.attempt(() => URL.parse()),
      canParse: h.attempt(() => URL.canParse()),
      construct: h.attempt(() => new URL()),
      append: h.attempt(() => new URLSearchParams().append("x")),
      get: h.attempt(() => new URLSearchParams().get())
    };

    const hosts = {};
    for (const host of ["xn--zca.test", "XN--ZCA.test", "xn--a.test", "xn--.test", "xn--abc-.test"]) {
      hosts[host] = h.attempt(() => new URL("http://" + host + "/").host);
    }

    const blobURL = URL.createObjectURL(new Blob(["x"]));
    const blobs = {
      shape: blobURL.replace(/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/, "<uuid>"),
      origin: new URL(blobURL).origin,
      notABlob: h.attempt(() => URL.createObjectURL("x"))
    };
    URL.revokeObjectURL(blobURL);

    return { surface, receivers, iteration, arity, hosts, blobs };
  }
});
