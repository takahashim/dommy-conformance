#!/usr/bin/env ruby
# frozen_string_literal: true

# Compare the two runners' observations and report where they disagree.
#
#   ruby runner/diff.rb [--chromium results/chromium.jsonl] [--dommy results/dommy.jsonl]
#
# A browser is an ORACLE, not the specification. Where the two disagree and it
# is Chromium departing from the spec text, the divergence is recorded in
# expectations/known-divergences.yml with the reasoning, and does not fail the
# run — but it is still printed, so a recorded divergence that quietly changed
# shape does not pass unnoticed.

require "json"
require "yaml"
require "pathname"

ROOT = Pathname.new(__dir__).parent

module OracleDiff
  Divergence = Struct.new(:case_id, :key, :chromium, :dommy, :expectation, keyword_init: true) do
    def expected? = !expectation.nil?
  end

  module_function

  def load_jsonl(path)
    return {} unless File.exist?(path)

    File.readlines(path).reject { |l| l.strip.empty? }.to_h do |line|
      record = JSON.parse(line)
      [record["case"], record]
    end
  end

  def expectations
    path = ROOT.join("expectations/known-divergences.yml")
    return [] unless File.exist?(path)

    Array(YAML.safe_load_file(path))
  end

  # Every expectation that could apply, in file order. A case may carry several
  # (a fuzz case accumulates one per known divergence shape), so the caller has
  # to try them all rather than stopping at the first case/key match.
  def expectations_for(list, case_id, key)
    list.select { |e| e["case"] == case_id && (e["key"] == key || e["key"] == "*") }
  end

  # A fuzz divergence cannot be recorded by pinning its values: the step log is
  # thousands of lines and every seed produces a different one. What identifies
  # it is its SHAPE — which operation was being performed, and which parts of
  # the observation disagreed. An expectation carrying `step_divergence` matches
  # on that, so the one known divergence is tolerated wherever a seed happens to
  # hit it while any OTHER divergence still fails the run.
  def step_divergence_matches?(expectation, chromium, dommy)
    matcher = expectation["step_divergence"]
    return false unless matcher

    index = (0...[chromium.size, dommy.size].max).find { |i| chromium[i] != dommy[i] }
    return false if index.nil?

    left = chromium[index].to_h
    right = dommy[index].to_h
    return false if matcher["op"] && left["op"] != matcher["op"]

    differing = (left.keys | right.keys).select { |k| left[k] != right[k] }.sort
    return false if matcher["keys"] && matcher["keys"].sort != differing

    true
  end

  # Walk the two result objects together, keyed by the names the case chose.
  # A key missing on one side is itself a divergence.
  def compare(case_id, chromium, dommy, expectations)
    return [runner_failure(case_id, chromium, dommy)] if chromium["error"] || dommy["error"]

    left = chromium["result"] || {}
    right = dommy["result"] || {}
    return [Divergence.new(case_id: case_id, key: "(result)", chromium: left, dommy: right)] unless
      left.is_a?(Hash) && right.is_a?(Hash)

    (left.keys | right.keys).sort.filter_map do |key|
      next if left[key] == right[key]

      # A step-log expectation only applies if the divergence really has the
      # shape it describes; otherwise this is a new finding that merely lands in
      # a case that has recorded ones.
      expectation = expectations_for(expectations, case_id, key).find do |candidate|
        next true unless candidate["step_divergence"]

        step_log?(left[key]) && step_log?(right[key]) &&
          step_divergence_matches?(candidate, left[key], right[key])
      end

      Divergence.new(
        case_id: case_id, key: key, chromium: left[key], dommy: right[key],
        expectation: expectation
      )
    end
  end

  def runner_failure(case_id, chromium, dommy)
    Divergence.new(
      case_id: case_id, key: "(the case did not run)",
      chromium: chromium["error"] || "ok", dommy: dommy["error"] || "ok"
    )
  end

  def render(value)
    text = JSON.generate(value)
    text.length > 400 ? text[0, 397] + "..." : text
  end

  # A step log (what the fuzzer returns) diffs badly as two blobs: once the two
  # engines diverge they pick different operands afterwards, so every later step
  # differs too and the real finding is buried. Report the FIRST differing step
  # with the couple of steps that led to it, and stop.
  def step_log?(value)
    value.is_a?(Array) && value.first.is_a?(Hash) && value.first.key?("step")
  end

  def render_step_divergence(chromium, dommy)
    index = (0...[chromium.size, dommy.size].max).find { |i| chromium[i] != dommy[i] }
    return ["    the logs differ but no step does — lengths #{chromium.size} vs #{dommy.size}"] if index.nil?

    lines = []
    lines << "    #{chromium.size} steps; first divergence at step #{index}"
    context = [index - 2, 0].max
    (context...index).each do |i|
      lines << "      step #{i} (agreed) #{chromium[i]["op"]}: #{chromium[i]["did"] || chromium[i]["threw"] || "skipped"}"
    end
    left = chromium[index]
    right = dommy[index]
    lines << "      step #{index} #{left&.dig("op")}: #{left&.dig("did") || left&.dig("threw") || "skipped"}"
    (left.to_h.keys | right.to_h.keys).sort.each do |key|
      next if left.to_h[key] == right.to_h[key]

      lines << "        #{key}"
      lines << "          chromium: #{render(left.to_h[key])}"
      lines << "          dommy:    #{render(right.to_h[key])}"
    end
    lines
  end

  def flag(argv, name, default)
    index = argv.index(name)
    index ? argv[index + 1] : default
  end

  def main(argv)
    chromium = load_jsonl(flag(argv, "--chromium", ROOT.join("results/chromium.jsonl").to_s))
    dommy = load_jsonl(flag(argv, "--dommy", ROOT.join("results/dommy.jsonl").to_s))
    known = expectations

    if chromium.empty? || dommy.empty?
      warn("no results to compare — run `rake oracle:chromium` and `rake oracle:dommy` first")
      return 1
    end

    only_chromium = chromium.keys - dommy.keys
    only_dommy = dommy.keys - chromium.keys
    shared = (chromium.keys & dommy.keys).sort

    divergences = shared.flat_map { |id| compare(id, chromium[id], dommy[id], known) }
    unexpected, accounted = divergences.partition { |d| !d.expected? }
    # Two very different reasons a divergence is not a failure, and conflating
    # them would be the worst thing this file could do: "Chromium is the one
    # departing from the spec" is a settled answer, "Dommy has a bug we have not
    # fixed yet" is an open debt. They are reported separately.
    gaps, expected = accounted.partition { |d| d.expectation["dommy_bug"] }

    puts "#{shared.size} cases compared"
    unless only_chromium.empty? && only_dommy.empty?
      puts "  ran on one side only: chromium=#{only_chromium.inspect} dommy=#{only_dommy.inspect}"
    end

    unless expected.empty?
      puts
      puts "recorded divergences (#{expected.size}) — Chromium and Dommy differ on purpose:"
      expected.each do |d|
        puts "  #{d.case_id} [#{d.key}]"
        unless d.expectation["step_divergence"]
          puts "    chromium: #{render(d.chromium)}"
          puts "    dommy:    #{render(d.dommy)}"
        end
        puts "    reason:   #{d.expectation["reason"].to_s.strip.lines.first&.strip}"
        # A recorded divergence whose values moved is no longer the same finding.
        if d.expectation["step_divergence"]
          puts "    shape:    #{JSON.generate(d.expectation["step_divergence"])}"
        end
        if d.expectation.key?("chromium") && d.expectation["chromium"] != d.chromium
          puts "    !! the recorded chromium value no longer matches — re-check this expectation"
        end
        if d.expectation.key?("dommy") && d.expectation["dommy"] != d.dommy
          puts "    !! the recorded dommy value no longer matches — re-check this expectation"
        end
      end
    end

    unless gaps.empty?
      puts
      puts "known Dommy gaps (#{gaps.size}) — real bugs, recorded so the run stays actionable:"
      gaps.group_by(&:case_id).each do |case_id, list|
        puts "  #{case_id}"
        list.each do |d|
          puts "    #{d.key}: #{d.expectation["dommy_bug"].to_s.strip.lines.first&.strip}"
        end
      end
    end

    if unexpected.empty?
      puts
      puts "no unexpected divergences"
      return 0
    end

    puts
    puts "UNEXPECTED DIVERGENCES (#{unexpected.size}):"
    unexpected.group_by(&:case_id).each do |case_id, list|
      name = chromium.dig(case_id, "name") || case_id
      puts
      puts "  #{case_id}"
      puts "  #{name}"
      list.each do |d|
        puts "    #{d.key}"
        if step_log?(d.chromium) && step_log?(d.dommy)
          puts render_step_divergence(d.chromium, d.dommy)
        else
          puts "      chromium: #{render(d.chromium)}"
          puts "      dommy:    #{render(d.dommy)}"
        end
      end
    end
    1
  end
end

exit(OracleDiff.main(ARGV)) if $PROGRAM_NAME == __FILE__
