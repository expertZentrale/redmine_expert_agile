# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A **Redmine plugin** (`redmine_expert_agile`) providing agile boards: a Kanban/Scrum board
built on Redmine's own query system, story points, sprints with a backlog planner, and
burndown / burnup / velocity / cumulative-flow / cycle-time charts. Requires Redmine 5.0+.

It is a **clean-room replacement for RedmineUP Agile PRO** (`plugins/redmine_agile`, GPLv3,
paid per-server licence). That plugin was read for behaviour only — no code was copied, and
this plugin is GPL-2.0-or-later like its siblings.

This plugin is developed **inside the parent `redmine-expert` deployment repo** (two levels up,
`../../`), which packages plugins, themes and Docker/Kubernetes config. **This repo is NOT a
Redmine checkout** — there is no Gemfile, `rake`, or `config/database.yml` at `../../`. Base
Redmine is supplied by a Docker image; the app only exists inside the running container
(`/usr/src/redmine`), so host-level `bundle exec rake` does not work.

**Naming policy: "expert" is the company name and is always lowercase in user-facing text** —
the plugin name, i18n values, menu captions, README and CHANGELOG. Never "Expert", not even at
the start of a sentence or label. Code identifiers keep normal casing (`ExpertAgileQuery`,
`RedmineExpertAgile`, `expert_agile_data`).

**Language policy:** **code comments are English**. **i18n stays bilingual**
(`config/locales/en.yml` + `de.yml`, kept key-for-key and line-for-line in sync) and the plugin
UI is German. Docs are **English-first with a German mirror kept in sync**: `README.md` (EN) /
`README.de.md` (DE), and `CHANGELOG.md` (EN, authoritative — release notes are generated from
it) / `CHANGELOG.de.md` (DE).

## Hard rules

- **Every `app/` and table name is prefixed `expert_agile_` / `ExpertAgile`.** RedmineUP's
  `redmine_agile` is installed alongside and **every plugin's `app/` shares one Zeitwerk
  autoload path**: a duplicate basename means only the first on the path ever loads and the
  second silently does not exist (`NoMethodError`, not `NameError`). Before adding a file under
  `app/`, check `ls ../redmine_agile/app/<dir>` for the same basename.
- **Zeitwerk derives constants with the default inflector** — no acronym casing in filenames.
- **Never use `docker exec`** to run commands inside a running container (hard project rule, see
  parent `README.md`). `docker-compose` itself is fine.
- **Patches are applied directly at the bottom of `init.rb`**, guarded so they run once — *not*
  via `Rails.configuration.to_prepare`. Redmine runs `init.rb` inside a `to_prepare` callback, so
  a nested registration would never fire in production.
- **Never wrap a core method with `prepend` + `super` if another installed plugin aliases it.**
  Use **UnboundMethod capture** instead (`original = base.instance_method(:foo)`, then
  `define_method` a replacement calling `original.bind(self).call`), as
  `lib/redmine_expert_agile/patches/issue_query_patch.rb` does. RedmineUP's plugins use
  `alias_method` pairs; if our module is prepended *before* their alias runs, their
  `alias_method :foo_without_x, :foo` captures **our** method as the original, our `super`
  reaches their `foo_with_x`, which calls `foo_without_x` — back into us. The first call then
  dies with `SystemStackError`. This is not theoretical: it happened on
  `IssueQuery#available_columns` during development.

  Methods aliased by the plugins installed alongside (`redmine_agile`, `redmine_contacts`,
  `redmine_contacts_helpdesk`) — verify with
  `grep -rn "alias_method :<name>," --include='*.rb' ../redmine_agile ../redmine_contacts*`
  before wrapping anything:

  | Method | Aliased by |
  | --- | --- |
  | `IssueQuery#available_columns` | redmine_agile, redmine_contacts_helpdesk |
  | `IssueQuery#issues` | redmine_agile, redmine_contacts_helpdesk |
  | `IssueQuery#initialize_available_filters` | redmine_agile |
  | `IssuesController#parse_params_for_bulk_update` | redmine_agile |
  | `ProjectsHelper#project_settings_tabs` | redmine_agile, redmine_contacts, redmine_contacts_helpdesk |
  | `Issue#css_classes` | redmine_agile |
  | `Journal#css_classes` | redmine_contacts_helpdesk |

  `prepend` + `super` remains correct for methods nobody else touches, and adding **new** methods
  is always a plain `include`.
- **No global monkeypatching.** Colour support is a `RedmineExpertAgile::Colorable` concern
  included explicitly into the models that need it, never into `ActiveRecord::Base`; helpers are
  included where used, never into `ApplicationController`.
- **Never touch the database connection at load time.** RedmineUP's `issue_query_patch.rb` calls
  `ActiveRecord::Base.connection.tables` during class loading, which breaks `rake db:create` on
  a virgin database.
- **No inline `<script>`.** Views render markup only; Ruby→JS data crosses through a JSON island
  (`<script type="application/json" id="ea-...">`) read by a static asset. The board must work
  under `script-src 'self'`.
- **Add the next migration number when changing schema; never edit a shipped migration.**
- **Plain `def ... end`** — Redmine 5.x still runs on Ruby 2.7, where endless method definitions
  are a syntax error.
- **Every settings key gets a declared default in `init.rb`.** Do not hide defaults in reader
  methods.

## Development workflow (Docker)

Run everything from the **parent repo root** (`../../`).

```bash
# Start / rebuild the local stack (MariaDB + Redmine) — Redmine on :3000
docker-compose -f docker-compose.yml up --build
```

Migrations run automatically on container build via `REDMINE_PLUGINS_MIGRATE=1`. Code changes
take effect only after a rebuild, because the plugin is **`COPY`'d into the image** (see
`Dockerfile.dev`), not volume-mounted — a plain `restart` does not pick up edited source.

## Tests

MiniTest via Redmine's own harness; `test/test_helper.rb` loads Redmine's helper, so the suite
requires a Redmine environment.

```bash
# All plugin tests
bundle exec rake redmine:plugins:test NAME=redmine_expert_agile RAILS_ENV=test

# Single file / single test
bundle exec ruby -Itest plugins/redmine_expert_agile/test/unit/board_positions_test.rb
bundle exec ruby -Itest plugins/redmine_expert_agile/test/unit/board_positions_test.rb -n test_midpoint
```

From the parent repo root, via the compose test profile:

```bash
# Note the -e: the compose command reads PLUGIN from the *container's* environment, so a
# plain `PLUGIN=... docker-compose ...` prefix is ignored and the helpdesk suite runs instead.
docker-compose -f docker-compose.yml --profile test run --build --rm -e PLUGIN=redmine_expert_agile redmine-test
```

`test/test_helper.rb` provides `with_agile_settings(hash) { ... }` for scoping plugin settings.

## Git workflow

`main` is protected — release tags are cut only from merged `main`.

- Branch per unit of work, `type/short-desc` with Conventional-Commit types (`feat/`, `fix/`,
  `chore/`, `docs/`, `refactor/`, `test/`). Branch off latest `main`.
- Open a PR into `main`. CI (`ci.yml`, `docker-image.yml`) must pass. **Squash-merge.**
- Trivial docs/CHANGELOG-only tweaks may go straight to `main`. Anything touching Ruby/JS,
  migrations, i18n or behaviour needs a branch + PR.
- Never rewrite published history.

## Releases (tag-driven)

The version is the **single source of truth in `init.rb`** (`version '...'`): bump it and commit
first, then tag the same commit and push (`git tag vX.Y.Z && git push origin vX.Y.Z`).
`.github/workflows/release.yml` verifies that the `init.rb` version equals the tag (fails on
mismatch), builds `redmine_expert_agile-<version>.{zip,tar.gz}` from the tagged tree, and
publishes the release with notes taken from the matching `## [<version>]` CHANGELOG section.

**Every release must also update `docs/redmine_org/`** — the copy-paste sources for the listing
at <https://www.redmine.org/plugins/redmine_expert_agile>. That directory renders **Textile**, not
Markdown (`h3.` headings, `*bold*`, `@code@`, `"label":url`), so these files are written in Textile
and are pasted in unedited. The directory keeps description and installation notes in **separate
fields** — keep them split. Part of the release commit, not an afterthought:

- `docs/redmine_org/releases/<version>.textile` — new file per release. User-facing changes only;
  the CHANGELOG is the source but this is not a copy of it. House shape:
  `h3. redmine_expert_agile <version> — <YYYY-MM-DD>`, then `h4. Added`/`Changed`/`Fixed`, always
  closing with `h4. Upgrade notes` (say "No migrations. Replace the plugin directory and restart."
  when that is all it takes).
- `docs/redmine_org/description.textile` — what the plugin *is*; update when a release adds a
  feature worth listing under *Features*, drops a limitation, or changes a design note, and bump
  the Redmine versions under *Requirements* when they move. **This one drifts silently**, because
  nothing forces it the way a release forces the notes: read it end to end against the CHANGELOG
  since the last tag before tagging, not just the part you happened to touch.
- `docs/redmine_org/installation.textile` — how to install and run it; update when a release
  changes a step (new migration, new permission or project module, new setting, new gem, or a
  change to how it coexists with RedmineUP Agile).

`docs/redmine_org/README.md` is the full checklist. `docs/` is excluded from the release archives,
so none of it ships to users.

## Architecture

### Bootstrap (`init.rb`)
Requires `lib/redmine_expert_agile.rb`, registers the plugin, its settings (board, colours,
estimates, sprints, charts), the `:expert_agile` and `:expert_agile_backlog` project modules
with their permissions, menus, and applies patches at the bottom.

`lib/redmine_expert_agile.rb` is the namespace plus typed settings readers — casting only, no
fallback values, because the defaults live in `init.rb`.

### Schema (`db/migrate/`)
- `expert_agile_data` — one row per issue: `position` (decimal), `story_points`, `sprint_id`.
  Unique index on `issue_id`.
- `expert_agile_sprints` — `name`, `description`, `status` (0 open / 1 active / 2 closed),
  `start_date`, `end_date`, `sharing` (Version-style: 0 none … 4 system).
- `expert_agile_colors` — polymorphic `container` + `color`, one composite index.

### Positions
`position` is a **decimal**, not a dense integer. The client reports
`{issue_id, target_status_id, prev_id, next_id}`; the server computes the midpoint and writes a
single row inside the same transaction as the issue save.
`RedmineExpertAgile::BoardPositions` rebalances a column when the neighbour gap gets too small.
This is a deliberate departure from RedmineUP, where the browser re-indexes the whole column on
every drop — which corrupts ordering under concurrent drags and against cards paginated out of
view.

### Query layer
`ExpertAgileQuery < Query` (Redmine's `queries` table, STI). Board settings ride in the
serialized `options` column: `board_statuses`, `wip_limits` (`{status_id => [min, max]}`),
`color_base`, `swimlane_field`, `card_columns`, `board_type`, `totals`. `ExpertAgileChartsQuery`
stores `date_from`/`date_to` as explicit options — never recover a date range by parsing
generated SQL.

### Charts (`lib/redmine_expert_agile/charts/`)
History is reconstructed by **one** query over `journal_details`, projected in a single pass into
a per-issue timeline, then walked once per date bucket — `O(journals)`, not
`O(dates × issues × journals)`. Results are cached in `Rails.cache` keyed on a scope fingerprint;
past dates are immutable. Chart.js is **vendored** under `assets/javascripts`, never taken from
another plugin's asset directory.

### Workflow enforcement
The board update calls `issue.new_statuses_allowed_to(User.current)` explicitly and returns a
specific error. WIP limits are **advisory** — they flag the column, they never block a move.
