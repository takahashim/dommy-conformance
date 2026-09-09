// Random mutation sequences, run identically in both engines.
//
// The hand-written cases each pin one behaviour someone already thought of.
// This finds the ones nobody did: the combinations. A live Range, a
// NodeIterator and a MutationObserver are all pointed at one tree, then a
// deterministic pseudo-random sequence of DOM mutations is applied to it, and
// everything observable is recorded after every step.
//
// Determinism is the whole trick. Both engines run the SAME sequence because
// the PRNG is seeded and integer-exact (Math.imul / >>> are bit-for-bit
// identical everywhere), and because every operand is chosen from the tree by
// index rather than by anything engine-specific. So when step 42 of seed 7
// differs, that is a real behavioural divergence and not two different runs.
//
// Once the two DO diverge they naturally pick different operands afterwards, so
// the diff reports the FIRST differing step and stops — everything after it is
// an echo, not evidence.
(function (global) {
  "use strict";

  // mulberry32: small, fast, and defined entirely in 32-bit integer ops, so two
  // engines cannot disagree about it.
  function rng(seed) {
    var a = seed >>> 0;
    return function () {
      a = (a + 0x6D2B79F5) >>> 0;
      var t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  function Fuzzer(harness, root, seed) {
    this.h = harness;
    this.root = root;
    this.random = rng(seed);
    this.serial = 0;
    this.detached = [];
  }

  Fuzzer.prototype.int = function (n) {
    return n <= 0 ? 0 : Math.floor(this.random() * n) % n;
  };

  Fuzzer.prototype.pick = function (list) {
    return list.length ? list[this.int(list.length)] : null;
  };

  // Every node under the root, in document order — the operand pool. Order is
  // structural, so both engines index into the same list as long as their trees
  // still agree.
  Fuzzer.prototype.nodes = function (filter) {
    var out = [];
    (function walk(node) {
      out.push(node);
      var kids = node.childNodes;
      for (var i = 0; i < kids.length; i++) walk(kids[i]);
    })(this.root);
    return filter ? out.filter(filter) : out;
  };

  Fuzzer.prototype.elements = function () {
    return this.nodes(function (n) { return n.nodeType === 1; });
  };

  Fuzzer.prototype.texts = function () {
    return this.nodes(function (n) { return n.nodeType === 3; });
  };

  // A parent that may receive children, and a node that may be moved (never the
  // root itself, and never an ancestor of the parent — those throw
  // HierarchyRequestError, which is correct but uninteresting to repeat).
  Fuzzer.prototype.movable = function (parent) {
    return this.nodes(function (n) {
      return n !== parent && n.parentNode && !n.contains(parent);
    });
  };

  Fuzzer.prototype.fresh = function () {
    this.serial++;
    var kind = this.int(3);
    if (kind === 0) {
      var el = document.createElement(["u", "s", "q", "em"][this.int(4)]);
      el.id = "n" + this.serial;
      if (this.int(2)) el.appendChild(document.createTextNode("t" + this.serial));
      return el;
    }
    if (kind === 1) return document.createTextNode("x" + this.serial);
    return document.createComment("c" + this.serial);
  };

  // ---- the operations -----------------------------------------------------
  // Each returns a short label describing what it did, so a divergence comes
  // with the sequence that produced it.

  Fuzzer.prototype.OPERATIONS = [
    function appendChildMove(f) {
      var parent = f.pick(f.elements());
      var node = f.pick(f.movable(parent));
      if (!parent || !node) return null;
      parent.appendChild(node);
      return "appendChild(" + f.label(parent) + ", " + f.label(node) + ")";
    },
    function appendChildFresh(f) {
      var parent = f.pick(f.elements());
      if (!parent) return null;
      var node = f.fresh();
      parent.appendChild(node);
      return "appendChild(" + f.label(parent) + ", new)";
    },
    function insertBefore(f) {
      var parent = f.pick(f.elements().filter(function (e) { return e.childNodes.length; }));
      if (!parent) return null;
      var ref = parent.childNodes[f.int(parent.childNodes.length)];
      var node = f.int(2) ? f.fresh() : f.pick(f.movable(parent));
      if (!node || node === ref) return null;
      parent.insertBefore(node, ref);
      return "insertBefore(" + f.label(parent) + ", " + f.label(node) + ", before " + f.label(ref) + ")";
    },
    function removeChild(f) {
      var node = f.pick(f.nodes(function (n) { return n.parentNode; }));
      if (!node) return null;
      var parent = node.parentNode;
      parent.removeChild(node);
      f.detached.push(node);
      return "removeChild(" + f.label(parent) + ", " + f.label(node) + ")";
    },
    function replaceChild(f) {
      var old = f.pick(f.nodes(function (n) { return n.parentNode && n !== f.root; }));
      if (!old) return null;
      var parent = old.parentNode;
      var node = f.int(2) ? f.fresh() : f.pick(f.movable(parent));
      if (!node) return null;
      parent.replaceChild(node, old);
      return "replaceChild(" + f.label(parent) + ", " + f.label(node) + ", " + f.label(old) + ")";
    },
    function replaceWith(f) {
      var node = f.pick(f.nodes(function (n) { return n.parentNode && n !== f.root; }));
      if (!node) return null;
      node.replaceWith(f.fresh(), f.fresh());
      return "replaceWith(" + f.label(node) + ", 2 new)";
    },
    function beforeAfter(f) {
      var node = f.pick(f.nodes(function (n) { return n.parentNode && n !== f.root; }));
      if (!node) return null;
      var after = f.int(2);
      if (after) node.after(f.fresh()); else node.before(f.fresh());
      return (after ? "after(" : "before(") + f.label(node) + ", new)";
    },
    function replaceChildren(f) {
      var parent = f.pick(f.elements());
      if (!parent) return null;
      var count = f.int(3);
      var kids = [];
      for (var i = 0; i < count; i++) kids.push(f.fresh());
      parent.replaceChildren.apply(parent, kids);
      return "replaceChildren(" + f.label(parent) + ", " + count + ")";
    },
    function setTextContent(f) {
      var parent = f.pick(f.elements());
      if (!parent) return null;
      var value = f.int(4) === 0 ? "" : "T" + (++f.serial);
      parent.textContent = value;
      return "textContent(" + f.label(parent) + ", " + JSON.stringify(value) + ")";
    },
    function normalize(f) {
      var parent = f.pick(f.elements());
      if (!parent) return null;
      parent.normalize();
      return "normalize(" + f.label(parent) + ")";
    },
    function splitText(f) {
      var text = f.pick(f.texts());
      if (!text) return null;
      var offset = f.int(text.length + 1);
      text.splitText(offset);
      return "splitText(" + f.label(text) + ", " + offset + ")";
    },
    function editData(f) {
      var text = f.pick(f.texts());
      if (!text) return null;
      var offset = f.int(text.length + 1);
      var count = f.int(text.length - offset + 1);
      var mode = f.int(3);
      if (mode === 0) text.insertData(offset, "i" + (++f.serial));
      else if (mode === 1) text.deleteData(offset, count);
      else text.replaceData(offset, count, "r" + (++f.serial));
      return ["insertData", "deleteData", "replaceData"][mode] + "(" + f.label(text) + ", " + offset + ", " + count + ")";
    },
    function insertFragment(f) {
      var parent = f.pick(f.elements());
      if (!parent) return null;
      var fragment = document.createDocumentFragment();
      var count = 1 + f.int(3);
      for (var i = 0; i < count; i++) fragment.appendChild(f.fresh());
      if (f.int(2) && parent.firstChild) parent.insertBefore(fragment, parent.firstChild);
      else parent.appendChild(fragment);
      return "insertFragment(" + f.label(parent) + ", " + count + ")";
    },
    function reattachDetached(f) {
      var node = f.pick(f.detached.filter(function (n) { return !n.parentNode; }));
      var parent = f.pick(f.elements());
      if (!node || !parent || node.contains(parent)) return null;
      parent.appendChild(node);
      return "reattach(" + f.label(parent) + ", " + f.label(node) + ")";
    }
  ];

  // A short, position-independent name for an operand, so the op log reads as
  // something a person could turn into a hand-written case.
  Fuzzer.prototype.label = function (node) {
    if (!node) return "null";
    if (node === this.root) return "root";
    if (node.nodeType === 1) return node.localName + (node.id ? "#" + node.id : "");
    if (node.nodeType === 3) return "#text" + JSON.stringify(node.data.slice(0, 6));
    if (node.nodeType === 8) return "#comment";
    return "#" + node.nodeType;
  };

  // ---- observation --------------------------------------------------------
  // Compact on purpose: this is recorded after every step of every seed, and it
  // has to stay readable when the diff prints it.

  Fuzzer.prototype.tree = function (node) {
    var self = this;
    if (node.nodeType === 3) return JSON.stringify(node.data);
    if (node.nodeType === 8) return "<!--" + node.data + "-->";
    var kids = [];
    for (var i = 0; i < node.childNodes.length; i++) kids.push(self.tree(node.childNodes[i]));
    return this.label(node) + (kids.length ? "(" + kids.join(" ") + ")" : "");
  };

  Fuzzer.prototype.observe = function (ranges, iterators, observer) {
    var self = this;
    return {
      tree: this.tree(this.root),
      ranges: ranges.map(function (r) {
        return self.h.ref(r.startContainer) + ":" + r.startOffset + ".." +
               self.h.ref(r.endContainer) + ":" + r.endOffset;
      }),
      iterators: iterators.map(function (it) {
        return self.h.ref(it.referenceNode) + (it.pointerBeforeReferenceNode ? "|before" : "|after");
      }),
      records: observer.takeRecords().map(function (rec) {
        return rec.type === "childList"
          ? "childList " + self.h.ref(rec.target) + " +" + rec.addedNodes.length + " -" + rec.removedNodes.length
          : rec.type + " " + self.h.ref(rec.target);
      })
    };
  };

  // ---- the run ------------------------------------------------------------

  // Once the two engines diverge they pick different operands, so everything
  // after the first divergence is incomparable — one outstanding divergence
  // therefore caps how deep the fuzzer can see. Excluding the operation that
  // causes it lets the hunt continue past it while it is being decided.
  global.runFuzzSeed = function (harness, root, seed, steps, exclude) {
    var fuzzer = new Fuzzer(harness, root, seed);
    var skip = (exclude || "").split(",").filter(Boolean);
    if (skip.length) {
      fuzzer.OPERATIONS = fuzzer.OPERATIONS.filter(function (op) {
        return skip.indexOf(op.name) === -1;
      });
    }

    // Anchor the observers at pseudo-random positions before anything moves, so
    // each seed watches a different part of the tree.
    var pool = fuzzer.nodes();
    var ranges = [];
    for (var i = 0; i < 3; i++) {
      var range = document.createRange();
      var node = pool[fuzzer.int(pool.length)];
      var limit = node.nodeType === 3 ? node.length : node.childNodes.length;
      var start = fuzzer.int(limit + 1);
      range.setStart(node, start);
      range.setEnd(node, start + fuzzer.int(limit - start + 1));
      ranges.push(range);
    }
    var iterators = [];
    for (var j = 0; j < 2; j++) {
      var iterator = document.createNodeIterator(root);
      var advance = fuzzer.int(5);
      for (var k = 0; k < advance; k++) iterator.nextNode();
      iterators.push(iterator);
    }
    var observer = harness.observe(root, { childList: true, subtree: true, characterData: true });

    var log = [];
    try {
    for (var step = 0; step < steps; step++) {
      var operation = fuzzer.OPERATIONS[fuzzer.int(fuzzer.OPERATIONS.length)];
      var entry = { step: step, op: operation.name };
      try {
        var did = operation(fuzzer);
        if (did === null) {
          entry.skipped = true;
        } else {
          entry.did = did;
        }
      } catch (error) {
        entry.threw = error && error.name ? error.name : String(error);
      }
      var state = fuzzer.observe(ranges, iterators, observer);
      entry.tree = state.tree;
      entry.ranges = state.ranges;
      entry.iterators = state.iterators;
      entry.records = state.records;
      log.push(entry);
    }
    } finally {
      // A registered MutationObserver is reachable from the node it observes,
      // in both engines, so it outlives this function unless it is disconnected
      // — and a NodeIterator is consulted by every removal for as long as its
      // document holds it. Seeds run one after another against the same
      // document, so leaving them behind means seed N is measured with the
      // 6 x (N - 1) observers, ranges and iterators every earlier seed left
      // there: quadratic in the seed count, and not the environment the case
      // describes. 96 seeds x 60 steps took 90s before this and 8s after.
      observer.disconnect();
      // detach() is a no-op by definition, but dropping the last reference is
      // what lets each engine reclaim these; a live Range costs work on every
      // mutation until it does.
      for (var d = 0; d < iterators.length; d++) iterators[d].detach();
      iterators.length = 0;
      ranges.length = 0;
    }
    return log;
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
