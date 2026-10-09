# frozen_string_literal: true

# Times the dommy operations that run on makiri: parsing, selector queries,
# serialization, text extraction and tree mutation, on a generated document.
# No JavaScript engine is involved, so the numbers move with makiri (and with
# dommy's own wrapper code on top of it), not with QuickJS.
#
#   ruby script/dom-bench/bench.rb [--items N] [--rounds N] [--filter S] [--json PATH]
#
# `rake bench:dom` calls this. Each row is the median of ROUNDS timed rounds
# after a warm-up; a round runs the row's block enough times to last ~50ms.

require "bundler/setup"
require "json"
require "dommy"
require "makiri"

argv = ARGV.dup
opt = ->(name, default) { (i = argv.index(name)) ? argv[i + 1] : default }
items = Integer(opt.("--items", ENV.fetch("BENCH_ITEMS", "2000")))
rounds = Integer(opt.("--rounds", ENV.fetch("ROUNDS", "9")))
filter = opt.("--filter", ENV["FILTER"])
json_path = opt.("--json", nil)

def build_html(items)
  rows = (1..items).map do |i|
    %(<li class="item r#{i % 7}" data-id="#{i}"><a href="/p/#{i}" class="link">item #{i}</a>) +
      %(<span class="meta">tag#{i % 13} &amp; more</span></li>)
  end.join("\n")
  <<~HTML
    <!doctype html><html><head><title>bench</title></head><body>
    <header id="top"><nav><a href="/">home</a></nav></header>
    <main id="main"><ul id="list">#{rows}</ul></main>
    <footer id="bot"><p>done</p></footer></body></html>
  HTML
end

HTML = build_html(items)
PARSER = Dommy::DOMParser.new

def fresh = PARSER.parse_from_string(HTML, "text/html")

doc = fresh
list = doc.get_element_by_id("list")

# A mutation invalidates whatever dommy caches per document generation, so a
# row that calls this measures the query itself rather than a cache hit.
touch = -> { list.set_attribute("data-t", "x") }

rows = {
  "parse" => -> { fresh },
  "querySelectorAll li" => -> { doc.query_selector_all("li").to_a },
  "querySelectorAll li (uncached)" => -> { touch.call; doc.query_selector_all("li").to_a },
  "querySelectorAll .item" => -> { doc.query_selector_all(".item").to_a },
  "querySelectorAll [data-id]" => -> { doc.query_selector_all("[data-id]").to_a },
  "querySelectorAll ul > li.r3 a" => -> { doc.query_selector_all("ul > li.r3 a").to_a },
  "querySelectorAll ul > li.r3 a (uncached)" => -> { touch.call; doc.query_selector_all("ul > li.r3 a").to_a },
  "querySelector #bot p" => -> { doc.query_selector("#bot p") },
  "getElementsByTagName a" => -> { doc.get_elements_by_tag_name("a").to_a },
  "matches" => -> { list.first_element_child.matches?("ul > li.item") },
  "closest" => -> { list.first_element_child.first_element_child.closest("main") },
  "outerHTML (document)" => -> { doc.document_element.outer_html },
  "innerHTML (list)" => -> { list.inner_html },
  "textContent (body)" => -> { doc.body.text_content },
  "children walk" => -> { list.children.to_a.each(&:tag_name) },
  "createElement+append+remove" => lambda {
    el = doc.create_element("li")
    el.set_attribute("class", "x")
    list.append_child(el)
    list.remove_child(el)
  },
  "setAttribute/getAttribute" => lambda {
    li = list.first_element_child
    li.set_attribute("data-x", "1")
    li.get_attribute("data-x")
  },
  "innerHTML= (small)" => lambda {
    host = doc.create_element("div")
    host.inner_html = "<p>a</p><p>b <b>c</b></p>"
  }
}
rows = rows.select { |name, _| name.include?(filter) } if filter

def time_row(block, rounds)
  3.times { block.call } # warm-up
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  block.call
  once = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  n = [(0.05 / [once, 1e-7].max).ceil, 1].max
  samples = Array.new(rounds) do
    GC.start
    t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    n.times { block.call }
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t) / n
  end
  samples.sort[samples.size / 2]
end

results = rows.to_h { |name, block| [name, time_row(block, rounds)] }

def fmt(sec)
  us = sec * 1e6
  us >= 1000 ? format("%.2f ms", us / 1000) : format("%.1f µs", us)
end

puts "| operation | median/call |", "|---|---:|"
results.each { |name, sec| puts "| #{name} | #{fmt(sec)} |" }
puts
puts "Ruby #{RUBY_VERSION}; makiri #{Makiri::VERSION}; dommy #{Dommy::VERSION}; #{items} items, #{rounds} rounds"

if json_path
  require "fileutils"
  FileUtils.mkdir_p(File.dirname(json_path))
  File.write(json_path, JSON.pretty_generate(
    versions: {ruby: RUBY_VERSION, makiri: Makiri::VERSION, dommy: Dommy::VERSION}, items: items,
    seconds: results
  ))
end
