# Copilot instructions — redmine_expert_agile

This file mirrors [`CLAUDE.md`](../CLAUDE.md). The two are intentional duplicates for different
tools — **keep them in sync when either changes.**

## What this is

A Redmine plugin (`redmine_expert_agile`, Redmine 5.0+) providing agile boards: a Kanban/Scrum
board on Redmine's query system, story points, sprints with a backlog planner, and burndown /
burnup / velocity / cumulative-flow / cycle-time charts.

It is an independent replacement for RedmineUP Agile PRO (`plugins/redmine_agile`, GPLv3). That
plugin served as a reference for behaviour only; no code was copied. This plugin is
GPL-2.0-or-later.

Developed inside the parent `redmine-expert` deployment repo (`../../`), which is **not** a
Redmine checkout — no Gemfile or `rake` at the repo root. Redmine comes from a Docker image.

## Hard rules (must follow)

1. **"expert" is always lowercase in user-facing text** — plugin name, i18n values, menu
   captions, README, CHANGELOG. Never "Expert", not even at the start of a label. Code
   identifiers keep normal casing (`ExpertAgileQuery`, `expert_agile_data`).
2. **Prefix every `app/` file, class and table with `expert_agile_` / `ExpertAgile`.** RedmineUP's
   `redmine_agile` is installed alongside and all plugins share one Zeitwerk autoload path; a
   duplicate basename means the second file silently never loads. Check
   `ls ../redmine_agile/app/<dir>` before adding a file.
3. **No acronym casing in filenames** — Zeitwerk's default inflector decides the constant.
4. **Never `docker exec`.** Use `docker-compose ... up --build` from the parent repo root.
5. **Apply patches at the bottom of `init.rb`**, guarded so they run once. Never
   `Rails.configuration.to_prepare` — Redmine already runs `init.rb` inside one, so a nested
   registration never fires in production.
5b. **Never wrap a core method with `prepend` + `super` if another installed plugin aliases it** —
   use UnboundMethod capture (`original = base.instance_method(:foo)` + `define_method` calling
   `original.bind(self).call`). RedmineUP plugins use `alias_method` pairs; a prepended `super`
   gets captured as their "original" and recurses into itself (`SystemStackError`). Already
   confirmed for `IssueQuery#available_columns`/`#issues`/`#initialize_available_filters`/
   `#joins_for_order_statement`,
   `IssuesController#parse_params_for_bulk_update`, `ProjectsHelper#project_settings_tabs`,
   `Issue#css_classes`, `Journal#css_classes`. Check with
   `grep -rn "alias_method :<name>," --include='*.rb' ../redmine_agile ../redmine_contacts*`
   before wrapping. Adding new methods is always a plain `include`.
6. **No global monkeypatching** — no mixing into `ActiveRecord::Base` or `ApplicationController`.
7. **Never touch the DB connection at load time.**
8. **No inline `<script>`.** Views render markup only; pass data via a JSON island read by a
   static asset. Must work under `script-src 'self'`.
9. **Add the next migration number; never edit a shipped migration.** Pin
   `ActiveRecord::Migration[6.1]`.
10. **Plain `def ... end`** — Redmine 5.x runs on Ruby 2.7, where endless methods are a syntax
    error.
11. **Every settings key gets a declared default in `init.rb`** — no defaults hidden in readers.
11b. **Comments explain our design on its own terms** — never describe, quote or judge how
    RedmineUP (or any other plugin) implements a feature; notes on running alongside it (aliased
    methods, name collisions, routes) are fine. Never copy its code.
12. **Code comments in English; i18n in seven languages** (`en`, `de`, `es`, `fr`, `it`, `pt`,
    `pt-BR`; every key in every file, same order as `en.yml`, enforced by
    `test/unit/locale_files_test.rb`); UI German. `CHANGELOG.md`/`README.md` are authoritative, `.de.md` are mirrors kept in sync.

## Commands

```bash
# Stack (from parent repo root)
docker-compose -f docker-compose.yml up --build

# Tests (inside a Redmine environment)
bundle exec rake redmine:plugins:test NAME=redmine_expert_agile RAILS_ENV=test
# Note the -e: the compose command reads PLUGIN from the *container's* environment, so a
# plain `PLUGIN=... docker-compose ...` prefix is ignored and the helpdesk suite runs instead.
docker-compose -f docker-compose.yml --profile test run --build --rm -e PLUGIN=redmine_expert_agile redmine-test
```

## Git and releases

Branch `type/short-desc` (Conventional-Commit types), PR into protected `main`, CI must pass,
squash-merge. Releases are tag-driven: bump `version` in `init.rb` (single source of truth),
commit, then `git tag vX.Y.Z && git push origin vX.Y.Z`. `release.yml` verifies tag == init.rb
version and builds the notes from the matching `## [<version>]` CHANGELOG section.
A final step asks the plugin website (`expertZentrale/redmine-plugins`) to rebuild via a
`plugin-released` dispatch, using the `SITE_DISPATCH_TOKEN` secret (fine-grained token, Contents
read/write on that repo only); without it the site catches up on its weekly cron, and the step
never fails a release.

Every release also updates `docs/redmine_org/` — Textile (not Markdown: `h3.`, `*bold*`, `@code@`,
`"label":url`) copy-paste sources for <https://www.redmine.org/plugins/redmine_expert_agile>, part
of the release commit:

- `releases/<version>.textile` — new file per release, user-facing changes only, derived from the
  CHANGELOG rather than copied. `h3. redmine_expert_agile <version> — <YYYY-MM-DD>`, then
  `h4. Added`/`Changed`/`Fixed`, closing with `h4. Upgrade notes`.
- `description.textile` — what the plugin is. Drifts silently because nothing forces it; read it
  end to end against the CHANGELOG since the last tag before tagging.
- `installation.textile` — install/upgrade steps, permissions, settings, RedmineUP coexistence.
  Description and installation are separate fields on redmine.org — keep them split.

`docs/redmine_org/README.md` is the full checklist; `docs/` is excluded from release archives.

## Architecture notes

- `lib/redmine_expert_agile.rb` — namespace + typed settings readers (casting only).
- Schema: `expert_agile_data` (per-issue `position` decimal, `story_points`, `sprint_id`),
  `expert_agile_sprints` (status 0/1/2, Version-style `sharing`), `expert_agile_colors`
  (polymorphic, `color` stored as `#rrggbb`; the palette is only swatches and fallbacks, and a
  coloured element carries `--ea-accent`/`--ea-tint` inline — never one CSS class per colour).
- **Positions are fractional decimals computed server-side** from
  `{issue_id, target_status_id, prev_id, next_id}`; one row written per move.
  `RedmineExpertAgile::BoardPositions` rebalances when the gap shrinks.
- `ExpertAgileQuery < Query` (STI); board settings live in the serialized `options` column.
  `ExpertAgileChartsQuery` stores `date_from`/`date_to` explicitly — never parse generated SQL.
- Charts replay history with **one** `journal_details` query projected in a single pass,
  `Rails.cache`d on a scope fingerprint. Chart.js and the Coloris colour picker are vendored
  under `assets/`, unmodified (the Coloris CSS only gains a licence header).
- Board update enforces workflow via `issue.new_statuses_allowed_to`. WIP limits are advisory.
- After saving a move the board update re-reads the status from the database and refuses the move
  if a callback put the old one back; a 200 must mean the card stays where it was dropped.
- The drop preview (`RedmineExpertAgile::MoveTargets`, rendered as `data-allowed-status-ids` on each
  card) is built from the **same** calls the update enforces with — `editable?`,
  `safe_attribute?('status_id')`, `new_statuses_allowed_to`. Plain cards share answers per
  project/tracker/status/author/assignee, so a full board costs a handful of workflow queries; cards
  with a parent, subtasks or a blocking relation are always asked through core one by one, because
  their closable/reopenable state depends on other issues. Never reimplement the workflow rules
  client-side or in a second code path: the preview must not be able to disagree with the refusal.
  The server stays authoritative; the preview only shows its answer early.
- **Swimlane drops** write the grouped field only for `ExpertAgileQuery::WRITABLE_SWIMLANES`
  (assignee, category, target version, priority), through `safe_attributes=` after the status is
  set and inside the move's transaction, then re-read it against the requested lane like the
  status. Every other lane is refused by name before anything is written. The board script sends
  `swimlane_field` on every move and `swimlane_id` only when the card left its lane; the answer
  carries `swimlaneId` and every lane's totals (`BoardGrid#swimlane_summaries`, the same numbers
  the page renders). Never add a field to the allowlist that a drag should not set (project,
  tracker, author, dates).
- **Card context menu** is Redmine's own (core `context_menu.js` via the `context_menu` helper):
  the board sits in `form#ea-board-form` with `data-cm-url` and a `back_url` field, each card is
  `.hascontextmenu` with a hidden `ids[]` checkbox, and `link_to_context_menu` gives keyboard and
  touch access. Core decides the entries, permissions and workflow — never build a menu of our own
  or filter its entries. The board script only intercepts the menu's PATCH field links
  (`/issues/:id` for one card, `/issues/bulk_update` for several) in the capture phase, sends them
  with `fetch`, and redraws from the board page the redirect to `back_url` returns (`swapBoard`:
  thead, tbody and the JSON island, keeping the table and its pinned head). A refusal is the
  edit/bulk edit form; its `#errorExplanation` is shown as text. Every other entry stays core's.
  Core leaves a right click on any link to the browser; a right click on the card's **own** links
  (`.ea-card-id`, `.ea-card-subject`) is re-dispatched on the card so the subject opens the menu,
  while links to other issues (epic, story, subtasks, field values) keep the browser's menu.
- **Epics** (`lib/redmine_expert_agile/epics.rb`): an epic is an issue of a tracker in the
  `epic_tracker_ids` setting (empty = off); an issue belongs to the nearest epic ancestor in the
  subtask tree. No table or custom field of its own. `Epics.nearest(issues, user)` answers a whole
  list from the nested set in one query and only considers epics the user may see — never walk
  `parent` per card. Cards read it through `ExpertAgileQuery#card_epic` (batch-loaded);
  `hide_epics` (default on) filters epic trackers in `board_filtered`, which counts and totals
  share.
  Epic swimlanes use `RedmineExpertAgile::EpicQueryColumn` (the one non-association lane); a drop
  writes `parent_issue_id` (`WRITABLE_SWIMLANES['epic']`), re-read from `parent_id`, and
  `Epics.lane_refusal` refuses a story's subtask and an epic by name before anything is written.
  `Epics.progress(epics, user)` aggregates the visible non-epic descendants (count, closed, story
  points) in one query; `ExpertAgileQuery#epic_progress` batches it over `epics_on_screen` (board epic
  lanes, planner epic containers). The planner's `epic` container writes `parent_issue_id` and shows
  only issues straight under an epic or under nothing.
  The sprint and version tabs carry an epic panel (`_epic_panel`, `panel_epics`: open visible epics of the
  project tree, not narrowed by the epic filter). Its entries are links that set the `expert_agile_epic_id`
  filter (`expert_agile_epic_panel_params` rebuilds the whole planner state, saved id included), and drop
  targets for `#update_epic`, which writes `parent_issue_id` with the epic tab's checks (`safe_attribute?`,
  `Epics.lane_refusal`, target must be in `panel_epics`), re-reads `parent_id` and answers whether the card
  still passes the filters (`shows_issue?`). `planner_layout` (`columns`|`list`) is a query option like
  `container_type` — a plain switch link, kept in the session, a request-only tweak on a saved planner,
  defaulting to the `planner_default_layout` setting; the list layout is CSS over the same card partial.
  Planner cards open core's context menu like board cards; `swapBacklog` redraws lanes, panel and island.
  `RedmineExpertAgile::Hierarchy` answers `children`, `parents` and `descendant_rows` (epic overview,
  `ExpertAgileEpicsController`) for a whole list in one visible-scoped query each; cards read them
  through `ExpertAgileQuery#card_story` / `#card_subtasks`, batch-loaded by `load_for_board`.
  The issue list's sprint filter (`expert_agile_sprint_id`, `active` resolved at query time) and
  column (`SprintQueryColumn`) come from `IssueQueryPatch`, and so does the epic filter
  (`expert_agile_epic_id`, while epics are on): everything below the chosen epics via the nested set,
  like `Epics.progress`, with only epics the user may see counted, also for any/none; on the
  planner's epic tab `=`/`!` also narrow the lanes (`ExpertAgileBacklogQuery#epic_lanes_filtered`). A QueryColumn grouped in SQL must
  override `group_by_statement` — core groups by the column's name otherwise — and its
  `group_value` must equal the SQL key, or the group counts come back empty. Group by a plain
  column of a joined row (`ead_group.sprint_id`, joined through `joins_for_order_statement`),
  never by a correlated subquery: MySQL's `ONLY_FULL_GROUP_BY` refuses the count, MariaDB does not.
  The epic tree on core's issue list is `RedmineExpertAgile::IssueTree`: on a list sorted by parent task
  first and not grouped (`applies?`), `view_issues_index_bottom` puts the page's epic rows (colour,
  progress) and every other row's nearest epic into the `ea-issue-tree-data` island, three queries per
  page whatever its size;
  `expert_agile_issue_tree.js` only decorates core's rows (`idnt-N` depth, tree lines, folding), never
  adds or moves one. `view_issues_sidebar_planning_bottom` links *Epics and stories* (`tree_list_params`)
  in projects with an agile module and an epic tracker — a link, not a saved query, because a public
  query is either one project's or every project's.
  Completing a sprint is `RedmineExpertAgile::SprintCompletion` (`ExpertAgileSprintsController#complete`):
  open issues move like a planner move (journaled, `manage_expert_agile_backlog`, the issue's own
  validation), then the sprint closes and the target may be activated — one transaction; a single
  refusal rolls back everything and is reported per issue. Never relax `no_open_issues_when_closing`.
