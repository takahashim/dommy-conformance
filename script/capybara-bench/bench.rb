# frozen_string_literal: true

# One driver's side of capybara-bench: run every scenario it supports and print
# one JSON object. run.rb starts one of these per driver; see README.md.
#
#   bundle exec ruby bench.rb <rack_test|dommy|dommy_js|cuprite|cuprite_tuned> [--rounds N] [--filter S]

DRIVER = ARGV.fetch(0).to_sym

# cuprite_tuned is cuprite with Ferrum's stale-node retry shortened. When a node
# it holds is gone, as when Turbo swaps its cached preview for the fresh page,
# Ferrum treats that as intermittent and retries: up to 6 times, 0.1s apart, by
# default. The constants are read when Ferrum loads, so they must be set before
# the require below. Plain cuprite keeps the defaults whatever the caller's
# environment says.
if DRIVER == :cuprite_tuned
  ENV["FERRUM_INTERMITTENT_SLEEP"] = "0.01"
elsif DRIVER == :cuprite
  ENV.delete("FERRUM_INTERMITTENT_SLEEP")
  ENV.delete("FERRUM_INTERMITTENT_ATTEMPTS")
end

require "json"
require "capybara"
require "capybara/dommy"
require "capybara/cuprite"
require_relative "app"
require_relative "scenarios"

if DRIVER.to_s.start_with?("cuprite")
  sleep_s = Ferrum::Frame::Runtime::INTERMITTENT_SLEEP
  abort "Ferrum's retry sleep is #{sleep_s}, not what #{DRIVER} needs" unless sleep_s == (DRIVER == :cuprite_tuned ? 0.01 : 0.1)
end

argv = ARGV.drop(1)
opt = ->(name, default) { (i = argv.index(name)) ? argv[i + 1] : default }
ROUNDS = Integer(opt.("--rounds", 5))
FILTER = opt.("--filter", "")
JS_DRIVERS = %i[dommy_js cuprite cuprite_tuned].freeze

Capybara.register_driver(:dommy) { |app| Capybara::Dommy::Driver.new(app) }
Capybara.register_driver(:dommy_js) { |app| Capybara::Dommy::Driver.new(app, javascript: true) }
%i[cuprite cuprite_tuned].each do |name|
  Capybara.register_driver(name) do |app|
    Capybara::Cuprite::Driver.new(app, browser_path: ENV.fetch("BROWSER_PATH", "/opt/pw-browsers/chromium"),
                                       headless: true, js_errors: true, process_timeout: 30,
                                       browser_options: {"no-sandbox" => nil})
  end
end
Capybara.server = :puma, {Silent: true}
Capybara.default_max_wait_time = 5

def now = Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000
def median(xs) = xs.sort[xs.size / 2]

# Peak resident memory of this process and everything it started (Chrome's
# processes, for cuprite), sampled every 50ms: a browser driver's cost is
# mostly outside the Ruby process, so the Ruby process alone would hide it.
class PeakMemory
  attr_reader :peak_mb

  def initialize
    @peak_mb = 0.0
    @thread = Thread.new { loop { sample; sleep 0.05 } }
  end

  def stop
    @thread.kill
    sample
  end

  private

  def sample
    tree = descendants(Process.pid)
    mb = tree.sum { |pid| rss_kb(pid) } / 1024.0
    @peak_mb = mb if mb > @peak_mb
  end

  def descendants(root)
    children = Hash.new { |h, k| h[k] = [] }
    Dir.glob("/proc/[0-9]*/stat").each do |stat|
      fields = File.read(stat).sub(/\A.*\) /, "").split
      children[Integer(fields[1])] << Integer(stat[%r{/proc/(\d+)/}, 1])
    rescue SystemCallError, ArgumentError
      next
    end
    queue = [root]
    queue.each { |pid| queue.concat(children[pid]) }
    queue
  end

  def rss_kb(pid)
    File.read("/proc/#{pid}/status")[/VmRSS:\s+(\d+)/, 1].to_i
  rescue SystemCallError
    0
  end
end

memory = PeakMemory.new
t0 = now
session = Capybara::Session.new(DRIVER, BenchApp)
session.visit "/"
session.assert_selector "h1", text: "Items"
startup_ms = now - t0

results = {}
BenchScenarios::ALL.each do |scenario|
  next unless scenario.name.include?(FILTER)
  next results[scenario.name] = {"skipped" => "driver runs no JavaScript"} if scenario.js && !JS_DRIVERS.include?(DRIVER)

  times = []
  resets = []
  begin
    (0..ROUNDS).each do |round| # round 0 is the warm-up
      t = now
      scenario.body.call(session)
      times << (now - t) if round.positive?
      t = now
      session.reset!
      resets << (now - t) if round.positive?
    end
    results[scenario.name] = {"ms" => median(times), "min" => times.min, "reset_ms" => median(resets)}
  rescue StandardError => e
    results[scenario.name] = {"error" => "#{e.class}: #{e.message.lines.first.to_s.strip[0, 100]}"}
    session.reset! rescue nil
  end
end
memory.stop

versions = %w[capybara capybara-dommy dommy dommy-js-quickjs cuprite ferrum puma].to_h do |name|
  [name, Gem.loaded_specs[name]&.version&.to_s]
end
browser = (session.driver.browser.version.product rescue nil) if DRIVER.to_s.start_with?("cuprite")
puts JSON.generate("driver" => DRIVER, "startup_ms" => startup_ms, "peak_mb" => memory.peak_mb,
                   "scenarios" => results, "versions" => versions.compact, "browser" => browser,
                   "ruby" => RUBY_VERSION)
