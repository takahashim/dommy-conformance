#!/usr/bin/env ruby
# frozen_string_literal: true

# Refresh every vendored WPT file from an upstream checkout, and pin the
# revision it came from.
#
#   ruby script/refresh-corpus.rb /path/to/web-platform-tests [--dry-run]
#
# The corpus is a dommy-selected SLICE of upstream: which files are in it is a
# decision recorded by the files themselves, so this only updates the content of
# files already vendored. It never adds new ones.
#
# Upstream rewrites tests, and a stale copy is worse than no copy: it pins an
# expectation the spec no longer has, and a correct implementation then reads as
# a regression. Two of those cost a bisect through dommy's history before the
# corpus turned out to be the stale side.
#
# A file upstream has deleted is reported, not removed — whether to drop it from
# the corpus is a judgement call (upstream may have merged it elsewhere).
#
# wpt/LOCAL_FILES lists the few files that are deliberately not upstream's (a
# wptserve template this harness has to answer for itself); those are skipped.

require "fileutils"
require "shellwords"

ROOT = File.expand_path("..", __dir__)
CORPUS = File.join(ROOT, "wpt/corpus")
HARNESS = File.join(ROOT, "wpt/testharness.js")
REVISION = File.join(ROOT, "wpt/UPSTREAM_REVISION")
LOCAL = File.readlines(File.join(ROOT, "wpt/LOCAL_FILES"), chomp: true)
  .reject { _1.strip.empty? || _1.start_with?("#") }

upstream = ARGV.find { |a| !a.start_with?("--") }
dry_run = ARGV.include?("--dry-run")
abort "usage: ruby script/refresh-corpus.rb /path/to/web-platform-tests [--dry-run]" unless upstream
abort "not a WPT checkout: #{upstream}" unless File.directory?(File.join(upstream, "resources"))

revision = `git -C #{upstream.shellescape} log -1 --format=%H`.strip
date = `git -C #{upstream.shellescape} log -1 --format=%cs`.strip
abort "cannot read #{upstream}'s HEAD" if revision.empty?

# Every tracked corpus file, plus the harness served from wpt/.
pairs = `git -C #{ROOT.shellescape} ls-files wpt/corpus`.lines(chomp: true).map do |tracked|
  rel = tracked.sub("wpt/corpus/", "")
  [File.join(CORPUS, rel), File.join(upstream, rel), rel]
end
pairs << [HARNESS, File.join(upstream, "resources/testharness.js"), "resources/testharness.js"]
pairs.reject! { |_local, _up, rel| LOCAL.include?(rel) }

updated, gone = [], []
pairs.each do |local, up, rel|
  next gone << rel unless File.exist?(up)
  next if File.binread(local) == File.binread(up)

  updated << rel
  FileUtils.cp(up, local) unless dry_run
end

File.write(REVISION, "#{revision}\n") unless dry_run

puts "upstream #{revision[0, 12]} (#{date})"
puts "#{dry_run ? "would update" : "updated"} #{updated.size} of #{pairs.size} files"
puts updated.map { "  #{_1}" }
unless gone.empty?
  puts "gone from upstream (#{gone.size}) — decide per file whether the corpus keeps it:"
  puts gone.map { "  #{_1}" }
end
