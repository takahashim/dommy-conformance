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

# TEMPORARY, mirroring dommy-js-quickjs's own Gemfile: the fork's release tag,
# quickjs 0.22.0 plus the JS rejection hook that hands the host the promise and
# reason the page rejected with. The binding is measured against it, since the
# released gem without the hook is a different engine to the page. Drop this
# once the hook is released. Pin a tag of the fork, not a commit a rewritten
# branch could leave unreachable.
gem "quickjs", github: "takahashim/quickjs.rb", tag: "v0.22.0-rejection-hook.1",
  submodules: true # the QuickJS C sources are a submodule

if (quickjs = ENV["DOMMY_JS_QUICKJS_PATH"] || sibling("../dommy-js-quickjs"))
  gem "dommy-js-quickjs", path: quickjs
else
  gem "dommy-js-quickjs"
end
