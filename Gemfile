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

# TEMPORARY, mirroring dommy-js-quickjs's own Gemfile: the released quickjs
# (0.21.0) reports an unhandled rejection the moment a promise rejects rather
# than at the end of the microtask checkpoint as HTML requires, and hands the
# host no promise/reason to report. The binding is written against the fork that
# fixes both, so measuring it on the released gem measures a different engine.
# Drop this once the fork is released.
# https://github.com/hmsk/quickjs.rb/pull/141
gem "quickjs", github: "takahashim/quickjs.rb", ref: "ef60ed5",
  submodules: true # the QuickJS C sources are a submodule

if (quickjs = ENV["DOMMY_JS_QUICKJS_PATH"] || sibling("../dommy-js-quickjs"))
  gem "dommy-js-quickjs", path: quickjs
else
  gem "dommy-js-quickjs"
end
