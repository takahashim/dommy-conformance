# frozen_string_literal: true

# The Dommy side of bench-compare: the same cases as bench.mjs, run through
# dommy-js-quickjs, printed as the same JSON object. See README.md.
#
#   bundle exec ruby script/bench-compare/bench_dommy.rb [--samples N] [--filter S]
#   bundle exec ruby script/bench-compare/bench_dommy.rb --memory   (in a fresh process)
#
# dommy and the binding come from the same place the rest of the repo takes
# them (the Gemfile: DOMMY_PATH / DOMMY_JS_QUICKJS_PATH or sibling checkouts).

require "json"
require "dommy"
require "dommy/js/quickjs"

HERE = __dir__
BASE = "<!DOCTYPE html><html><head></head><body></body></html>"
argv = ARGV.dup
opt = ->(name, default) { (i = argv.index(name)) ? argv[i + 1] : default }
SAMPLES = Integer(opt.("--samples", 7))
FILTER = opt.("--filter", "")
MEMORY = argv.include?("--memory")
MEMORY_WINDOWS = Integer(opt.("--memory-windows", 20))

# A window the way a JS-enabled Dommy page gets one (runner/dommy.rb does the
# same): a parsed document, a QuickJS runtime, the window and browser globals.
Context = Struct.new(:window, :runtime) do
  def self.open
    window = Dommy.parse(BASE)
    runtime = Dommy::Js::Quickjs::Runtime.new
    runtime.define_host_object("document", window.document)
    runtime.install_window(window)
    runtime.install_browser_globals
    new(window, runtime)
  end

  def close = runtime.dispose
end

def now = Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000
def median(xs) = xs.sort[xs.size / 2]
def rss_mb = File.read("/proc/self/status")[/VmRSS:\s+(\d+)/, 1].to_i / 1024.0

# The case's object is defined once per window, then setup runs untimed and
# run is timed from Ruby around a single evaluate — the same boundary the Node
# side times around a direct call (one evaluate costs tens of microseconds).
def run_case(file)
  source = File.read(file)
  times = []
  checksum = nil
  (0..SAMPLES).each do |i| # sample 0 is the warm-up
    ctx = Context.open
    begin
      ctx.runtime.execute("globalThis.__case = (#{source}\n);")
      ctx.runtime.execute("__case.setup(window, document)")
      t0 = now
      value = ctx.runtime.evaluate("__case.run(window, document)")
      dt = now - t0
      times << dt if i.positive?
      checksum = value
    rescue StandardError => e
      return {"error" => e.message.lines.first.to_s.strip[0, 80]}
    ensure
      ctx.close
    end
  end
  checksum = checksum.to_i if checksum.is_a?(Float) && checksum == checksum.floor
  {"ms" => median(times), "min" => times.min, "checksum" => checksum}
end

def window_cost
  table = File.read(File.join(HERE, "cases/02-parse-innerhtml.js"))
  per_window = lambda do |fill|
    GC.start
    before = rss_mb
    kept = Array.new(MEMORY_WINDOWS) do
      ctx = Context.open
      if fill
        ctx.runtime.execute("globalThis.__case = (#{table}\n); __case.setup(window, document); " \
                            "__case.run(window, document); delete window.__markup; delete globalThis.__case;")
      end
      ctx
    end
    GC.start
    mb = (rss_mb - before) / MEMORY_WINDOWS
    kept.each(&:close)
    mb
  end
  baseline = rss_mb
  empty = per_window.(false)
  filled = per_window.(true)
  boot = Array.new(SAMPLES) do
    t0 = now
    ctx = Context.open
    dt = now - t0
    ctx.close
    dt
  end
  {"boot_ms" => median(boot), "baseline_mb" => baseline, "empty_mb" => empty, "table_mb" => filled}
end

quickjs = Gem.loaded_specs["dommy-js-quickjs"]
result = {
  "engine" => "dommy",
  "version" => "#{Dommy::VERSION} / dommy-js-quickjs #{quickjs&.version || "?"}",
  "runtime" => "ruby #{RUBY_VERSION} + QuickJS",
}
if MEMORY
  result["window"] = window_cost
else
  result["cases"] = Dir[File.join(HERE, "cases/*.js")].sort.filter_map do |file|
    name = File.basename(file, ".js")
    [name, run_case(file)] if name.include?(FILTER)
  end.to_h
end
puts JSON.generate(result)
