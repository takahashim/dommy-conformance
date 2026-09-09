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

  def expectation_for(list, case_id, key)
    list.find { |e| e["case"] == case_id && e["key"] == key }
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

      Divergence.new(
        case_id: case_id, key: key, chromium: left[key], dommy: right[key],
        expectation: expectation_for(expectations, case_id, key)
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
    unexpected, expected = divergences.partition { |d| !d.expected? }

    puts "#{shared.size} cases compared"
    unless only_chromium.empty? && only_dommy.empty?
      puts "  ran on one side only: chromium=#{only_chromium.inspect} dommy=#{only_dommy.inspect}"
    end

    unless expected.empty?
      puts
      puts "recorded divergences (#{expected.size}) — Chromium and Dommy differ on purpose:"
      expected.each do |d|
        puts "  #{d.case_id} [#{d.key}]"
        puts "    chromium: #{render(d.chromium)}"
        puts "    dommy:    #{render(d.dommy)}"
        puts "    reason:   #{d.expectation["reason"].to_s.strip.lines.first&.strip}"
        # A recorded divergence whose values moved is no longer the same finding.
        if d.expectation.key?("chromium") && d.expectation["chromium"] != d.chromium
          puts "    !! the recorded chromium value no longer matches — re-check this expectation"
        end
        if d.expectation.key?("dommy") && d.expectation["dommy"] != d.dommy
          puts "    !! the recorded dommy value no longer matches — re-check this expectation"
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
        puts "      chromium: #{render(d.chromium)}"
        puts "      dommy:    #{render(d.dommy)}"
      end
    end
    1
  end
end

exit(OracleDiff.main(ARGV)) if $PROGRAM_NAME == __FILE__
