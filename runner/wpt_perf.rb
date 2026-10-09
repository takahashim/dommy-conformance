#!/usr/bin/env ruby
# frozen_string_literal: true

# Summarise the time a WPT run took, from the `ms` each file recorded.
#
#   ruby runner/wpt_perf.rb [--results results/wpt.jsonl] [--top 15]
#
# Wall time per file includes booting the page and testharness.js, so compare
# totals between runs on the same machine rather than quoting them.

require "json"
require "pathname"

ROOT = Pathname.new(__dir__).parent
argv = ARGV.dup
opt = ->(name, default) { (i = argv.index(name)) ? argv[i + 1] : default }
path = opt.("--results", ROOT.join("results/wpt.jsonl").to_s)
top = Integer(opt.("--top", "15"))

records = File.readlines(path).reject { _1.strip.empty? }.map { JSON.parse(_1) }.select { _1["ms"] }
abort "no timings in #{path} — re-run `rake wpt:run` first" if records.empty?

times = records.map { _1["ms"] }.sort
sum = times.sum
pct = ->(q) { times[[(times.size * q).ceil - 1, 0].max] }
puts format("%d files, %.1fs total; median %.0f ms, p90 %.0f ms, p99 %.0f ms", records.size, sum / 1000, pct.(0.5), pct.(0.9), pct.(0.99))

by_dir = records.group_by { _1["file"].split("/").first }.transform_values { |rs| rs.sum { _1["ms"] } }
puts "", "by top-level directory:"
by_dir.sort_by { -_2 }.each { |dir, ms| puts format("  %-24s %8.1fs  %4.1f%%", dir, ms / 1000, 100 * ms / sum) }

puts "", "slowest #{top} files:"
records.max_by(top) { _1["ms"] }.each { puts format("  %8.0f ms  %s", _1["ms"], _1["file"]) }
