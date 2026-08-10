# Changelog – redmine_expert_agile

> 🇬🇧 English version · [Deutsche Version](CHANGELOG.de.md)

All notable changes to this plugin are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This file is authoritative: the release workflow generates the GitHub release
notes from the section matching the pushed tag.

## [Unreleased]

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
