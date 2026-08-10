# redmine_expert_agile

> 🇬🇧 English version · [Deutsche Version](README.de.md)

Agile boards for Redmine: a Kanban/Scrum board built on Redmine's own query system, story
points, sprints with a backlog planner, and charts.

Requires **Redmine 5.0 or newer**. Licensed under the **GPL-2.0-or-later** (see [LICENSE](LICENSE)).

## Contents

- [Features](#features)
- [Installation](#installation)
- [Configuration](#configuration)
- [Permissions](#permissions)
- [Development](#development)
- [License](#license)

## Features

> The plugin is under active development towards its first release (0.1.0). Items below are the
> scope of that release; see [CHANGELOG.md](CHANGELOG.md) for what has landed so far.

- **Board** — columns from issue statuses, drag & drop, swimlanes, advisory WIP limits,
  configurable card fields, sub-columns via a shared status name prefix, a backlog column, and
  saved boards. Boards are Redmine queries, so every filter, grouping and visibility rule you
  already know applies.
- **Story points** — stored per issue, offered as a configurable value list (modified Fibonacci
  by default), restrictable to selected trackers, available as an issue list column and filter.
- **Sprints** — a first-class entity with start and end dates, an open/active/closed lifecycle,
  and Version-style sharing across a project tree. Redmine versions remain usable for planning
  alongside sprints.
- **Backlog planner** — drag issues into sprints or versions from a dedicated planning view.
- **Charts** — burndown, burnup, velocity, cumulative flow and cycle time, in issues, hours or
  story points.
- **Colors** — cards coloured by tracker, priority, status, assignee, project, spent time, or
  per issue.
- **REST API** — read *and* write agile data (story points, sprint assignment) plus sprint CRUD.

### Design notes

A few deliberate differences from comparable plugins, because they affect correctness:

- **Board positions are fractional decimals computed on the server.** A move sends only the
  dragged card and its two neighbours, and writes one row. Re-indexing a whole column in the
  browser corrupts ordering when two people drag at once, and silently reorders against cards
  that are paginated out of view.
- **Chart history is reconstructed in a single pass** over one `journal_details` query and
  cached, rather than re-scanning every issue's journals once per date.
- **No inline JavaScript.** Views render markup; data reaches the browser through a JSON island.
  The board works under a `script-src 'self'` content security policy.
- **No global monkeypatching** of `ActiveRecord::Base` or `ApplicationController`.

## Installation

```bash
cd /path/to/redmine/plugins
git clone https://github.com/expertZentrale/redmine_expert_agile.git
cd /path/to/redmine
bundle exec rake redmine:plugins:migrate NAME=redmine_expert_agile RAILS_ENV=production
```

Restart Redmine, then enable the **expert Agile** module (and optionally **expert Agile
Backlog**) per project under *Project settings → Modules*.

Alternatively, download a release archive from the
[Releases page](https://github.com/expertZentrale/redmine_expert_agile/releases) and unpack it
into `plugins/`.

### Running alongside RedmineUP Agile

All classes, tables and routes are prefixed, so both plugins can be installed at once. However,
both patch `Issue#safe_attributes=`, `IssueQuery` and `ProjectsHelper#project_settings_tabs`, and
RedmineUP uses `alias_method` pairs — **enabling both on the same project is not supported.**
Migrate a project by disabling one module and enabling the other.

## Configuration

*Administration → Plugins → Redmine expert Agile*. Settings are grouped into Board, Colors,
Estimates, Sprints and Charts. Every key ships with a default, so a fresh install is immediately
usable.

Two worth knowing:

- **Board item limit** (default 500) caps how many issues one board render loads.
- **Chart item limit** (default 1000) and **chart cache duration** (default 60 minutes) bound the
  cost of the history-replaying charts.

## Permissions

Granted per role under *Administration → Roles and permissions*.

| Module | Permission | Allows |
| --- | --- | --- |
| expert Agile | View agile board | Open the board, read cards |
| expert Agile | Edit agile board | Drag & drop, create and edit cards |
| expert Agile | Save agile boards | Create private saved boards |
| expert Agile | Manage public agile boards | Create and edit public saved boards |
| expert Agile | View agile charts | Open the charts page |
| expert Agile | Manage sprints | Create, edit and close sprints |
| expert Agile Backlog | View backlog | Open the backlog planner |
| expert Agile Backlog | Manage backlog | Plan issues into sprints and versions |

## Development

See [CLAUDE.md](CLAUDE.md) for the full development guide. In short, from the parent
`redmine-expert` repository root:

```bash
# Start the local stack (Redmine on :3000)
docker-compose -f docker-compose.yml up --build

# Run the plugin test suite
PLUGIN=redmine_expert_agile docker-compose -f docker-compose.yml --profile test run --build --rm redmine-test
```

Inside a Redmine environment:

```bash
bundle exec rake redmine:plugins:test NAME=redmine_expert_agile RAILS_ENV=test
```

## License

GPL-2.0-or-later. This plugin is an independent, clean-room implementation; it contains no code
from any other agile plugin.
