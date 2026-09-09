# frozen_string_literal: true

require "pathname"

ROOT = Pathname.new(__dir__)
RESULTS = ROOT.join("results")

# dommy and the engine binding come from sibling checkouts, or from the
# environment. Nothing here pins a version: this repo measures whatever it is
# pointed at.
def checkout(env_var, *candidates)
  ENV[env_var] || candidates.map { |c| ROOT.join(c).to_s }.find { |c| File.directory?(File.join(c, "lib")) }
end

DOMMY_PATH = checkout("DOMMY_PATH", "../dommy/gems/dommy", "../dommy")
QUICKJS_PATH = checkout("DOMMY_JS_QUICKJS_PATH", "../dommy-js-quickjs", "../takahashim/dommy-js-quickjs")

def runner_env
  {"DOMMY_PATH" => DOMMY_PATH, "DOMMY_JS_QUICKJS_PATH" => QUICKJS_PATH}.compact
end

def filter_args
  ENV["FILTER"] ? ["--filter", ENV["FILTER"]] : []
end

desc "Run every case in both engines and report the differences"
task oracle: ["oracle:chromium", "oracle:dommy", "oracle:diff"]

namespace :oracle do
  desc "Run the cases in headless Chromium (Playwright)"
  task :chromium do
    sh "node", ROOT.join("runner/chromium.js").to_s, *filter_args
  end

  desc "Run the cases through dommy + dommy-js-quickjs"
  task :dommy do
    abort "no dommy checkout found — set DOMMY_PATH" unless DOMMY_PATH
    sh runner_env, RbConfig.ruby, ROOT.join("runner/dommy.rb").to_s, *filter_args
  end

  desc "Diff the results already in results/ (no re-run)"
  task :diff do
    sh RbConfig.ruby, ROOT.join("runner/diff.rb").to_s
  end

  desc "Show where this run resolves dommy and the engine binding from"
  task :where do
    puts "dommy:            #{DOMMY_PATH || "(installed gem)"}"
    puts "dommy-js-quickjs: #{QUICKJS_PATH || "(installed gem)"}"
    puts "chromium:         #{ENV["PLAYWRIGHT_BROWSERS_PATH"] || "(playwright default)"}"
  end
end

task default: :oracle
