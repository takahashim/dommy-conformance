// The harness both sides share. It runs unchanged in headless Chromium and in
// dommy-js-quickjs, so it may use nothing but DOM + ECMAScript.
//
// Its whole job is to turn "what happened" into a value that is EQUAL between
// two correct implementations and UNEQUAL between a correct one and a wrong
// one. That rules out anything carrying engine-specific noise: object identity
// (which cannot cross JSON at all), innerHTML (attribute order and quoting are
// serializer choices), error messages, and iteration order of unordered
// collections. What is left is positions, names, and structure.
(function (global) {
  "use strict";

  var HTML_NS = "http://www.w3.org/1999/xhtml";
  var cases = [];

  // Registration REPLACES rather than appends: a runner evaluates the source
  // once to learn the case's `html` and again once the document exists, and
  // re-registering must not look like two cases.
  global.defineCase = function (spec) {
    cases = [spec];
  };

  // ---- node identity ------------------------------------------------------
  // Two engines have no shared object identity, so every node is referred to by
  // either a name the case gave it or its position in the tree. Positions are
  // recomputed on every call, so a reference taken after a mutation describes
  // where the node is NOW — which is the point when the thing under test is a
  // node that moved.

  function Harness() {
    this._tags = [];       // [node, name] pairs; no Map, to stay dependency-free
    this._events = [];
  }

  Harness.prototype.tag = function (node, name) {
    this._tags.push([node, name]);
    return node;
  };

  Harness.prototype._tagOf = function (node) {
    for (var i = 0; i < this._tags.length; i++) {
      if (this._tags[i][0] === node) return this._tags[i][1];
    }
    return null;
  };

  function nodeLabel(node) {
    switch (node.nodeType) {
      case 1: return node.localName;
      case 3: return "#text";
      case 4: return "#cdata";
      case 7: return "#pi:" + node.target;
      case 8: return "#comment";
      case 9: return "#document";
      case 10: return "#doctype";
      case 11: return "#fragment";
      default: return "#type" + node.nodeType;
    }
  }

  // "html[0]/body[1]/div[0]" — the child index at each step, so a serializer's
  // idea of which whitespace to keep cannot shift the answer.
  Harness.prototype.ref = function (node) {
    if (node === null || node === undefined) return null;

    var tagged = this._tagOf(node);
    if (tagged) return "@" + tagged;

    var steps = [];
    var current = node;
    while (current) {
      var parent = current.parentNode;
      if (!parent) {
        // Every detached root of the same node type would otherwise get the
        // same label, so two paths under DIFFERENT detached subtrees would
        // compare equal and a real divergence would read as a coincidence.
        //
        // Naming them in first-seen order would fix that but make divergences
        // CONTAGIOUS: the moment the two engines disagree about how many nodes
        // get looked at, every later detached label drifts by one and unrelated
        // steps light up. So the name is derived from the subtree itself —
        // order-independent, and equal between two engines exactly when the
        // subtrees are equal, which is the only thing being asked.
        steps.unshift(current.nodeType === 9 ? "#document" : "<detached " + this._detachedName(current) + ">");
        break;
      }
      var index = 0;
      var kids = parent.childNodes;
      for (var i = 0; i < kids.length; i++) {
        if (kids[i] === current) { index = i; break; }
      }
      steps.unshift(nodeLabel(current) + "[" + index + "]");
      current = parent;
    }
    return steps.join("/");
  };

  Harness.prototype._detachedName = function (root) {
    var label = nodeLabel(root);
    if (root.nodeType === 1 && root.id) return label + "#" + root.id;

    // No id to go on, so use the subtree's own shape. A 32-bit FNV-1a keeps the
    // label short; a collision would merely make two different subtrees compare
    // equal, which is the pre-existing behaviour, never a false divergence.
    var shape = this._shapeKey(root);
    var hash = 0x811c9dc5;
    for (var i = 0; i < shape.length; i++) {
      hash ^= shape.charCodeAt(i);
      hash = Math.imul(hash, 0x01000193) >>> 0;
    }
    return label + "~" + hash.toString(36);
  };

  Harness.prototype._shapeKey = function (node) {
    if (node.nodeType === 3 || node.nodeType === 8) return node.data;
    var out = nodeLabel(node) + (node.nodeType === 1 && node.id ? "#" + node.id : "") + "(";
    var kids = node.childNodes;
    for (var i = 0; i < kids.length; i++) out += this._shapeKey(kids[i]) + ",";
    return out + ")";
  };

  Harness.prototype.refs = function (list) {
    var out = [];
    for (var i = 0; i < list.length; i++) out.push(this.ref(list[i]));
    return out;
  };

  // ---- tree serialization -------------------------------------------------
  // Built from the node interfaces rather than from innerHTML: attribute order
  // is normalized, and text / comment nodes stay individually visible (whether
  // adjacent text nodes were merged is exactly the kind of thing under test).

  Harness.prototype.dom = function (node) {
    if (node === null || node === undefined) return null;

    switch (node.nodeType) {
      case 1: {
        var attrs = [];
        for (var i = 0; i < node.attributes.length; i++) {
          var a = node.attributes[i];
          attrs.push([a.name, a.value]);
        }
        attrs.sort(function (x, y) { return x[0] < y[0] ? -1 : x[0] > y[0] ? 1 : 0; });
        var out = { el: node.localName, attrs: attrs, kids: this.kids(node) };
        if (node.namespaceURI !== HTML_NS) out.ns = node.namespaceURI;
        return out;
      }
      case 3: return { text: node.data };
      case 4: return { cdata: node.data };
      case 7: return { pi: node.target, data: node.data };
      case 8: return { comment: node.data };
      case 10: return { doctype: node.name, publicId: node.publicId, systemId: node.systemId };
      case 9:
      case 11: return { root: nodeLabel(node), kids: this.kids(node) };
      default: return { nodeType: node.nodeType };
    }
  };

  Harness.prototype.kids = function (node) {
    var out = [];
    var kids = node.childNodes;
    for (var i = 0; i < kids.length; i++) out.push(this.dom(kids[i]));
    return out;
  };

  // Just the shape — element names and nesting, no attributes or text. Useful
  // when a case is about where nodes ended up, not about their content.
  Harness.prototype.shape = function (node) {
    var out = [];
    var kids = node.childNodes;
    for (var i = 0; i < kids.length; i++) {
      var child = kids[i];
      out.push(child.nodeType === 1 ? child.localName + (child.childNodes.length ? "(" + this.shape(child).join(",") + ")" : "") : nodeLabel(child));
    }
    return out;
  };

  // ---- the live objects a mutation is observed through --------------------

  Harness.prototype.range = function (range) {
    return {
      start: [this.ref(range.startContainer), range.startOffset],
      end: [this.ref(range.endContainer), range.endOffset],
      collapsed: range.collapsed
    };
  };

  Harness.prototype.iterator = function (iterator) {
    return {
      reference: this.ref(iterator.referenceNode),
      pointerBefore: iterator.pointerBeforeReferenceNode
    };
  };

  Harness.prototype.walker = function (walker) {
    return { current: this.ref(walker.currentNode) };
  };

  // MutationRecords, drained synchronously. takeRecords() is used rather than
  // the callback so a case stays deterministic without depending on when each
  // engine reaches its microtask checkpoint.
  Harness.prototype.records = function (observer) {
    var self = this;
    return observer.takeRecords().map(function (record) {
      var out = { type: record.type, target: self.ref(record.target) };
      if (record.type === "childList") {
        out.added = self.refs(record.addedNodes);
        out.removed = self.refs(record.removedNodes);
        out.previousSibling = self.ref(record.previousSibling);
        out.nextSibling = self.ref(record.nextSibling);
      } else if (record.type === "attributes") {
        out.attributeName = record.attributeName;
        out.attributeNamespace = record.attributeNamespace;
        out.oldValue = record.oldValue;
      } else {
        out.oldValue = record.oldValue;
      }
      return out;
    });
  };

  Harness.prototype.observe = function (target, options) {
    var observer = new MutationObserver(function () {});
    observer.observe(target, options);
    return observer;
  };

  // ---- outcomes -----------------------------------------------------------

  // A thrown DOMException is identified by its `name`, never its message: the
  // names are normative, the messages are not.
  Harness.prototype.attempt = function (fn) {
    try {
      return { value: fn() };
    } catch (error) {
      if (error && typeof error.name === "string") {
        // Only ever set a key to a real value: `undefined` disappears through
        // JSON.stringify but survives as null through a Ruby bridge, which
        // would make two agreeing engines look different.
        var out = { threw: error.name };
        if (typeof error.code === "number") out.code = error.code;
        return out;
      }
      return { threw: String(error) };
    }
  };

  // Record an ordered log — event dispatch order, callback order. The case
  // pushes plain strings; ordering IS the observation.
  Harness.prototype.log = function (entry) {
    this._events.push(entry);
    return entry;
  };

  Harness.prototype.logged = function () {
    return this._events.slice();
  };

  // Knobs a runner may widen from the environment (see `rake fuzz SEEDS=...`).
  // A case reads them through here so its committed default stays the thing CI
  // runs, and a deeper ad-hoc run needs no edit.
  Harness.prototype.config = function (name, fallback) {
    var config = global.__oracleConfig;
    var value = config && config[name] !== undefined && config[name] !== null ? config[name] : fallback;
    return typeof fallback === "number" ? Number(value) : value;
  };

  // Let queued microtasks (and any promise the case is waiting on) run. Both
  // runners await the case's return value, so a case may simply `await h.tick()`.
  Harness.prototype.tick = function () {
    return Promise.resolve();
  };

  // ---- entry point --------------------------------------------------------
  // Returns { name, result } or { name, error } — never throws, so one broken
  // case cannot take the run down with it.

  global.__oracleRun = async function () {
    if (cases.length !== 1) {
      return { error: "a case file must register exactly one case, found " + cases.length };
    }
    var spec = cases[0];
    try {
      var harness = new Harness();
      var result = await spec.run(harness);
      return { name: spec.name, result: result === undefined ? null : result };
    } catch (error) {
      return {
        name: spec.name,
        error: (error && error.name ? error.name + ": " : "") + (error && error.message ? error.message : String(error))
      };
    }
  };

  global.__oracleHtml = function () {
    return cases.length === 1 ? (cases[0].html || "") : "";
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
