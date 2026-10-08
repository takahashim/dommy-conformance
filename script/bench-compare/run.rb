# frozen_string_literal: true

# Run every case under Dommy, jsdom, happy-dom and linkedom, and print the
# comparison as Markdown. `rake bench` calls this; see README.md.
#
#   ruby script/bench-compare/run.rb [--engines dommy,jsdom] [--samples N] [--filter S]
#
# Each engine's timing and its memory each run in a fresh process, so no
# engine's heap or JIT state leaks into another's numbers. Writes
# results/bench-compare.{json,md}.

require "json"
require "open3"
require "fileutils"

HERE = __dir__
ROOT = File.expand_path("../..", HERE)
NODE_ENGINES = %w[jsdom happydom linkedom].freeze
ENGINES_ALL = ["dommy", *NODE_ENGINES].freeze

argv = ARGV.dup
opt = ->(name, default) { (i = argv.index(name)) ? argv[i + 1] : default }
engines = opt.("--engines", ENGINES_ALL.join(",")).split(",")
passthrough = %w[--samples --filter].flat_map { |flag| (v = opt.(flag, nil)) ? [flag, v] : [] }

unless (engines & NODE_ENGINES).empty? || File.directory?(File.join(HERE, "node_modules"))
  abort "jsdom / happy-dom / linkedom are not installed: (cd #{HERE} && npm install)"
end

def command(engine, *args)
  if engine == "dommy"
    [RbConfig.ruby, File.join(HERE, "bench_dommy.rb"), *args]
  else
    ["node", "--expose-gc", File.join(HERE, "bench.mjs"), engine, *args]
  end
end

def run_json(cmd)
  out, err, status = Open3.capture3(*cmd)
  abort "#{cmd.join(" ")} failed:\n#{err}" unless status.success?
  JSON.parse(out.lines.last)
end

results = engines.to_h do |engine|
  warn "  #{engine}: cases"
  timed = run_json(command(engine, *passthrough))
  warn "  #{engine}: window cost"
  sized = run_json(command(engine, "--memory", *passthrough.each_slice(2).select { _1[0] == "--samples" }.flatten))
  [engine, timed.merge("window" => sized["window"])]
end

def fmt_ms(ms) = ms >= 100 ? format("%.0f", ms) : format("%.1f", ms)
def fmt_mb(mb) = format("%.1f", mb)

def ratio(a, b)
  return "" unless a && b && b.positive?

  r = a / b
  r >= 1 ? format("%.1f×", r) : format("1/%.1f", 1 / r)
end

case_names = results.values.flat_map { _1["cases"].keys }.uniq.sort
lines = []
lines << "| case | #{engines.join(" | ")} |#{" dommy ÷ jsdom |" if engines.include?("dommy") && engines.include?("jsdom")}"
lines << "|---|#{"---:|" * engines.size}#{"---:|" if engines.include?("dommy") && engines.include?("jsdom")}"
case_names.each do |name|
  checksums = results.values.filter_map { _1["cases"].dig(name, "checksum") }.uniq
  cells = engines.map do |engine|
    r = results[engine]["cases"][name]
    next "n/a" if r.nil? || r["error"]

    mismatch = checksums.size > 1 && r["checksum"] != results.dig("dommy", "cases", name, "checksum") ? " ≠" : ""
    fmt_ms(r["ms"]) + mismatch
  end
  extra = (" #{ratio(results.dig("dommy", "cases", name, "ms"), results.dig("jsdom", "cases", name, "ms"))} |" if engines.include?("dommy") && engines.include?("jsdom"))
  lines << "| #{name} | #{cells.join(" | ")} |#{extra}"
end
lines << ""
lines << "Median ms per run (lower is better). n/a: the library lacks an API the case uses; " \
         "≠: its result differs from Dommy's, so it did not do the same work."
lines << ""
lines << "| window | #{engines.join(" | ")} |"
lines << "|---|#{"---:|" * engines.size}"
{
  "open a window (ms)" => ["boot_ms", :fmt_ms],
  "memory per empty window (MB)" => ["empty_mb", :fmt_mb],
  "memory per window holding ~18k nodes (MB)" => ["table_mb", :fmt_mb],
}.each do |label, (key, f)|
  lines << "| #{label} | #{engines.map { send(f, results[_1]["window"][key]) }.join(" | ")} |"
end
lines << ""
lines << engines.map { "- **#{_1}**: #{results[_1]["version"]} (#{results[_1]["runtime"]})" }.join("\n")
report = lines.join("\n")

FileUtils.mkdir_p(File.join(ROOT, "results"))
File.write(File.join(ROOT, "results/bench-compare.json"), JSON.pretty_generate(results))
File.write(File.join(ROOT, "results/bench-compare.md"), report + "\n")
puts report
