# Changelog – redmine_expert_agile

> 🇬🇧 English version · [Deutsche Version](CHANGELOG.de.md)

All notable changes to this plugin are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This file is authoritative: the release workflow generates the GitHub release
notes from the section matching the pushed tag.

## [Unreleased]

### Fixed

- **A saved board or backlog could be opened by anyone who knew its id.** Both lookups resolved
  the id straight from the table, so a private board belonging to another user opened for any
  member of the project — its name and its whole filter set, though not issue data, which
  `Issue.visible` still gates. Both now resolve through `visible` and `global_or_on_project`, the
  scope the sidebar and the query controller already used.
- **A saved board or backlog stayed open after it stopped being visible.** The session carries
  only an id and outlives the query it points at, so an owner turning a shared board private, or a
  role losing the permission, had no effect until the viewer's session happened to end. The
  session restore now resolves through the same scope and falls back to a fresh board when the
  saved one is gone or no longer visible.

### Added

- **The backlog planner has the board's filter and options panel.** The backlog tab was the one
  agile screen without one: it built a throwaway query on every request, so it always showed every
  open issue of the project and nothing a user chose survived a page reload. It now carries the
  same panel the board does — Redmine's own filter widget, a collapsible *Options* fieldset with
  card fields and colouring, and Apply / Clear / Save — persisted in its own session key so
  coming back via the project menu shows the backlog as it was left. There is no status-column or
  WIP part: the planner deliberately ignores where an issue sits in the workflow.
- **Saved backlogs.** A backlog can be saved, edited and deleted like a board or a chart, and
  saved backlogs are listed in the agile sidebar, which the backlog tab now renders. They are
  `ExpertAgileBacklogQuery` rows in Redmine's `queries` table, visible through the
  `view_expert_agile_backlog` permission rather than the board's, and
  `ExpertAgileBacklogQueriesController` is the board's query controller pointed at that class —
  the same reuse the charts variant already uses. Saving needs `add_expert_agile_queries`, which
  lives in the `expert_agile` module, so a project running the backlog module alone can filter but
  not save.
- **Backlog cards show the fields the panel selects.** They were a fixed set of id, tracker,
  subject, status and story points; they now render the assignee and avatar, estimated hours, done
  ratio, the description excerpt and any selected column including custom fields, exactly as a
  board card does.

### Fixed

- **A chart saved from its own screen was stored as a board.** `expert_agile_queries/new` and
  `edit` hardcoded the board's routes, so every variant of the query controller posted its form to
  `ExpertAgileQueriesController` regardless of which screen it came from. Where the shared form
  posts, and what it is titled, is now the controller's business. The charts variant had no Save
  link in the UI, so this only ever bit the API; the backlog would have hit it on the first click.

- **Screenshots in both READMEs.** `README.md` and `README.de.md` now open a *Screenshots* section
  covering the board with its sub-columns and WIP limits, swimlanes, the backlog planner, the
  sprint list, story points on the issue form, burndown, velocity, cumulative flow, the card
  colours screen and the plugin settings — so the plugin can be evaluated without installing it
  first. The images live in `docs/screenshots/{en,de}/` and, like the rest of `docs/`, are excluded
  from the release archives, so the installable package does not grow.
- **`scripts/seed_screenshot_demo.rb` and `scripts/teardown_screenshot_demo.rb`** build and remove
  the synthetic demo project the screenshots are taken from: five sprints across the
  open/active/closed lifecycle, ~130 issues with backdated status journals so the
  history-replaying charts have something to replay, story points, board positions, time entries,
  card colours and three saved boards. Unlike their helpdesk counterparts these scripts do write
  global state — story points and sprints are off by default and neither feature is visible
  otherwise — so the seed records every value and every row id it touches in an
  `expert_agile_screenshot_backup` setting and the teardown restores the instance from it.
  `RELABEL=de` renames the demo statuses between the English and the German capture pass, so both
  screenshot sets share one dataset. Both scripts refuse to run without `DEMO_STACK=1`: they boot
  under the official Redmine image, which runs in production mode, so `Rails.env` cannot tell a
  disposable database from a real one and the opt-in has to be typed.

### Fixed

- **"Show future data on charts" did nothing.** The setting was declared, documented in the
  settings screen and read by `RedmineExpertAgile.chart_future_data?`, but no chart ever consulted
  it: every series was drawn to the end of the selected range, so a burndown looked at mid-sprint
  ran flat from today to the sprint end and a velocity chart showed empty buckets for weeks that
  have not happened. Measured series (`:actual`, `:total`, `:created`, `:closed`, `:trend`) now
  stop at today unless the setting is on, while the ideal line — a projection, not a measurement —
  still spans the whole range. An interval bucket that merely *contains* today is kept, because a
  week is legitimately partial on the day you look at it.
- **Cumulative flow bands were indistinguishable.** The band colour was a hue derived from the
  status's index among *all* of the instance's statuses, so on an installation with fifty statuses
  a six-band chart drew six neighbouring hues — six shades of the same pink, one on top of the
  other. The palette is now spread over the bands the chart actually draws, so the bands are as far
  apart on the colour wheel as they can be.
- **Untranslated column header on the card colours screen.** The table header called
  `l(:label_name)`, a key neither the plugin nor Redmine defines, so the admin screen rendered
  "Translation missing: en.label_name". It now uses Redmine's own `field_name`.
- **The documented test command ran the wrong plugin.** Both READMEs put `PLUGIN=` in front of
  `docker-compose … run`, where it stays a shell variable and never reaches the container — the
  service fell through to its default and the helpdesk suite ran instead, reporting a clean 417
  green tests while the agile suite was never executed. The command now passes `-e PLUGIN=…`.

## [0.1.9] - 2026-08-11

### Fixed

- **Backlog lanes overlapped each other.** The board's fixed 300px column width was written as an
  unscoped `.ea-cell` rule, and the backlog reuses that class — so every drop zone rendered 314px
  wide inside a 280px lane and spilled over its neighbour. The width now belongs to the board's
  table, and the plugin's boxes size with `border-box`.

### Changed

- **The backlog planner looks like a planning tool.** The sprint/version switch is a segmented
  control rather than two bare links. A sprint lane shows its status, its date range and the days
  left, so you can tell which sprint is running without leaving the page; a version lane shows its
  date. The unplanned column is dashed to mark it as the source rather than a target, lanes carry
  the same accent colour they have on the board, an empty lane says what to do with it, and each
  lane scrolls internally so a large backlog no longer makes the page thousands of pixels tall.

### Added

- Controller tests for the backlog planner, which had none: lane structure, exactly one drop
  target per lane, container ids, totals, the sprint metadata, module and permission gating, and
  planning an issue into and back out of a sprint.

## [0.1.8] - 2026-08-11

### Changed

- **The board options panel is compact.** Three stacked fieldsets — one of them Redmine's
  two-list-with-arrows column picker, about 400px tall on its own — are now a single panel of
  three side-by-side groups that wrap on narrow screens: card fields, appearance, and columns with
  their WIP limits. Opening the options costs 279px instead of pushing the board most of a screen
  down, and every setting is visible at once.
- **Card fields are a checkbox grid.** Ordering columns matters in a table and much less on a
  card, so the space the arrow picker spent on ordering now shows every available field, custom
  fields and description included, in two dense columns. Selections still post as `c[]`, so
  Redmine's own parameter handling is unchanged.

  Note this drops the ability to *order* card fields; they now follow Redmine's own column order.
- Status columns and their WIP limits are a three-column grid with closed statuses in italic, so
  the "done" column is easy to spot. Long field names carry a tooltip, and both scrollable lists
  fade at the bottom edge so a half-visible row reads as "more below" rather than as a glitch.

## [0.1.7] - 2026-08-11

### Fixed

- **Every issue page returned a 500.** The issue form hook asked a guard method that had never
  been written, so opening any issue — including clicking a card on the board — failed with
  `undefined method 'sprint_visible?'`. The guard now exists and shows the sprint selector only
  when sprints are switched on and the project has one to plan into.
- **The plugin's view hooks are now covered by tests that render Redmine's own pages** — issue
  show, edit, new, bulk edit and the issue list, with the module on and off and with sprints and
  story points enabled. The whole plugin suite passed throughout this outage because nothing had
  ever rendered a core page with the plugin loaded; a hook that breaks a core page is the one
  failure a plugin most needs to catch.

## [0.1.6] - 2026-08-11

### Added

- **More card fields.** Created and updated were already selectable; the card picker now also
  offers **time in status** — whole days since the issue last changed status, answered from one
  grouped journal query for the whole board rather than a lookup per card — and a **short excerpt
  of the description**, whose length is configurable in the plugin settings. Description is a
  block column in Redmine, so the options panel now exposes block columns the way Redmine's own
  query form does.
- The excerpt is plain text: HTML and wiki markup are stripped rather than rendered, because a
  card is a summary and full markup drags headings, tables and images into it. Descriptions
  ingested from email are mostly HTML, so this matters in practice.

### Fixed

- **A setting added in a later version never took effect on an existing installation.** Redmine
  hands back the stored settings hash wholesale once the settings form has been saved even once,
  so a newly declared key is simply absent and reads as nil — which for a numeric setting becomes
  0. The declared defaults are now merged underneath the stored values, so a stored value still
  wins (including a deliberately blank one) while new keys get their default. This is what made
  the description excerpt collapse to its 20-character floor.

## [0.1.5] - 2026-08-11

### Fixed

- **Swimlanes did not read as lanes.** Each lane was a table row with a narrow label cell on the
  left, so nothing tied the row together across the columns. A lane is now a band spanning the
  full width of the board, with the lane name and its own issue and story point totals. On a
  board wide enough to scroll, the lane name stays pinned while the columns move underneath it.
- **Every lane looked the same.** Lanes now carry an accent colour. A lane whose value can be
  coloured — a tracker, priority or status — uses that colour, so the band matches its cards and
  grouping by priority gives the expected calm-to-red ramp; anything else gets a stable palette
  entry derived from its id.

## [0.1.4] - 2026-08-10

### Added

- **Sidebar on the agile pages.** The board and the charts page now carry a sidebar in the same
  shape as Redmine's issue list: quick links between board, charts and backlog, the saved boards
  (or saved charts) split into "My queries" and shared ones, and the project's sprints with a
  link to create another. Switching between views is a single click.
- **Saved charts.** `ExpertAgileChartsQueriesController` — like the board's, its routes and
  permissions had existed since the first commit with no controller behind them. A chart's
  selection, unit, interval and date range are saved with it. It is the board's query controller
  pointed at a different class rather than a second copy.

### Fixed

- **Saving a chart was refused with 403.** Only `:index` was mapped for the charts-query
  controller, and `find_optional_project` authorises the controller/action pair — so every other
  action was denied by default rather than by intent.
- **The "save board" link went to the wrong route.** It pointed at the collection path, which is
  `#index` and simply redirects back to the board, silently discarding the configuration being
  saved. It now posts to the `new` action, as Redmine's own query form does.
- **Saved charts no longer appear among the saved boards.** `ExpertAgileChartsQuery` is a
  subclass of `ExpertAgileQuery`, so an unqualified lookup listed both; the sidebar filters on the
  exact type.

## [0.1.3] - 2026-08-10

### Fixed

- **Board options were lost on the next page load.** Statuses, WIP limits, swimlanes and the
  colour basis lived only in the URL, so setting a WIP maximum and then reloading — or simply
  returning to the board from the project menu — silently reverted everything. The board now
  remembers its configuration in the session, exactly as Redmine's own issue list does. Only what
  is needed to rebuild the board is stored, not the whole options blob.
- **Anyone able to save a board could edit and delete other people's private boards.**
  `editable_by?` checked only the "save boards" permission and ignored ownership entirely. It now
  mirrors Redmine's own rule: your own boards are yours, public project boards need the manage
  permission, and global boards stay admin-only.
- **Saving a board never worked**: the controller assigned `safe_attributes`, which `Query` does
  not implement, so creating one raised. Name, description and visibility are now assigned
  explicitly, and visibility is only assignable with the manage permission — a user without it
  gets a private board rather than a public one, matching Redmine.

### Changed

- Board display state is session-backed, but what a **move** is permitted to do still comes only
  from the request and the issue's own workflow — never from the session.

## [0.1.2] - 2026-08-10

### Added

- **Board options panel.** The board now carries the same collapsible filter and options panel as
  every other Redmine list, so a board is configured where it is used rather than only in the
  global settings. It offers Redmine's own filter widget, and lets you choose which statuses
  become columns (closed ones included, for the "done" column), per-column WIP limits, the
  swimlane field, the colour basis, whether to show the assignee's avatar, and which fields appear
  on the cards.
- **Card fields are the query's own columns**, so anything Redmine can show in the issue list —
  including custom fields — can be put on a card, rendered by Redmine's own column formatting.
- **Saved boards.** `ExpertAgileQueriesController` was declared in the routes and permissions from
  the start but had never been written, so saving a board 404'd. Boards can now be saved, edited
  and deleted, private or public according to the agile permissions.
- **Assignee avatars on cards**, on by default and switchable per board.

### Fixed

- **Setting a WIP limit crashed the board with a 500.** `ActionController::Parameters` is not a
  Hash and does not implement `each_with_object`; the model tests passed plain hashes and never
  exercised a real request. The setters now accept both, and the options panel is covered by
  controller tests that go through actual request parameters.

## [0.1.1] - 2026-08-10

### Fixed

- **The board showed every open status in the instance, not the project's own.** On a real
  installation that meant 37 columns of which 3 were used, each squeezed to about 27 pixels wide,
  with card text wrapping one character per line. Columns now come from Redmine's
  `Project#rolled_up_statuses` — the statuses the project's trackers can actually reach.
- **Cards were never coloured unless an administrator had assigned every colour by hand.**
  Choosing a colour basis appeared to do nothing. A container with no explicit colour now falls
  back to a stable palette entry derived from its id, so a board is colour-coded immediately;
  an explicit colour still wins. Colouring *by issue* deliberately keeps no fallback, since there
  the point is that only marked issues stand out.
- **Priorities are coloured on a semantic ramp** (calm to red) derived from their position in the
  enumeration, rather than an arbitrary palette entry, so "urgent" actually looks urgent.
- **Card text overflowed and columns were uneven.** Long subjects, URLs and compound words now
  break inside the card, subjects clamp to three lines, and every column is pinned to the same
  width with the board scrolling sideways instead of squeezing.
- **The backlog planner had no menu entry**, its cards were not coloured like the board's, and a
  project with no sprints showed an empty page with no explanation. It now appears in the project
  menu, colours cards consistently, and offers to create the first sprint.
- **Column headers are tinted by status** when status colours are enabled.
- **Two chart labels rendered as "Translation missing"** — the date range used Redmine core keys
  that do not exist in the German locale. The charts page also highlighted the board's menu item
  instead of its own.

### Changed

- Card and column styling reworked: larger columns, clearer card hierarchy, status and story
  point chips, hover states.

## [0.1.0] - 2026-08-10

### Added

- **Plugin skeleton.** Registration, plugin settings with a declared default for
  every key, the `expert_agile` and `expert_agile_backlog` project modules with
  their permissions, the schema (`expert_agile_data`, `expert_agile_sprints`,
  `expert_agile_colors`), routes, English and German locales, and the CI,
  Docker smoke-test and release workflows.
- **Story points.** A story point value per issue, stored in `expert_agile_data` rather than as
  a custom field. The field appears on the issue form, in the issue attribute table and in the
  bulk edit form, and is offered either as a configurable value list (modified Fibonacci by
  default) or as free numeric entry. It can be restricted to selected trackers. Parent issues
  additionally show the total across their subtree, and "not estimated" stays distinguishable
  from "estimated as zero".
- **Story points on the issue list.** A sortable `story_points` column and an integer filter on
  the core issue query. Issues with no agile data row correctly count as having no story points,
  so `is not` and `none` include them instead of silently dropping them.

- **Saved agile boards.** `ExpertAgileQuery` subclasses Redmine's own `IssueQuery`, so every
  issue filter, column, visibility rule and project scope applies to a board unchanged, and a
  saved board is a single row in the `queries` table with no extra schema. The board's own
  settings — visible status columns, WIP limits, colour basis, swimlane field, card fields, board
  type, sprint and backlog flags — ride in the serialized options, with typed accessors so the
  stored shape lives in one place. WIP limits are stored as integer pairs rather than a
  `"2-7"` string that has to be re-parsed on every render.
- **Board columns and swimlanes.** Columns are plain `BoardColumn` value objects carrying issue
  count, estimated hours, story points and WIP state; statuses sharing a `Prefix:` naming prefix
  expose a `path` for sub-column headers. Swimlanes reuse Redmine's grouping and are derived from
  the loaded cards, so a lane only appears when it holds one. The whole board is built from a
  single issue load, and a board that hits its item cap reports it rather than looking complete.

- **The board itself.** Columns from issue statuses, drag & drop between and within columns,
  swimlanes, sub-column headers from a shared `Prefix:` status naming, advisory WIP limits, card
  tooltips, and a project menu entry next to the Gantt chart. Card markup contains no inline
  script and no inline event handlers, and the board reads its configuration from a JSON island,
  so it works under a `script-src 'self'` content security policy.
- **Server-computed fractional card ranks.** A move sends only the dragged card and its two
  neighbours; the server computes the midpoint and writes exactly one row, inside the same
  transaction as the issue save. Concurrent drags in the same column no longer overwrite each
  other, and dragging inside a column that is paginated no longer reorders the cards below the
  fold. When repeated drops into one gap exhaust the available precision the column is re-spread
  automatically.
- **Explicit workflow enforcement on the board.** A move to a status the workflow forbids is
  rejected with a specific error and changes nothing, rather than being inferred from an
  attribute assignment that silently did not stick.

- **Card colours.** Cards can be coloured by tracker, priority, status, project, assignee, spent
  time, or per issue, from a closed nine-colour palette chosen so the card text stays readable.
  Colours for trackers, priorities and statuses are managed from a new admin screen; per-issue
  colours appear on the issue form when a board colours by issue. Colour support is a concern
  included into the five models that can be coloured, not mixed into `ActiveRecord::Base`, and the
  admin screen resolves its target class through a whitelist rather than constantizing a request
  parameter.

- **Sprints.** A first-class sprint with a name, description, start and end date, an
  open/active/closed lifecycle and Version-style sharing across a project tree. Activating a
  sprint stands the project's other active sprint down, a sprint cannot be closed while it still
  holds open issues, and overlapping sprints are rejected unless explicitly allowed. Sprints are
  managed from a project settings tab and a full CRUD screen, assignable from the issue form,
  and exposed over the REST API. Deleting a sprint unassigns its issues rather than deleting
  them. Sprint changes are written into the issue's own journal, so a re-plan shows up in the
  issue history alongside the other changes of that edit.

- **Backlog planner.** A separate planning view, behind its own `expert Agile Backlog` module,
  showing an unplanned backlog alongside one lane per sprint or per version. Issues are dragged
  into a lane with the same server-computed ranking the board uses, lane totals update in place,
  and the backlog can be searched by subject or issue id. Planning into sprints and into versions
  is one parameterised query rather than two near-identical ones, and the drag & drop behaviour is
  the same implementation as the board's. A container id that the project may not plan into is
  rejected, so a crafted request cannot move an issue into an unrelated project's sprint.

- **Charts.** Burndown, burnup, cumulative flow, velocity and cycle time, in issues, hours or
  story points, over a day, week or month interval. Historical state is reconstructed from one
  query over the journals, projected in a single pass into a per-issue timeline and answered by
  binary search, so the cost is proportional to the number of journal entries rather than to
  dates x issues x journals. Computed series are cached on a fingerprint of everything that could
  change them. The item cap applies only to the charts that actually replay history; the counting
  charts are unbounded because they are cheap. Chart.js is vendored with the plugin rather than
  borrowed from another plugin's asset directory, and dates are converted to the reader's own
  timezone so a chart is not off by one for anyone east of UTC.

- **REST API.** Agile data per issue is readable *and writable* — story points and sprint
  assignment can be set directly rather than only through nested attributes on the issue endpoint
  — plus full sprint CRUD. A sprint id is resolved against the sprints the issue's project may
  actually plan into, so a foreign id is rejected instead of written in. Board rank is
  deliberately read-only: ranks are computed by the server from a card's neighbours, and letting a
  client post one would reintroduce the concurrency problem the design avoids. Documented in
  `API.md`.

### Fixed

- **Core method wrapping no longer recurses infinitely** when RedmineUP plugins are installed.
  `IssueQuery#available_columns`, `#initialize_available_filters` and
  `IssuesController#parse_params_for_bulk_update` are wrapped by UnboundMethod capture instead of
  `prepend` + `super`: those plugins patch the same methods with `alias_method` pairs, which
  captures a prepended method as its own "original" and dies with `SystemStackError` on the first
  query.
