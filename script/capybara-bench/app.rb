# frozen_string_literal: true

require "json"
require "rack"
require "uri"

# The app every driver is benchmarked against: an ordinary server-rendered
# site. The plain pages need no JavaScript (rack_test can drive them); the
# /hw pages are the Hotwire flavour Rails ships by default — the real Turbo and
# Stimulus bundles, Turbo Drive navigation, a Turbo Frame, a 422 form round
# trip and a fetch() from a Stimulus controller.
module BenchApp
  ITEMS = (1..50).map { |i| {"id" => i, "name" => "Item #{i}", "price" => i * 3} }
  CATEGORIES = %w[Books Tools Garden Toys].freeze
  ASSETS = {
    "/assets/turbo.js" => "@hotwired/turbo/dist/turbo.es2017-umd.js",
    "/assets/stimulus.js" => "@hotwired/stimulus/dist/stimulus.umd.js",
  }.freeze
  NODE_MODULES = File.join(__dir__, "node_modules")
  CONTROLLERS = File.read(File.join(__dir__, "controllers.js"))

  module_function

  def call(env)
    req = Rack::Request.new(env)
    route(req.request_method, req.path_info, req)
  rescue KeyError, ArgumentError
    html(404, "Not found", "<h1>Not found</h1>")
  end

  def route(verb, path, req)
    case [verb, path]
    in ["GET", "/"] then html(200, "Items", item_list("/items"))
    in ["GET", "/items/new"] then html(200, "New item", item_form("/items"))
    in ["POST", "/items"] then create(req, "/items")
    in ["GET", "/items/created"] then html(200, "Created", created(req))
    in ["GET", %r{\A/items/(\d+)\z}] then html(200, "Item", item_page(Regexp.last_match(1), "/"))
    in ["GET", "/table"] then html(200, "Table", table)
    in ["GET", "/hw/items"] then hw(200, "Items", item_list("/hw/items"))
    in ["GET", %r{\A/hw/items/(\d+)\z}] then hw(200, "Item", item_page(Regexp.last_match(1), "/hw/items"))
    in ["GET", "/hw/new"] then hw(200, "New item", item_form("/hw/items"))
    in ["POST", "/hw/items"] then create(req, "/hw/items", hotwire: true)
    in ["GET", "/hw/items/created"] then hw(200, "Created", created(req))
    in ["GET", "/hw/counter"] then hw(200, "Counter", counter)
    in ["GET", "/hw/frames"] then hw(200, "Frames", frames)
    in ["GET", %r{\A/hw/frames/(\d+)\z}] then hw(200, "Frame", frame(Regexp.last_match(1)))
    in ["GET", "/hw/fetch"] then hw(200, "Fetch", loader)
    in ["GET", "/api/items.json"] then [200, {"content-type" => "application/json"}, [JSON.generate(ITEMS)]]
    in ["GET", "/assets/controllers.js"] then js(CONTROLLERS)
    in ["GET", String] if ASSETS.key?(path) then js(File.read(File.join(NODE_MODULES, ASSETS.fetch(path))))
    else html(404, "Not found", "<h1>Not found</h1>")
    end
  end

  def html(status, title, body, head = "")
    page = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>#{title}</title>#{head}</head>" \
           "<body>#{body}</body></html>"
    [status, {"content-type" => "text/html; charset=utf-8"}, [page]]
  end

  def hw(status, title, body)
    html(status, title, body, '<script src="/assets/turbo.js"></script><script src="/assets/stimulus.js"></script>' \
                              '<script src="/assets/controllers.js"></script>')
  end

  def js(source) = [200, {"content-type" => "text/javascript"}, [source]]
  def esc(text) = Rack::Utils.escape_html(text.to_s)

  def item_list(base)
    links = ITEMS.map { |i| %(<li><a href="#{base}/#{i["id"]}">#{i["name"]}</a></li>) }.join
    %(<h1>Items</h1><nav><a href="#{base == "/items" ? "/items/new" : "/hw/new"}">New item</a></nav><ul id="items">#{links}</ul>)
  end

  def item_page(id, back)
    item = ITEMS.fetch(Integer(id) - 1)
    %(<h1>#{item["name"]}</h1><p class="price">$#{item["price"]}</p><a href="#{back}">All items</a>)
  end

  def item_form(action, errors = [], values = {})
    error_list = errors.empty? ? "" : %(<ul class="errors">#{errors.map { "<li>#{esc(_1)}</li>" }.join}</ul>)
    options = CATEGORIES.map { |c| %(<option#{" selected" if values["category"] == c}>#{c}</option>) }.join
    <<~HTML
      <h1>New item</h1>#{error_list}
      <form action="#{action}" method="post">
        <label for="name">Name</label><input id="name" name="name" value="#{esc(values["name"])}">
        <label for="price">Price</label><input id="price" name="price" type="number" value="#{esc(values["price"])}">
        <label for="category">Category</label><select id="category" name="category">#{options}</select>
        <label><input type="checkbox" name="agree" value="1"> I agree</label>
        <button type="submit">Create</button>
      </form>
    HTML
  end

  def create(req, action, hotwire: false)
    params = req.POST
    errors = []
    errors << "Name can't be blank" if params["name"].to_s.strip.empty?
    errors << "Terms must be accepted" unless params["agree"] == "1"
    if errors.empty?
      query = URI.encode_www_form(name: params["name"], category: params["category"])
      [303, {"location" => "#{action}/created?#{query}"}, []]
    else
      # 422, as Rails renders a failed create — the status Turbo requires to
      # render a form response in place.
      (hotwire ? method(:hw) : method(:html)).call(422, "New item", item_form(action, errors, params))
    end
  end

  def created(req) = "<h1>Created #{esc(req.GET["name"])}</h1><p>in #{esc(req.GET["category"])}</p>"

  def table
    rows = (1..500).map do |i|
      %(<tr id="row-#{i}"><td class="name">Row #{i}</td><td class="price">#{i * 3}</td><td><a href="/items/#{(i % 50) + 1}">edit</a></td></tr>)
    end
    %(<h1>Table</h1><table><thead><tr><th>Name</th><th>Price</th><th></th></tr></thead><tbody>#{rows.join}</tbody></table>)
  end

  def counter
    fruits = (1..100).map { %(<li data-filter-target="item">Fruit #{_1}</li>) }.join
    <<~HTML
      <h1>Counter</h1>
      <div data-controller="counter">
        <button data-action="counter#increment">Add one</button> <output data-counter-target="count">0</output>
      </div>
      <div data-controller="toggle">
        <button data-action="toggle#toggle">Details</button>
        <section data-toggle-target="panel" hidden><p>The hidden details</p></section>
      </div>
      <div data-controller="filter">
        <label for="q">Filter</label><input id="q" data-filter-target="input" data-action="input->filter#filter">
        <ul>#{fruits}</ul>
      </div>
    HTML
  end

  def frames
    links = (1..10).map { %(<a href="/hw/frames/#{_1}" data-turbo-frame="detail">Show #{_1}</a>) }.join(" ")
    %(<h1>Frames</h1><nav>#{links}</nav><turbo-frame id="detail"><p>Pick one</p></turbo-frame>)
  end

  def frame(id) = %(<h1>Frame page</h1><turbo-frame id="detail"><p>Detail #{Integer(id)}</p></turbo-frame>)

  def loader
    %(<h1>Fetch</h1><div data-controller="loader"><button data-action="loader#load">Load</button>) +
      %(<ul id="loaded" data-loader-target="list"></ul></div>)
  end
end
