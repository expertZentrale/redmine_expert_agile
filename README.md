# redmine_expert_agile

> 🇬🇧 English version · [Deutsche Version](README.de.md)

Agile boards for Redmine: a Kanban/Scrum board built on Redmine's own query system, story
points, sprints with a backlog planner, and charts.

Requires **Redmine 5.0 or newer**. Licensed under the **GPL-2.0-or-later** (see [LICENSE](LICENSE)).

## Contents

- [Features](#features)
- [Screenshots](#screenshots)
- [REST API](API.md)
- [Installation](#installation)
- [Configuration](#configuration)
- [Permissions](#permissions)
- [Development](#development)
- [License](#license)

## Features

- **Board** — columns from issue statuses, drag & drop, swimlanes, advisory WIP limits,
  configurable card fields, sub-columns via a shared status name prefix, a backlog column, and
  saved boards. Boards are Redmine queries, so every filter, grouping and visibility rule you
  already know applies.
- **Story points** — stored per issue, offered as a configurable value list (modified Fibonacci
  by default), restrictable to selected trackers, available as an issue list column and filter.
- **Sprints** — a first-class entity with start and end dates, an open/active/closed lifecycle,
  and Version-style sharing across a project tree. Redmine versions remain usable for planning
  alongside sprints. A board can be narrowed to one sprint, or follow whichever sprint is active.
- **Backlog planner** — drag issues into sprints or versions from a dedicated planning view, with
  the same filters, card fields and saved queries as the board.
- **Charts** — burndown, burnup, velocity, cumulative flow and cycle time, in issues, hours or
  story points.
- **Colors** — cards coloured by tracker, priority, status, assignee, project or spent time.
  Any colour can be picked, with 18 palette shades offered as swatches.
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

## Screenshots

All screenshots show a demo project with synthetic data, built by
`scripts/seed_screenshot_demo.rb`.

### Board

Columns are issue statuses and cards are dragged between them. Statuses sharing a prefix —
`Dev: Review` and `Dev: Test` — are merged under one header, and a column over its WIP limit
flags itself.

![Agile board with five status columns: To do, In Progress, a merged Dev header spanning the
Review and Test sub-columns, and Done. Each column header carries its card count and WIP limit,
Review is highlighted for holding five cards against a limit of four, and the cards show issue
id, tracker, subject, assignee, story points and percent done](docs/screenshots/en/01-board.png)

Any field the query can group by becomes a swimlane, so the same board can be read per assignee,
per tracker or per priority.

A board carries its subprojects' issues, and the global board carries everything — so whether a
card may be dragged is a question about that card's own project, not about the one whose board is
on screen. A card from a project where you may not move cards is shown but not draggable.

A board worth keeping is saved from the options panel and reopened from the sidebar. Editing a
saved board opens the same panel it was created with, so its filters, card fields, swimlanes,
colouring, status columns and WIP limits can all be changed — and Edit takes whatever is currently
applied along with it, so it opens the board as it is on screen rather than as it was last saved.

![The same board grouped into swimlanes by assignee: one labelled band per team member plus a
band for unassigned issues, each spanning all five status columns](docs/screenshots/en/02-board-swimlanes.png)

### Story points

Story points are a column of the plugin's own table, not a custom field, and are offered as a
fixed scale on the issue form next to the sprint the issue belongs to.

![Issue form showing Redmine's own attribute fields above two fields added by the plugin: a Story
points dropdown set to 5 and a Sprint dropdown set to Sprint 24](docs/screenshots/en/05-story-points.png)

### Sprints

Sprints are dated containers with their own lifecycle — open, active, closed — managed in the
project settings. A project runs one active sprint at a time.

![Sprints tab in the project settings listing five sprints with their status, start and due date:
one active, one open and three closed](docs/screenshots/en/04-sprints.png)

A board becomes a sprint board through the **Sprint** selector in its options panel: pick one
sprint, or *Active sprint* to follow whichever sprint is running, so a saved sprint board never
has to be re-pointed when the next iteration starts. Columns, counts and totals then cover only
that sprint's issues. The same works from a link — `…/expert_agile/board?set_filter=1&sprint_id=41`
or `sprint_id=active`. Only sprints the project may plan into are accepted; any other id, or
*Active sprint* while none is running, shows an empty board rather than every issue.

### Backlog planner

The planner puts the unplanned backlog next to the sprints it can be dragged into, each lane
totalling its issue count and story points. A second tab plans into Redmine versions instead.

It carries the same filter and options panel as the board: Redmine's own filter widget, the card
fields and colouring, and Apply / Clear / Save. What is applied is kept in the session, so coming
back to the planner shows it as it was left, and a planner worth keeping can be saved and reopened
from the sidebar. There are no status columns or WIP limits here — the planner ignores where an
issue sits in the workflow, since an issue is planned or it is not.

![Backlog planner with a Sprints and a Versions tab: a Backlog lane on the left and one lane per
available sprint beside it, each headed by its issue count, story point total, date range and
days remaining](docs/screenshots/en/03-backlog.png)

### Charts

Burndown and burnup replay the issue history from the journals. Measured lines stop at today; the
ideal line runs to the end of the range.

![Burndown chart over a sprint in story points: the remaining line descends from 200 points and
stops at today, above a dashed grey ideal line falling to zero at the sprint end. The sidebar
lists the saved charts and the project's sprints](docs/screenshots/en/06-chart-burndown.png)

![Velocity chart as grouped bars per week, comparing issues created against issues closed over
the last sixty days](docs/screenshots/en/07-chart-velocity.png)

![Cumulative flow chart: seven stacked bands, one per issue status, growing over sixty days from
five to a hundred and twenty-five issues](docs/screenshots/en/08-chart-cumulative-flow.png)

### Colours

Cards take their colour from their tracker, status, priority, assignee, project or spent-time
ratio — from what an issue is, never one issue at a time. The mapping is administered centrally.

Each colour is picked with a [Coloris](https://coloris.js.org/) picker: a colour area, a hue
slider and a hex field, with the plugin's 18 palette shades offered as swatches. Any colour works.
A card shows it as its left border and a pale tint of it as its background, and the tint stays
light enough to read the card's text on whatever was picked. Anything without a colour of its own
(assignees, and trackers or statuses nobody has coloured yet) still gets a stable palette shade.

![Card colours administration screen, Status tab: each status beside a hex field showing its
colour, with the picker open on In Progress — colour area, hue slider, the hex value and eighteen
palette swatches](docs/screenshots/en/09-card-colors.png)

### Configuration

![Plugin settings with five sections — Board, Colors, Estimates, Sprints and Charts — holding the
default card fields, board item limit, colour base, estimation unit, story point scale, sprint
switches and chart defaults](docs/screenshots/en/10-settings.png)

The REST API has no screen of its own — see [API.md](API.md).

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

# Run the plugin test suite. The plugin name has to travel as -e: a shell variable
# never reaches the container, and the service then silently tests its default plugin.
docker-compose -f docker-compose.yml --profile test run --build --rm \
  -e PLUGIN=redmine_expert_agile redmine-test
```

Inside a Redmine environment:

```bash
bundle exec rake redmine:plugins:test NAME=redmine_expert_agile RAILS_ENV=test
```

## License

GPL-2.0-or-later. This plugin is an independent, clean-room implementation; it contains no code
from any other agile plugin.
