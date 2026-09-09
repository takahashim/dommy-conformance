# frozen_string_literal: true

source "https://rubygems.org"

gem "rake", "~> 13.0"

# This repo measures whatever it is pointed at, so it pins nothing: a sibling
# checkout wins, and a released gem is the fallback (which is how you would
# measure a published version).
def sibling(*candidates)
  candidates.map { |c| File.expand_path(c, __dir__) }.find { |c| File.directory?(File.join(c, "lib")) }
end

if (dommy = ENV["DOMMY_PATH"] || sibling("../dommy/gems/dommy", "../dommy"))
  gem "dommy", path: dommy
else
  gem "dommy"
end

if (quickjs = ENV["DOMMY_JS_QUICKJS_PATH"] || sibling("../dommy-js-quickjs"))
  gem "dommy-js-quickjs", path: quickjs
else
  gem "dommy-js-quickjs"
end
