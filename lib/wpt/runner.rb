# frozen_string_literal: true

require "json"
require "dommy/browser"
require_relative "result"
require_relative "resources"

module DommyConformance
  module Wpt
    # Runs a vendored WPT test file the way a browser does: the file is loaded
    # as the document and its own `<script>` tags boot through ScriptBoot, with
    # testharness.js / testharnessreport.js / sibling helpers served by
    # Resources. No regex extraction or manual script concatenation — the
    # parsed DOM and the real resource/script pipeline drive everything.
    #
    #   results = Runner.run("css/cssom/CSSStyleSheet.html")  # => [Result, …]
    #
    # Handles the two WPT file shapes:
    #   * `.html`                — markup whose inline `<script>` blocks hold the
    #                              test
    #   * `.any.js`/`.window.js`  — a bare test script (with `// META: script=`
    #     include directives), wrapped in a generated harness page
    class Runner
      WPT_ROOT = Resources::WPT_ROOT
      

      META_SCRIPT = %r{^\s*//\s*META:\s*script=(\S+)}.freeze
      # testharness's harness timeout is 10s; pump past it so a stuck async test
      # is marked TIMEOUT and the rest are still harvested.
      PUMP_ROUNDS = 250
      PUMP_STEP_MS = 100
      # `<meta name=timeout content=long>` raises the harness timeout to 60s, so
      # a file that only completes by timing its stragglers out needs the pump
      # to run past that too — or it is harvested before completion, as 0/0.
      LONG_PUMP_ROUNDS = 700
      LONG_TIMEOUT_META = /<meta\s+name=["']?timeout["']?\s+content=["']?long/i.freeze

      class << self
        def available? = Resources.available?

        # The tests under the vendored tree, relative to WPT_ROOT: one per file,
        # or, for a file that declares variants, one per variant — the path
        # with the variant's query or fragment appended, as WPT names them
        # (`dom/x.html?a=1`). A variant is how the file is meant to be loaded;
        # loading it bare runs it in a configuration none of them is.
        def manifest
          ::Dir.glob("**/*.{any,window}.js", base: WPT_ROOT)
            .concat(::Dir.glob("**/*.{html,htm}", base: WPT_ROOT))
            .reject { |p| p.start_with?("common/", "resources/") || p.include?("/resources/") || p.include?("/support/") || p.end_with?("-ref.html") }
            .flat_map { |p| variants(p).map { |variant| "#{p}#{variant}" } }
            .sort
        end

        VARIANT_META_HTML = /<meta\s+name=["']?variant["']?\s+content=["']([^"']*)["']/i.freeze
        VARIANT_META_JS = %r{^\s*//\s*META:\s*variant=(\S*)}.freeze

        # A file's variants (`?query` / `#fragment`, "" for the bare file);
        # [""] when it declares none.
        def variants(rel_path)
          source = ::File.read(::File.join(WPT_ROOT, rel_path), encoding: "UTF-8").scrub
          found = source.scan(rel_path.end_with?(".js") ? VARIANT_META_JS : VARIANT_META_HTML).flatten
          found.empty? ? [""] : found.uniq
        end

        # `rel_path` is a test id: a file, with its variant if it has one.
        def run(rel_path)
          rel_path, variant = split_variant(rel_path)
          path = absolute(rel_path)
          html, encoding = page_for(path, rel_path)
          url = "http://localhost/#{rel_path.delete_prefix('/')}#{variant}"
          resources = Resources.build

          # Boot with execute_scripts: false so the window `load` event has NOT
          # fired yet — script boot replays "complete -> load", and tests that
          # read `iframe.contentDocument` inside a `load` handler need static
          # `<iframe src>` frames navigated BEFORE that. We wire them, then drive
          # script boot ourselves (which fires load with the frames in place).
          browser = ::Dommy::Browser.new(
            html, url: url, resources: resources,
            execute_scripts: false, strict: false, settle: false,
            wasm_memory_shim: true, navigable: true, encoding: encoding
          )
          browser.runtime.define_host_object("__dommyTestDriver", TestDriver.new(browser.window.document))
          boot_scripts(browser, url, resources)
          rounds = html.match?(LONG_TIMEOUT_META) ? LONG_PUMP_ROUNDS : PUMP_ROUNDS
          harvest(browser, url, resources, rounds)
        ensure
          browser&.dispose
        end

        # Replicate Dommy::Browser's script-boot step. Static `<iframe src>`
        # frames are populated with their content document BEFORE the document's
        # scripts run — so a script (or the window load event that boot fires)
        # that reads `contentDocument` finds it — but each frame's own `load`
        # event fires AFTER the scripts, which is when a browser fires it. An
        # `onload="testIframe(this)"` handler calls a function the document's own
        # script defines; dispatching the frame's load before that script ran
        # left the async_test it starts uncompleted ("Removed iframe").
        def boot_scripts(browser, base_url, resources)
          frames = populate_iframes(browser, base_url, resources)
          doc = browser.window.document
          doc.external_script_runner = lambda do |element, src|
            ::Dommy::Js::ScriptBoot.run_external_script(browser.runtime, doc, element, src, resources: resources)
          end
          ::Dommy::Js::ScriptBoot.run_document_scripts(browser.runtime, doc, resources: resources)
          frames.each { |iframe| dispatch_iframe_load(iframe) }
          browser.settle
        end

        private

        # "dir/x.html?a=1" -> ["dir/x.html", "?a=1"]; a plain path has "".
        def split_variant(test_id)
          index = test_id.index(/[?#]/)
          index ? [test_id[0...index], test_id[index..]] : [test_id, ""]
        end

        def absolute(rel_path)
          return rel_path if ::File.absolute_path?(rel_path) && ::File.exist?(rel_path)

          ::File.join(WPT_ROOT, rel_path)
        end

        # The document to load: an `.html` test is its own page; a `.js` test is
        # wrapped in a generated harness page that pulls in testharness, the
        # report shim, its META includes, and the test body — all as `<script>`
        # tags ScriptBoot runs in order.
        # wptserve `.sub.` template substitutions, mapped onto the single-host
        # harness: the document's own host and default ports stay same-origin,
        # while the "second" ports and alternate hosts become distinct (cross-
        # origin) URLs the path-based resource layer still serves. Enough for the
        # CORS `.sub` tests that hard-code `http://{{host}}:{{ports[http][1]}}/…`.
        WPT_SUBS = {
          # The document's own origin is http://localhost (port 80, which a URL
          # serializes without), so "host:port" written out is just the host;
          # `localhost:80` would match no URL the page produces.
          "{{host}}:{{ports[http][0]}}" => "localhost",
          "{{domains[]}}:{{ports[http][0]}}" => "localhost",
          "{{host}}" => "localhost",
          "{{ports[http][0]}}" => "80", "{{ports[http][1]}}" => "8001",
          "{{ports[https][0]}}" => "443", "{{ports[https][1]}}" => "8444",
          "{{ports[ws][0]}}" => "80", "{{ports[wss][0]}}" => "443",
          "{{domains[]}}" => "localhost", "{{domains[www2]}}" => "www2.localhost",
          "{{hosts[alt][]}}" => "not-localhost.test",
          "{{hosts[alt][www2]}}" => "www2.not-localhost.test",
        }.freeze

        # The page to load and the encoding its document has. An HTML file is
        # decoded from its bytes as a browser decodes a response with no
        # charset — a BOM (dropped), else its <meta charset>, else UTF-8; the
        # page wrapped around a .js test is UTF-8.
        def page_for(path, rel_path)
          if rel_path.end_with?(".html", ".htm")
            source, encoding = ::Dommy::Encodings.decode_document(::File.binread(path), "text/html")
            source = WPT_SUBS.reduce(source) { |s, (k, v)| s.gsub(k, v) } if rel_path.include?(".sub.")
            return [source, encoding]
          end

          source = ::File.read(path).delete_prefix("\ufeff")
          source = WPT_SUBS.reduce(source) { |s, (k, v)| s.gsub(k, v) } if rel_path.include?(".sub.")

          includes = source.scan(META_SCRIPT).flatten
            .map { |spec| %(<script src="#{resolve_include(spec, rel_path)}"></script>) }
          # wptserve turns `// META: timeout=long` into this meta on the page it
          # generates; testharness reads its timeout from there.
          long = source.match?(%r{^\s*//\s*META:\s*timeout=long}) ? %(<meta name="timeout" content="long">) : ""
          # wptserve's window wrapper for a `.any.js` also defines GLOBAL, the
          # scope probe `GLOBAL.isWindow()` & co. that shared tests branch on.
          page = <<~HTML
            <!DOCTYPE html><html><head>#{long}
            <script>self.GLOBAL = { isWindow() { return true; }, isWorker() { return false; }, isShadowRealm() { return false; } };</script>
            <script src="/resources/testharness.js"></script>
            <script src="/resources/testharnessreport.js"></script>
            #{includes.join("\n")}
            <script>#{source}</script>
            </head><body></body></html>
          HTML
          [page, "UTF-8"]
        end

        # A META `script=` spec is "/"-rooted at the WPT tree or relative to the
        # test file; either way return a URL path the resource layer resolves
        # (file_system serves the vendored tree by path).
        def resolve_include(spec, rel_path)
          spec = spec.sub(/\?.*\z/, "")
          return spec if spec.start_with?("/")

          dir = ::File.dirname("/#{rel_path.delete_prefix('/')}")
          ::File.expand_path(spec, dir)
        end

        # Script boot has already fired the load event; drain microtasks/timers
        # until the completion callback stashes results or the pump budget is
        # spent. `base_url` resolves `<iframe src>` against the vendored tree.
        def harvest(browser, base_url, resources, rounds = PUMP_ROUNDS)
          wire_iframes(browser, base_url, resources)
          if browser.evaluate("globalThis.__wptResults === null")
            rounds.times do
              browser.advance_time(PUMP_STEP_MS)
              # Tests that build their subtests inside an `<iframe>` create the
              # frame dynamically (frame.src = "...content.html"), so re-wire
              # each round until its onload fires and the body runs.
              wire_iframes(browser, base_url, resources)
              break unless browser.evaluate("globalThis.__wptResults === null")
            end
          end

          # Harvest as a JSON string, not by dehydrating the JS array directly:
          # the bridge sometimes hands back opaque host objects rather than
          # Hashes, and WPT names/messages can carry control characters that
          # JSON escapes safely.
          json = browser.evaluate("JSON.stringify(globalThis.__wptResults)")
          return [] unless json.is_a?(::String) && !json.empty?

          parsed = ::JSON.parse(json)
          # A never-completing test (e.g. one gated on an iframe that never
          # loaded) leaves `__wptResults` as JS null → parses to Ruby nil. Don't
          # let that crash the whole file's harvest; report nothing instead.
          return [] unless parsed.is_a?(::Array)

          parsed.map { |r| Result.new(r["name"], r["status"], r["message"]) }
        end

        # Populate a frame and fire its `load` — for frames created DURING the
        # harvest (frame.src = "..." in a test body), whose onload handler is
        # already installed before the src is set.
        def wire_iframes(browser, base_url, resources)
          populate_iframes(browser, base_url, resources).each { |iframe| dispatch_iframe_load(iframe) }
        end

        # Populate any `<iframe src=...>` whose src resolves against the vendored
        # tree with a parsed content document, and return the frames that were
        # newly populated (their `load` is the caller's to fire) — the browser
        # doesn't navigate iframes itself, but WPT tests routinely run their body
        # inside a framed document (Selectors-API suites, the createElementNS
        # XML/XHTML-document cases via /common/dummy.{xml,xhtml}). Idempotent: an
        # already-populated frame is skipped, so it is safe to call every pump
        # round for dynamically created frames.
        def populate_iframes(browser, base_url, resources)
          populated = []
          browser.window.document.query_selector_all("iframe").each do |iframe|
            next if iframe.content_document

            src = iframe.get_attribute("src").to_s
            src = "" if src == "about:blank"
            srcdoc = iframe.get_attribute("srcdoc")
            sub =
              if !src.empty?
                # The element's own resolution, which encodes the query in the
                # document's encoding as HTML's "encoding-parse" does.
                resolved = iframe.respond_to?(:src) && !iframe.src.to_s.empty? ? iframe.src.to_s : resolve_url(base_url, src)
                response = resources.get(resolved.sub(/#.*\z/, ""))
                next unless response&.success? && response.body

                parse_framed_document(response, resolved)
              else
                # A srcless (blank/about:blank) or `srcdoc` iframe gets its own
                # empty/srcdoc document, so `contentWindow` resolves and its
                # cross-realm globals (contentWindow.AbortSignal / DOMException /
                # Comment) are available — used by dom/abort + constructor tests.
                ::Dommy.parse(srcdoc.to_s.empty? ? "<!DOCTYPE html><html><head></head><body></body></html>" : srcdoc.to_s)
              end
            next unless sub

            iframe.__internal_set_content_document__(sub.document)
            # A navigation from inside the frame (a form submit, a link) loads
            # into the frame itself.
            if sub.respond_to?(:navigation_delegate=) && browser.respond_to?(:frame_navigation_delegate)
              sub.navigation_delegate = browser.frame_navigation_delegate(iframe)
            end
            # Exposing the seeded constructors on a nested realm is an
            # engine-binding affordance, not part of the runtime contract, so
            # a binding that lacks it simply runs without cross-realm
            # `instanceof` rather than failing the whole file.
            browser.runtime.expose_constructors_on(sub) if browser.runtime.respond_to?(:expose_constructors_on)
            populated << iframe
          end
          populated
        rescue StandardError
          # Wiring is best-effort; a malformed frame must not abort the harvest.
          populated
        end

        def dispatch_iframe_load(iframe)
          iframe.dispatch_event(::Dommy::Event.new("load"))
        rescue StandardError
          # A handler that throws must not take the harvest with it.
          nil
        end

        # Parse framed markup according to the resource extension: XML/XHTML get
        # the XML parser (case-preserving, real namespaces) so createElement /
        # namespaceURI match the spec; everything else parses as HTML.
        def parse_framed_document(response, resolved)
          body = response.body
          path = resolved.sub(/[#?].*\z/, "")
          win =
            if path.end_with?(".xml", ".xhtml")
              w = ::Dommy::Window.new(nil, backend_doc: ::Dommy::Backend.parse_xml(body))
              w.document.content_type = path.end_with?(".xhtml") ? "application/xhtml+xml" : "text/xml"
              w
            else
              # Decoded as a browser decodes the response: its charset, a BOM,
              # its <meta charset>, else UTF-8.
              text, encoding = ::Dommy::Encodings.decode_document(body.to_s.b, content_type_of(response) || "text/html")
              ::Dommy.parse(text, encoding: encoding)
            end
          # Carry the URL (incl. fragment) onto the framed window so `:target` /
          # location.hash resolve in the framed document.
          win.location.__internal_set_url__(resolved) if resolved.include?("#")
          win
        rescue StandardError
          nil
        end

        def content_type_of(response)
          headers = response.respond_to?(:headers) ? response.headers || {} : {}
          key = headers.keys.find { |k| k.to_s.casecmp?("content-type") }
          key && headers[key]
        end

        # Resolve a possibly-relative iframe src against the test's URL.
        def resolve_url(base_url, src)
          ::URI.join(base_url, src).to_s
        rescue ::URI::Error
          src
        end
      end
    end
  end
end
