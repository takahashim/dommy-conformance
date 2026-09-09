# frozen_string_literal: true

# The Web Platform Tests corpus, run against dommy the way a browser runs it:
# the file is loaded as the document and its own <script> tags boot through the
# normal resource/script pipeline, with testharness.js served from wpt/.
#
# Engine-agnostic. Dommy::Browser picks whichever JS runtime binding has
# registered itself, so the same corpus measures any of them; require the
# binding you want before running (runner/wpt.rb does that from ENGINE).
require_relative "wpt/result"
require_relative "wpt/resources"
require_relative "wpt/runner"

module DommyConformance
  module Wpt
  end
end
