# capybara-bench

How long a feature-spec suite takes, and how much memory it needs, with each
Capybara driver a Ruby project would choose between:

- **rack_test**: Capybara's default. No JavaScript.
- **dommy**: capybara-dommy. No JavaScript.
- **dommy_js**: capybara-dommy with `javascript: true`. Page scripts run in QuickJS.
- **cuprite**: headless Chrome over CDP, with Ferrum's defaults.
- **cuprite_tuned**: cuprite with `FERRUM_INTERMITTENT_SLEEP=0.01`. See
  "Reading the numbers".

```
(cd script/capybara-bench && npm install)    # the Turbo and Stimulus bundles the app serves
rake bench:capybara                          # or: ruby -rbundler script/capybara-bench/run.rb
rake bench:capybara DRIVERS=dommy_js,cuprite,cuprite_tuned ROUNDS=9 FILTER=turbo
```

The directory has its own `Gemfile` for cuprite and puma. dommy, dommy-rack and
capybara-dommy come from `DOMMY_PATH`'s `gems/` directory, and
dommy-js-quickjs from `DOMMY_JS_QUICKJS_PATH`, the same as for the rest of the
repo. The report is printed as Markdown and written to
`results/capybara-bench.{json,md}`.

## The app and the scenarios

`app.rb` is a small server-rendered Rack app:

- plain pages: a list, item pages, a form that re-renders with errors and
  redirects on success, and a 500-row table;
- `/hw` pages, the Hotwire flavour a new Rails app ships with: the real Turbo 8
  and Stimulus 3 bundles from npm, plus `controllers.js`.

`scenarios.rb` holds nine scenarios written in the plain Capybara DSL. Each
one asserts as it goes, so a driver that renders a page wrong fails the
scenario instead of finishing it early.

| scenario | what it does | JS |
|---|---|---|
| browse | 10 round trips list → item → list via links | |
| form | submit empty (errors), fill, select, check, submit (redirect) | |
| table | 500 rows: count them, 20 `within` lookups, collect a column | |
| table-all | the same, counting with `visible: :all` | |
| stimulus | click a counter 10×, toggle a hidden panel, filter a list while typing | ✓ |
| turbo-drive | the browse scenario under Turbo Drive | ✓ |
| turbo-frame | 10 links that navigate a `<turbo-frame>` only | ✓ |
| turbo-form | the form scenario through Turbo: a 422 render, then a 303 | ✓ |
| fetch | a Stimulus action that fetches JSON and renders 50 items | ✓ |

## What is measured

- **Time.** Each driver runs in its own process. Each scenario runs once to
  warm up, then 5 times (`ROUNDS`). The table shows the median. A
  `session.reset!` runs between runs, as between examples in a suite.
  - `all it ran, incl. resets` is the sum of the medians plus the resets, over
    the scenarios that driver supports.
  - Totals are only comparable across drivers that ran the same scenarios.
- **Startup.** The first visit, including the browser launch and the
  in-process puma for cuprite.
- **Peak memory.** The peak RSS of the Ruby process plus every process it
  started, sampled every 50 ms. That includes Chrome's renderer, GPU and
  utility processes for cuprite. Every driver's process loads the same gems
  (about 80 MB), so differences between drivers are what each one adds.

## Reading the numbers

- **dommy_js versus dommy.** dommy_js also pays for JavaScript on pages that
  have none: each page boots a QuickJS runtime and installs the window.
  Compare `browse` under `dommy` and under `dommy_js`.
- **cuprite and Turbo Drive.** Turbo renders a page it has cached twice: first
  the cached preview, then the fresh response. A node cuprite already holds is
  gone after the swap. Ferrum treats that as an intermittent error and retries
  up to `FERRUM_INTERMITTENT_ATTEMPTS` (6) times, `FERRUM_INTERMITTENT_SLEEP`
  (0.1 s) apart, before Capybara looks the node up again. That is about 0.5 s
  per stale node, while the page itself is right after about 70 ms.
  - A cuprite suite on a Turbo app with default settings pays this cost, so the
    `cuprite` column keeps it.
  - `cuprite_tuned` shortens the sleep, so the two columns show what that
    setting is worth (on `turbo-drive`, roughly 7.1 s against 2.8 s).
- **table against table-all.** Capybara checks each node it counts for
  visibility. A browser driver pays one round trip per check, so `table`
  against `table-all` shows what that costs each driver. Counting hundreds of
  visible nodes is heavier than most suites do.
- **Machine dependence.** Everything is wall time on the machine running it.
  Compare drivers within one run, not runs across machines.
