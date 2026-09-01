# redmine.org plugin directory

Copy-paste sources for the plugin's listing at
<https://www.redmine.org/plugins/redmine_expert_agile>.

The directory renders **Textile**, not Markdown — headings are `h3.`, bold is
`*text*`, inline code is `@code@`, links are `"label":url`. Everything here is
written in Textile so it can be pasted straight into the form without editing.

The directory keeps the description and the installation notes in **separate
fields**, so they are separate files here — don't merge them.

| File | Pastes into |
|------|-------------|
| `description.textile` | the **Description** field — what the plugin is and does, current version |
| `installation.textile` | the **Installation notes** field — requirements, install, permissions, configuration, upgrade |
| `releases/<version>.textile` | the **Notes** field when registering that version |
| `logo-100.png` | the plugin page **image upload** (the directory shows logos at 100×100) |
| `logo.svg`, `logo-500.png` | source and large master of the logo — edit the SVG, re-export both PNGs |

`docs/` is excluded from the release archives (`--exclude='docs'` in
`.github/workflows/release.yml`), so none of this ships to users.

## When cutting a release

1. Write `releases/<version>.textile` — user-facing changes only. The CHANGELOG
   is the source, but this is not a copy of it: drop the internal detail, keep
   what an operator deciding whether to upgrade needs. Follow the house shape —
   `h3. redmine_expert_agile <version> — <YYYY-MM-DD>`, then `h4. Added` /
   `Changed` / `Fixed` in whatever order fits, and always close with
   `h4. Upgrade notes` (say "No migrations. Replace the plugin directory and
   restart." when that is all it takes).
2. Update `description.textile` if the release changed what the plugin *is* or
   *supports* — a new feature worth listing under *Features*, a dropped
   limitation, a changed design note. Bump the Redmine versions under
   *Requirements* if they moved.
3. Update `installation.textile` if the release changed a step: a new migration,
   a new permission or project module, a new setting, a new gem, or a change to
   how it coexists with RedmineUP Agile.
4. After pushing the tag, register the version at
   <https://www.redmine.org/plugins/redmine_expert_agile> and paste the files
   into their respective fields.

## The failure mode to guard against

The release notes get written because the release forces them. The description
does not, so it drifts: it keeps advertising last year's plugin while the
CHANGELOG has moved on, and nobody notices because nothing breaks.

The worked example from this repo. `description.textile` used to say:

> *Backlog planner* — drag issues into sprints or versions from a dedicated
> planning view, behind its own project module.

Which stayed true right up until the backlog gained the board's filter and
options panel, session persistence, saved backlogs and configurable cards. The
sentence never became *wrong* — it just described a thinner plugin than the one
being shipped, and nothing in the release process would have caught it, because
that release's notes were about the backlog panel and read perfectly well.

So: **before tagging, read `description.textile` end to end against the
CHANGELOG since the last tag**, not just the section you happen to be touching.
Ask of each bullet whether it still describes the current plugin, and of the
CHANGELOG whether anything in it belongs in a bullet that does not exist yet.
