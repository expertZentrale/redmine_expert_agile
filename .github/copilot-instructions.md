# Copilot instructions — redmine_expert_agile

This file mirrors [`CLAUDE.md`](../CLAUDE.md). The two are intentional duplicates for different
tools — **keep them in sync when either changes.**

## What this is

A Redmine plugin (`redmine_expert_agile`, Redmine 5.0+) providing agile boards: a Kanban/Scrum
board on Redmine's query system, story points, sprints with a backlog planner, and burndown /
burnup / velocity / cumulative-flow / cycle-time charts.

It is a clean-room replacement for RedmineUP Agile PRO (`plugins/redmine_agile`, GPLv3). That
plugin was read for behaviour only; no code was copied. This plugin is GPL-2.0-or-later.

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
   confirmed for `IssueQuery#available_columns`/`#issues`/`#initialize_available_filters`,
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
12. **Code comments in English; i18n bilingual** (`en.yml` + `de.yml` key-for-key in sync); UI
    German. `CHANGELOG.md`/`README.md` are authoritative, `.de.md` are mirrors kept in sync.

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
  (polymorphic).
- **Positions are fractional decimals computed server-side** from
  `{issue_id, target_status_id, prev_id, next_id}`; one row written per move.
  `RedmineExpertAgile::BoardPositions` rebalances when the gap shrinks.
- `ExpertAgileQuery < Query` (STI); board settings live in the serialized `options` column.
  `ExpertAgileChartsQuery` stores `date_from`/`date_to` explicitly — never parse generated SQL.
- Charts replay history with **one** `journal_details` query projected in a single pass,
  `Rails.cache`d on a scope fingerprint. Chart.js is vendored under `assets/javascripts`.
- Board update enforces workflow via `issue.new_statuses_allowed_to`. WIP limits are advisory.
