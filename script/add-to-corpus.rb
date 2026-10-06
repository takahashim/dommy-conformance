#!/usr/bin/env ruby
# frozen_string_literal: true

# Vendor more of web-platform-tests into the corpus, from an upstream checkout
# at the revision the corpus is pinned to.
#
#   ruby script/add-to-corpus.rb /path/to/web-platform-tests PATH... [--exclude PATH]... [--dry-run]
#
# Each PATH is a directory or file relative to the WPT root
# (`shadow-dom/declarative`, `html/webappapis/dynamic-markup-insertion`). A
# directory is copied whole — its `support/` and `resources/` files with it, so
# the pages its tests load in iframes resolve — and every root-absolute include
# a copied file names (`<script src="/common/...">`, `// META: script=/...`) is
# copied too, transitively.
#
# The checkout must be at wpt/UPSTREAM_REVISION: a file from another revision
# would mix two upstreams in one corpus, which is exactly the staleness
# script/refresh-corpus.rb exists to prevent. A wpt/NON_SPEC_FILES file named
# outright is refused; one inside a named directory is skipped (and reported),
# as is everything under an `--exclude` path, so a directory can be vendored
# without the proposals it also holds. Files already vendored are left alone
# (refresh-corpus.rb updates those).
#
# Copying does not change expectations/wpt.json; run the corpus and record it.

require "fileutils"
require "shellwords"

ROOT = File.expand_path("..", __dir__)
CORPUS = File.join(ROOT, "wpt/corpus")
def listed(path)
  File.readlines(path, chomp: true).reject { _1.strip.empty? || _1.start_with?("#") }
end
NON_SPEC = listed(File.join(ROOT, "wpt/NON_SPEC_FILES"))
PINNED = File.read(File.join(ROOT, "wpt/UPSTREAM_REVISION")).strip
# Served by the harness itself (lib/wpt/resources.rb), never from the corpus.
HARNESS_SERVED = %w[
  resources/testharness.js resources/testharnessreport.js resources/testdriver.js
  resources/testdriver-vendor.js resources/testdriver-actions.js
].freeze

argv = ARGV.dup
excluded = []
while (i = argv.index("--exclude"))
  excluded << argv.delete_at(i + 1).to_s.delete_suffix("/")
  argv.delete_at(i)
end
args = argv.reject { _1.start_with?("--") }
dry_run = argv.include?("--dry-run")
upstream = args.shift
abort "usage: ruby script/add-to-corpus.rb /path/to/web-platform-tests PATH... [--dry-run]" if upstream.nil? || args.empty?
abort "not a WPT checkout: #{upstream}" unless File.directory?(File.join(upstream, "resources"))

revision = `git -C #{upstream.shellescape} log -1 --format=%H`.strip
abort "#{upstream} is at #{revision[0, 12]}, the corpus is pinned to #{PINNED[0, 12]}" unless revision == PINNED

def files_under(upstream, rel)
  path = File.join(upstream, rel)
  abort "not in the checkout: #{rel}" unless File.exist?(path)
  return [rel] if File.file?(path)

  Dir.glob("**/*", File::FNM_DOTMATCH, base: path)
     .select { File.file?(File.join(path, _1)) }
     .map { File.join(rel, _1) }
end

# Root-absolute includes a test file names: script/link src/href attributes and
# testharness `// META: script=` lines. Relative ones live beside the file and
# arrive with its directory.
def absolute_includes(text)
  text.scan(%r{(?:src|href)\s*=\s*["'](/[^"'?#]+)}).flatten
      .concat(text.scan(%r{^//\s*META:\s*script=(/\S+)}).flatten)
      .map { _1.delete_prefix("/") }
end

refused = args & NON_SPEC
abort "non-spec files (wpt/NON_SPEC_FILES) cannot be vendored:\n  #{refused.join("\n  ")}" unless refused.empty?

excluded_path = ->(rel) { excluded.any? { |x| rel == x || rel.start_with?("#{x}/") } }
wanted = args.flat_map { files_under(upstream, _1) }.reject(&excluded_path)
skipped = wanted & NON_SPEC
wanted -= skipped
queue = wanted.dup
until queue.empty?
  rel = queue.shift
  next unless rel.match?(/\.(html?|js|xhtml|svg)\z/)

  text = File.binread(File.join(upstream, rel)).force_encoding(Encoding::UTF_8).scrub
  absolute_includes(text).each do |inc|
    next if HARNESS_SERVED.include?(inc) || wanted.include?(inc) || NON_SPEC.include?(inc) || excluded_path.(inc)
    next unless File.file?(File.join(upstream, inc))

    wanted << inc
    queue << inc
  end
end

added = wanted.uniq.reject { File.exist?(File.join(CORPUS, _1)) }
added.each do |rel|
  next if dry_run

  dest = File.join(CORPUS, rel)
  FileUtils.mkdir_p(File.dirname(dest))
  FileUtils.cp(File.join(upstream, rel), dest)
end

puts "upstream #{revision[0, 12]}"
puts "#{dry_run ? "would add" : "added"} #{added.size} files (#{wanted.uniq.size - added.size} already vendored)"
puts "skipped #{skipped.size} non-spec files (wpt/NON_SPEC_FILES)" unless skipped.empty?
