#!/usr/bin/env ruby
# frozen_string_literal: true

# Compare a WPT run against the recorded per-file baseline.
#
#   ruby runner/wpt_diff.rb [--results results/wpt.jsonl] [--record]
#
# The baseline is EXACT, not a floor: every file's pass/total is pinned. A
# regression fails; so does an unrecorded improvement, because the point of the
# record is that a change's effect on the corpus is stated up front and
# reviewable in the diff. `--record` rewrites it.
#
# Recording pass/total per file — rather than "min_pass plus a list of expected
# failure names" — is what makes "this change moved exactly these files, in this
# direction" a one-line answer.

require "json"
require "pathname"

ROOT = Pathname.new(__dir__).parent

module WptDiff
  module_function

  def flag(argv, name, default = nil)
    index = argv.index(name)
    index ? argv[index + 1] : default
  end

  def load_results(path)
    File.readlines(path).reject { |l| l.strip.empty? }.to_h do |line|
      record = JSON.parse(line)
      [record["file"], record]
    end
  end

  def baseline_path = ROOT.join("expectations/wpt.json")

  def summarize(results)
    pass = results.values.sum { |r| r["pass"].to_i }
    total = results.values.sum { |r| r["total"].to_i }
    green = results.values.count { |r| r["total"].to_i.positive? && r["pass"] == r["total"] }
    errored = results.values.count { |r| r["error"] }
    {"subtests_passed" => pass, "subtests_total" => total, "files" => results.size,
     "files_green" => green, "files_errored" => errored}
  end

  def record!(results)
    files = results.keys.sort.to_h do |file|
      record = results[file]
      entry =
        if record["error"]
          {"error" => record["error"]}
        else
          {"pass" => record["pass"], "total" => record["total"]}
        end
      [file, entry]
    end
    payload = {
      "README" => "Per-file WPT baseline. Exact, not a floor: `rake wpt` fails on any " \
                  "movement in either direction, so a change states its effect on the " \
                  "corpus in the diff. Re-record with `rake wpt:record`.",
      "summary" => summarize(results),
      "files" => files
    }
    File.write(baseline_path, JSON.pretty_generate(payload) + "\n")
    warn("recorded #{files.size} files to #{baseline_path}")
  end

  def cell(entry)
    return "ERROR(#{entry["error"]})" if entry.nil? || entry["error"]

    "#{entry["pass"]}/#{entry["total"]}"
  end

  def main(argv)
    results_path = flag(argv, "--results", ROOT.join("results/wpt.jsonl").to_s)
    unless File.exist?(results_path)
      warn("no results at #{results_path} — run `rake wpt:run` first")
      return 1
    end
    results = load_results(results_path)

    if argv.include?("--record")
      record!(results)
      return 0
    end

    unless File.exist?(baseline_path)
      warn("no baseline at #{baseline_path} — create it with `rake wpt:record`")
      return 1
    end
    baseline = JSON.parse(File.read(baseline_path))
    recorded = baseline["files"]

    now = summarize(results)
    was = baseline["summary"]
    puts "subtests  #{was["subtests_passed"]}/#{was["subtests_total"]}  ->  #{now["subtests_passed"]}/#{now["subtests_total"]}"
    puts "files     #{was["files_green"]} green of #{was["files"]}  ->  #{now["files_green"]} green of #{now["files"]}"

    improved = []
    regressed = []
    (recorded.keys | results.keys).sort.each do |file|
      before = recorded[file]
      after = results[file]
      after_entry = after.nil? ? nil : (after["error"] ? {"error" => after["error"]} : {"pass" => after["pass"], "total" => after["total"]})
      next if before == after_entry

      line = "  #{file}: #{cell(before)} -> #{cell(after_entry)}"
      if before.nil? || before["error"] || after_entry.nil? || after_entry["error"]
        (after_entry && !after_entry["error"] ? improved : regressed) << line
      elsif after_entry["pass"] > before["pass"]
        improved << line
      else
        regressed << line
      end
    end

    unless improved.empty?
      puts
      puts "IMPROVED (#{improved.size}) — re-record with `rake wpt:record` to accept:"
      puts improved
    end
    unless regressed.empty?
      puts
      puts "REGRESSED (#{regressed.size}):"
      puts regressed
    end

    if improved.empty? && regressed.empty?
      puts
      puts "no per-file change"
      return 0
    end
    1
  end
end

exit(WptDiff.main(ARGV)) if $PROGRAM_NAME == __FILE__
