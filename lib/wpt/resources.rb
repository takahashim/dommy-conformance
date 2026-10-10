# frozen_string_literal: true

require_relative "endpoints"
require_relative "test_driver"
module DommyConformance
  module Wpt
    # The resource layer a real WPT test page resolves its `<script src>`
    # against — so the harness boots the document's own scripts through the
    # normal browser path (ScriptBoot) instead of regex-extracting them:
    #
    #   * `/resources/testharness.js`        -> the vendored harness
    #   * `/resources/testharnessreport.js`  -> REPORT_SHIM (harvests results)
    #   * everything else                    -> the vendored WPT tree on disk,
    #                                            by URL path (so `support/x.js`
    #                                            and `/common/y.js` resolve)
    #
    # A request for a file not on disk returns nil, so a missing optional
    # include is simply skipped (the test still runs).
    module Resources
      TESTHARNESS = ::File.expand_path("../../wpt/testharness.js", __dir__)
      WPT_ROOT    = ::File.expand_path("../../wpt/corpus", __dir__)

      # testharnessreport.js stand-in: a browser loads testharness.js then this,
      # before the test's own scripts. It silences the visual output (we harvest
      # programmatically), mirrors id'd elements onto the global for WPT's
      # "named access on the Window" (`<div id=log>` -> bare `log`), and stashes
      # each subtest's result for the Ruby side to read after completion.
      #
      # Each mirrored id is looked up when read, not copied: an element moved
      # into a shadow tree or removed is no longer the global's, and a copy
      # would also shadow `window.<id>` (the window falls back to globalThis's
      # own properties). An assignment replaces the accessor, as on a window.
      REPORT_SHIM = <<~JS
        setup({ output: false });
        globalThis.__wptResults = null;
        for (const __el of document.querySelectorAll("[id]")) {
          const __id = __el.id;
          if (__id && !(__id in globalThis)) {
            try {
              Object.defineProperty(globalThis, __id, {
                get() { return document.getElementById(__id) ?? undefined; },
                set(value) {
                  Object.defineProperty(globalThis, __id, { value, configurable: true, writable: true });
                },
                configurable: true,
              });
            } catch (__e) {}
          }
        }
        add_completion_callback((tests) => {
          globalThis.__wptResults = tests.map((t) => ({ name: t.name, status: t.status, message: t.message }));
        });
      JS

      # testdriver.js stand-in. The real file proxies to a WebDriver automation
      # backend; we only need the synchronous-ish queries WPT's accessibility
      # tests use, backed by Dommy's computed role/label on the element proxy.
      # testdriver-vendor.js / testdriver-actions.js exist only so their
      # `<script src>` resolves; they need no behavior here.
      #
      # click / send_keys / bless / Actions are performed as trusted user input
      # by Dommy's Interaction layer, through the `__dommyTestDriver` host
      # object the runner installs (TestDriver).
      TESTDRIVER_SHIM = <<~'JS'
        globalThis.test_driver = globalThis.test_driver || {};
        test_driver.get_computed_role = (el) => Promise.resolve(el.__internal_computed_role__());
        test_driver.get_computed_label = (el) => Promise.resolve(el.__internal_computed_label__());
        (() => {
          const host = () => globalThis.__dommyTestDriver;
          // Like a WebDriver round trip, the input arrives after the caller's
          // synchronous code — deferred to a microtask, not a task: the engine
          // evaluates a module's top-level await by draining microtasks only.
          const run = (f) => Promise.resolve().then(() => { f(); });
          // Plain functions, as testdriver.js has them: some tests call them
          // with `new`.
          test_driver.click = function (el) { return run(() => host().click(el)); };
          test_driver.send_keys = function (el, keys) { return run(() => host().sendKeys(el, String(keys))); };
          test_driver.bless = function (intent, action, win) {
            win = win || window;
            const button = win.document.createElement("button");
            button.textContent = intent || "Bless";
            win.document.body.appendChild(button);
            let result;
            button.addEventListener("click", () => { if (action) result = action(); }, { once: true });
            return test_driver.click(button).then(() => { button.remove(); return result; });
          };
          class Actions {
            constructor(defaultTickDuration = 16) {
              this.sources = []; this.current = {}; this.elements = [];
              this.ButtonType = { LEFT: 0, MIDDLE: 1, RIGHT: 2, BACK: 3, FORWARD: 4 };
            }
            _source(type, name, params) {
              name = name || (type === "key" ? "keyboard" : type === "pointer" ? "mouse" : type);
              let s = this.sources.find(x => x.type === type && x.id === name);
              if (!s) { s = { type, id: name, parameters: params, actions: [] }; this.sources.push(s); }
              this.current[type] = s;
              return s;
            }
            _cur(type) { return this.current[type] || this._source(type); }
            _push(type, action, sourceName) {
              const s = sourceName ? this._source(type, sourceName) : this._cur(type);
              const tick = Math.max(0, ...this.sources.map(x => x.actions.length));
              while (s.actions.length < tick) s.actions.push({ type: "pause" });
              s.actions.push(action);
              return this;
            }
            addPointer(name, pointerType = "mouse", setAsDefault = true) { this._source("pointer", name, { pointerType }); return this; }
            addKeyboard(name, setAsDefault = true) { this._source("key", name); return this; }
            setPointer(name) { this.current.pointer = this._source("pointer", name); return this; }
            setKeyboard(name) { this.current.key = this._source("key", name); return this; }
            keyDown(key, sourceName) { return this._push("key", { type: "keyDown", value: key }, sourceName); }
            keyUp(key, sourceName) { return this._push("key", { type: "keyUp", value: key }, sourceName); }
            pointerDown({ button = 0, sourceName } = {}) { return this._push("pointer", { type: "pointerDown", button }, sourceName); }
            pointerUp({ button = 0, sourceName } = {}) { return this._push("pointer", { type: "pointerUp", button }, sourceName); }
            pointerMove(x, y, { origin = "viewport", duration, sourceName } = {}) {
              let o = origin;
              if (origin && typeof origin === "object") { this.elements.push(origin); o = this.elements.length - 1; }
              return this._push("pointer", { type: "pointerMove", x, y, origin: o }, sourceName);
            }
            scroll() { return this; }
            pause(duration = 0, type = "none", { sourceName } = {}) { return this; }
            send() { return run(() => host().actions(JSON.stringify(this.sources), this.elements)); }
          }
          test_driver.Actions = Actions;
          test_driver.action_sequence = (sources) => run(() => host().actions(JSON.stringify(sources), []));
        })();
      JS

      module_function

      def available? = ::File.exist?(TESTHARNESS) && ::File.directory?(WPT_ROOT)

      # A Resources adapter for a test loaded at `base_path` (a "/"-rooted path
      # like "/css/cssom/CSSStyleSheet.html"), so its relative includes resolve
      # against the right WPT directory.
      def build
        Pipe.new(chain_adapters)
      end

      def chain_adapters
        ::Dommy::Resources.chain(
          ::Dommy::Resources.static(
            "/resources/testharness.js" => ::File.read(TESTHARNESS),
            "/resources/testharnessreport.js" => REPORT_SHIM,
            "/resources/testdriver.js" => TESTDRIVER_SHIM,
            "/resources/testdriver-vendor.js" => "",
            "/resources/testdriver-actions.js" => ""
          ),
          # Dynamic WPT server endpoints (resources/*.py) that fetch/xhr tests hit,
          # ahead of the static tree so an endpoint wins over any same-named file.
          Endpoints.new,
          ::Dommy::Resources.file_system(root: WPT_ROOT, base_url: "/")
        )
      end
    end
  end
end
