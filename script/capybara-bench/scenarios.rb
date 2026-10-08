# frozen_string_literal: true

# What each benchmarked "test" does, in the plain Capybara DSL a feature spec
# uses. `js: true` scenarios need a driver that runs page JavaScript; the rest
# run on every driver. Each one asserts as it goes, so a driver that gets a
# page wrong fails the scenario instead of finishing it early.
module BenchScenarios
  Scenario = Struct.new(:name, :js, :body)

  def self.table(s, **visibility)
    s.visit "/table"
    s.assert_selector "tbody tr", count: 500, **visibility
    (1..20).each do |i|
      n = i * 25
      s.within("#row-#{n}") { s.assert_selector "td.price", text: (n * 3).to_s }
    end
    raise "expected 500 cells" unless s.all("td.name", **visibility).size == 500
  end

  ALL = [
    Scenario.new("browse", false, lambda do |s|
      s.visit "/"
      (1..10).each do |i|
        s.click_link "Item #{i}", exact: true
        s.assert_selector "h1", text: "Item #{i}"
        s.click_link "All items"
        s.assert_selector "h1", text: "Items"
      end
    end),

    Scenario.new("form", false, lambda do |s|
      s.visit "/items/new"
      s.click_button "Create"
      s.assert_text "Name can't be blank"
      s.fill_in "Name", with: "Widget"
      s.fill_in "Price", with: "12"
      s.select "Tools", from: "Category"
      s.check "I agree"
      s.click_button "Create"
      s.assert_selector "h1", text: "Created Widget"
      s.assert_text "in Tools"
    end),

    # The 500-row table, twice. Capybara checks every node it counts for
    # visibility by default; `table-all` counts with `visible: :all`. A browser
    # driver pays one round trip per check, so the gap between the two rows is
    # what that check costs each driver.
    Scenario.new("table", false, ->(s) { table(s) }),
    Scenario.new("table-all", false, ->(s) { table(s, visible: :all) }),

    Scenario.new("stimulus", true, lambda do |s|
      s.visit "/hw/counter"
      10.times { s.click_button "Add one" }
      s.assert_selector "output", text: "10"
      s.assert_no_text "The hidden details"
      s.click_button "Details"
      s.assert_text "The hidden details"
      s.fill_in "Filter", with: "Fruit 7"
      s.assert_selector "li", text: /\AFruit 7\d?\z/, count: 11
    end),

    Scenario.new("turbo-drive", true, lambda do |s|
      s.visit "/hw/items"
      (1..10).each do |i|
        s.click_link "Item #{i}", exact: true
        s.assert_selector "h1", text: "Item #{i}"
        s.click_link "All items"
        s.assert_selector "h1", text: "Items"
      end
    end),

    Scenario.new("turbo-frame", true, lambda do |s|
      s.visit "/hw/frames"
      (1..10).each do |i|
        s.click_link "Show #{i}"
        s.assert_selector "turbo-frame#detail", text: "Detail #{i}"
      end
      s.assert_selector "h1", text: "Frames" # the frame navigated, the page did not
    end),

    Scenario.new("turbo-form", true, lambda do |s|
      s.visit "/hw/new"
      s.click_button "Create"
      s.assert_text "Name can't be blank"
      s.fill_in "Name", with: "Widget"
      s.select "Tools", from: "Category"
      s.check "I agree"
      s.click_button "Create"
      s.assert_selector "h1", text: "Created Widget"
    end),

    Scenario.new("fetch", true, lambda do |s|
      s.visit "/hw/fetch"
      s.click_button "Load"
      s.assert_selector "#loaded li", count: 50
    end),
  ].freeze
end
