# frozen_string_literal: true

# Print two `bench.rb --json` files side by side: ruby compare.rb OLD NEW
require "json"

old, new = ARGV.map { JSON.parse(File.read(_1)) }
abort "usage: compare.rb OLD.json NEW.json" unless old && new

puts "makiri #{old.dig("versions", "makiri")} -> #{new.dig("versions", "makiri")}; " \
     "dommy #{old.dig("versions", "dommy")} -> #{new.dig("versions", "dommy")}", ""
puts "| operation | old | new | new/old |", "|---|---:|---:|---:|"
new["seconds"].each do |name, sec|
  was = old["seconds"][name] or next
  puts format("| %s | %.1f µs | %.1f µs | %.2fx |", name, was * 1e6, sec * 1e6, sec / was)
end
puts "", "Single runs are noisy (a few percent to tens); repeat before reading a delta below ~15%."
