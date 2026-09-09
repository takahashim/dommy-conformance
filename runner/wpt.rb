#!/usr/bin/env ruby
# frozen_string_literal: true

# Run the vendored WPT corpus against dommy and write one JSON line per file.
#
#   ruby runner/wpt.rb [--filter substring] [--out results/wpt.jsonl]
#                      [--engine quickjs] [--jobs N] [--timeout SECONDS]
#
# Each file runs in a FORKED child with a timeout. A WPT file is arbitrary
# third-party JavaScript driving a whole browser stack: one that wedges, or
# corrupts the JS heap, or exhausts memory must not take the run with it. The
# child's result comes back as one JSON line over a pipe.

require "json"
require "timeout"
require "pathname"
require "fileutils"
require "etc"

ROOT = Pathname.new(__dir__).parent

def use_checkout(env_var, *relative_candidates)
  candidates = [ENV[env_var], *relative_candidates.map { |c| ROOT.join(c).to_s }].compact
  found = candidates.find { |c| File.directory?(File.join(c, "lib")) }
  $LOAD_PATH.unshift(File.join(found, "lib")) if found
  found
end

use_checkout("DOMMY_PATH", "../dommy/gems/dommy", "../dommy")
use_checkout("DOMMY_JS_QUICKJS_PATH", "../dommy-js-quickjs", "../takahashim/dommy-js-quickjs")
$LOAD_PATH.unshift(ROOT.join("lib").to_s)

ENGINE = (ARGV.include?("--engine") ? ARGV[ARGV.index("--engine") + 1] : ENV.fetch("ENGINE", "quickjs"))

require "dommy"
# The corpus is engine-agnostic; the binding is chosen here and Dommy::Browser
# picks up whatever registered itself.
require "dommy/js/#{ENGINE}"
require "wpt"

module WptRun
  module_function

  def flag(argv, name, default = nil)
    index = argv.index(name)
    index ? argv[index + 1] : default
  end

  # One file, in a forked child. Returns the parsed record, or a record naming
  # how the child died — never raises.
  def run_isolated(rel, timeout)
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      # A WPT file's own output is noise here; only the JSON line matters.
      $stdout.reopen(File::NULL)
      $stderr.reopen(File::NULL)
      begin
        results = DommyConformance::Wpt::Runner.run(rel)
        writer.puts JSON.generate(
          file: rel,
          pass: results.count(&:pass?),
          total: results.size,
          failing: results.reject(&:pass?).map { |r| {status: r.status_name, name: r.name, message: r.message.to_s[0, 200]} }
        )
      rescue Exception => e # rubocop:disable Lint/RescueException -- report anything, including a NoMemoryError
        writer.puts JSON.generate(file: rel, error: "#{e.class}: #{e.message.to_s[0, 200]}")
      end
      writer.close
      exit!(0)
    end
    writer.close

    line = nil
    begin
      Timeout.timeout(timeout) { line = reader.read }
    rescue Timeout::Error
      begin
        Process.kill("KILL", pid)
      rescue StandardError
        nil
      end
      line = JSON.generate(file: rel, error: "TIMEOUT after #{timeout}s")
    end
    begin
      Process.wait(pid)
    rescue StandardError
      nil
    end
    reader.close
    line = JSON.generate(file: rel, error: "the child produced no output (crash?)") if line.nil? || line.strip.empty?
    JSON.parse(line)
  end

  def main(argv)
    filter = flag(argv, "--filter")
    out = flag(argv, "--out", ROOT.join("results/wpt.jsonl").to_s)
    timeout = flag(argv, "--timeout", ENV.fetch("WPT_FILE_TIMEOUT", "120")).to_i

    files = DommyConformance::Wpt::Runner.manifest
    files = files.select { |f| f.include?(filter) } if filter
    warn("running #{files.size} WPT files against dommy (engine: #{ENGINE})")

    FileUtils.mkdir_p(File.dirname(out))
    total_pass = total = green = 0
    File.open(out, "w") do |io|
      files.each_with_index do |rel, index|
        record = run_isolated(rel, timeout)
        io.puts JSON.generate(record)
        io.flush
        if record["error"]
          warn(format("  %4d/%d  !  %-58s %s", index + 1, files.size, rel, record["error"]))
        else
          total_pass += record["pass"]
          total += record["total"]
          green += 1 if record["total"].positive? && record["pass"] == record["total"]
          mark = record["pass"] == record["total"] ? "✓" : " "
          warn(format("  %4d/%d  %s  %-58s %d/%d", index + 1, files.size, mark, rel, record["pass"], record["total"]))
        end
      end
    end

    percent = total.zero? ? 0 : (100.0 * total_pass / total).round(1)
    warn("")
    warn("WPT conformance: #{total_pass}/#{total} subtests (#{percent}%) across #{files.size} files; #{green} files fully green")
    warn("wrote #{out}")
  end
end

WptRun.main(ARGV) if $PROGRAM_NAME == __FILE__
