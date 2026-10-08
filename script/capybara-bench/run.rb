# frozen_string_literal: true

# Run the scenarios under every driver and print the comparison as Markdown.
# `rake bench` calls this; see README.md.
#
#   ruby script/capybara-bench/run.rb [--drivers rack_test,dommy] [--rounds N] [--filter S]
#
# Each driver runs in its own process, under this directory's own bundle.
# Writes results/capybara-bench.{json,md}.

require "json"
require "open3"
require "fileutils"

HERE = __dir__
ROOT = File.expand_path("../..", HERE)
DRIVERS = %w[rack_test dommy dommy_js cuprite cuprite_tuned].freeze

argv = ARGV.dup
opt = ->(name, default) { (i = argv.index(name)) ? argv[i + 1] : default }
drivers = opt.("--drivers", DRIVERS.join(",")).split(",")
passthrough = %w[--rounds --filter].flat_map { |flag| (v = opt.(flag, nil)) ? [flag, v] : [] }
abort "the Hotwire bundles are not installed: (cd #{HERE} && npm install)" unless File.directory?(File.join(HERE, "node_modules/@hotwired"))

env = {"BUNDLE_GEMFILE" => File.join(HERE, "Gemfile")}
results = drivers.to_h do |driver|
  warn "  #{driver}"
  out, err, status = Bundler.with_unbundled_env do
    Open3.capture3(env, "bundle", "exec", RbConfig.ruby, File.join(HERE, "bench.rb"), driver, *passthrough, chdir: HERE)
  end
  abort "#{driver} failed:\n#{err}" unless status.success?
  [driver, JSON.parse(out.lines.last)]
end

def fmt_ms(ms) = ms >= 100 ? format("%.0f", ms) : format("%.1f", ms)

def cell(result)
  return "—" if result.nil? || result["skipped"]
  return "error" if result["error"]

  fmt_ms(result["ms"])
end

names = results.values.flat_map { _1["scenarios"].keys }.uniq
lines = []
lines << "| scenario | #{drivers.join(" | ")} |"
lines << "|---|#{"---:|" * drivers.size}"
names.each do |name|
  lines << "| #{name} | #{drivers.map { cell(results[_1]["scenarios"][name]) }.join(" | ")} |"
end
totals = drivers.map do |d|
  fmt_ms(results[d]["scenarios"].values.sum { |r| r["ms"] ? r["ms"] + r["reset_ms"] : 0 })
end
lines << "| **all it ran, incl. resets** | #{totals.join(" | ")} |"
lines << "| startup (first visit) | #{drivers.map { fmt_ms(results[_1]["startup_ms"]) }.join(" | ")} |"
lines << "| peak memory, MB (incl. child processes) | #{drivers.map { format("%.0f", results[_1]["peak_mb"]) }.join(" | ")} |"
lines << ""
lines << "Median ms per scenario (lower is better); —: the driver runs no JavaScript."
if drivers.include?("cuprite_tuned")
  lines << "cuprite_tuned: cuprite with FERRUM_INTERMITTENT_SLEEP=0.01 (Ferrum's stale-node retry, 0.1s by default)."
end
errors = results.flat_map { |d, r| r["scenarios"].filter_map { |n, s| "- #{d} / #{n}: #{s["error"]}" if s["error"] } }
lines.concat(["", "Errors:", *errors]) unless errors.empty?
any = results.values.first
lines << ""
lines << "Ruby #{any["ruby"]}; " + any["versions"].map { "#{_1} #{_2}" }.join(", ") +
         ((browser = results.values.filter_map { _1["browser"] }.first) ? "; #{browser} (headless)" : "")
report = lines.join("\n")

FileUtils.mkdir_p(File.join(ROOT, "results"))
File.write(File.join(ROOT, "results/capybara-bench.json"), JSON.pretty_generate(results))
File.write(File.join(ROOT, "results/capybara-bench.md"), report + "\n")
puts report
