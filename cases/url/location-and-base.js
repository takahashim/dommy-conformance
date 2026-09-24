// What `location` reports, and what a relative URL in the document resolves
// against. Both need the document to HAVE a URL, which is what `url:` gives it
// on either side; WPT's own Location suite is mostly out of reach here because
// it navigates for real, so the parts and the fragment setter are worth pinning
// against a browser instead.
//
// Left out on purpose:
//   * `search` / `pathname` / `protocol` setters navigate, and a navigation in
//     the browser tears down the context the case is running in.
//   * `assign("#x")` / `replace("#x")` are queued in Chromium and applied at
//     once by Dommy, so a value read straight afterwards compares two different
//     moments rather than two behaviours.
//   * `JSON.stringify(location)`, whose key order is a serializer choice.
defineCase({
  name: "location's parts, the fragment setter, and what a relative URL resolves against",
  url: "http://oracle.test/dir/page.html?q=1&r=2#frag",
  html: [
    '<base href="/base/sub/">',
    '<a id="rel" href="../other/x.html?a=b#c"></a>',
    '<a id="dotted" href="./y"></a>',
    '<a id="rooted" href="/z?k=v"></a>',
    '<a id="schemeless" href="//elsewhere.test/w"></a>',
    '<a id="fragmentOnly" href="#only"></a>',
    '<a id="empty" href=""></a>',
    '<form id="form" action="post"></form>'
  ].join(""),
  run(h) {
    var parts = {};
    ["protocol", "host", "hostname", "port", "pathname", "search", "hash", "origin", "href"].forEach(function (key) {
      parts[key] = String(location[key]);
    });

    var resolved = {};
    ["rel", "dotted", "rooted", "schemeless", "fragmentOnly", "empty"].forEach(function (id) {
      resolved[id] = document.getElementById(id).href;
    });

    // A fragment change is same-document, so the case survives it. `hash = ""`
    // is the interesting one: clearing a fragment that is there keeps the "#".
    var fragments = [];
    function record(label) {
      fragments.push([label, location.href, location.hash]);
    }
    record("initial");
    location.hash = "next";
    record("hash = 'next'");
    location.hash = "#hashed";
    record("hash = '#hashed'");
    location.hash = "";
    record("hash = ''");
    location.hash = "back";
    record("hash = 'back'");

    return {
      parts: parts,
      stringified: [String(location), location.toString()],
      document: { URL: document.URL, documentURI: document.documentURI, baseURI: document.baseURI },
      resolved: resolved,
      formAction: document.getElementById("form").action,
      fragments: fragments
    };
  }
});
