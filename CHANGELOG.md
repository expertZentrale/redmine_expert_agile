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

### Fixed

- **Core method wrapping no longer recurses infinitely** when RedmineUP plugins are installed.
  `IssueQuery#available_columns`, `#initialize_available_filters` and
  `IssuesController#parse_params_for_bulk_update` are wrapped by UnboundMethod capture instead of
  `prepend` + `super`: those plugins patch the same methods with `alias_method` pairs, which
  captures a prepended method as its own "original" and dies with `SystemStackError` on the first
  query.
