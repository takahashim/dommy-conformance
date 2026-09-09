#!/usr/bin/env ruby
# frozen_string_literal: true

# The dommy side of the differential harness: run every case through
# dommy-js-quickjs and write one JSON line per case, in the same shape the
# Chromium runner writes.
#
#   ruby runner/dommy.rb [--filter substring] [--out results/dommy.jsonl]
#
# dommy and the engine binding are resolved from sibling checkouts (or
# DOMMY_PATH / DOMMY_JS_QUICKJS_PATH), so this repo pins neither.

require "json"
require "fileutils"
require "pathname"

ROOT = Pathname.new(__dir__).parent

# Prepend a checkout's lib/ if there is one; otherwise fall through to whatever
# is installed, so running against released gems also works.
def use_checkout(env_var, *relative_candidates)
  candidates = [ENV[env_var], *relative_candidates.map { |c| ROOT.join(c).to_s }].compact
  found = candidates.find { |c| File.directory?(File.join(c, "lib")) }
  $LOAD_PATH.unshift(File.join(found, "lib")) if found
  found
end

use_checkout("DOMMY_PATH", "../dommy/gems/dommy", "../dommy")
use_checkout("DOMMY_JS_QUICKJS_PATH", "../dommy-js-quickjs", "../takahashim/dommy-js-quickjs")

require "dommy"
require "dommy/js/quickjs"

module Oracle
  module_function

  def case_ids(filter)
    ids = Dir.glob(ROOT.join("cases/**/*.js")).sort.map do |path|
      Pathname.new(path).relative_path_from(ROOT.join("cases")).to_s
    end
    filter ? ids.select { |id| id.include?(filter) } : ids
  end

  # One case, in two runtimes.
  #
  # The markup a case wants is a property of the case, so it can only be learned
  # by running the case file — but the document has to exist before the window
  # is installed. So a throwaway runtime evaluates the source just far enough to
  # read `html` (harness.js touches no DOM, so registration alone is safe), and
  # a second, pristine runtime does the real run. A used runtime cannot be
  # promoted to the real one: the window install expects an untouched global.
  # The extra runtime costs about 4ms.
  def run_case(id, harness)
    source = harness + "\n" + File.read(ROOT.join("cases", id))
    html = extract_html(source)
    window = Dommy.parse("<!DOCTYPE html><html><head></head><body>#{html}</body></html>")
    runtime = Dommy::Js::Quickjs::Runtime.new
    begin
      runtime.define_host_object("document", window.document)
      runtime.install_window(window)
      runtime.install_browser_globals
      runtime.evaluate("(async () => { #{source}\n; return __oracleRun(); })()")
    ensure
      runtime.dispose
    end
  rescue StandardError, ScriptError => e
    {"error" => "runner: #{e.class}: #{e.message}"}
  end

  def extract_html(source)
    runtime = Dommy::Js::Quickjs::Runtime.new
    runtime.evaluate("(() => { #{source}\n; return __oracleHtml(); })()").to_s
  ensure
    runtime&.dispose
  end

  def flag(argv, name, default = nil)
    index = argv.index(name)
    index ? argv[index + 1] : default
  end

  def main(argv)
    filter = flag(argv, "--filter")
    out = flag(argv, "--out", ROOT.join("results/dommy.jsonl").to_s)

    harness = File.read(ROOT.join("lib/harness.js"))
    lines = case_ids(filter).map do |id|
      record = run_case(id, harness)
      record = {"error" => "runner: case returned #{record.class}"} unless record.is_a?(Hash)
      warn("  #{record["error"] ? "!" : "."} #{id}")
      JSON.generate({"case" => id, "engine" => "dommy"}.merge(record))
    end

    FileUtils.mkdir_p(File.dirname(out))
    File.write(out, lines.join("\n") + (lines.empty? ? "" : "\n"))
    warn("wrote #{out}: #{lines.size} cases")
  end
end

Oracle.main(ARGV) if $PROGRAM_NAME == __FILE__
