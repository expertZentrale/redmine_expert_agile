# REST API — redmine_expert_agile

All endpoints speak JSON and XML (swap the extension) and use Redmine's own
authentication: an `X-Redmine-API-Key` header, a `key=` query parameter, or HTTP Basic. The REST
web service must be enabled under *Administration → Settings → API*.

Every endpoint is subject to the usual Redmine visibility rules on top of the plugin
permissions — an issue you cannot see has no agile data you can read.

## Contents

- [Agile data](#agile-data)
- [Sprints](#sprints)
- [Errors](#errors)

---

## Agile data

Per-issue board rank, story points and sprint assignment.

### `GET /issues/:id/expert_agile_data.:format`

Requires the issue to be visible.

```bash
curl -H "X-Redmine-API-Key: $KEY" \
     "$REDMINE_URL/issues/42/expert_agile_data.json"
```

```json
{
  "expert_agile_data": {
    "issue_id": 42,
    "position": "1024.0",
    "story_points": 5,
    "sprint_id": 7
  }
}
```

An issue that has never been ranked, estimated or planned has no row; the endpoint still
answers `200` with `null` values rather than `404`.

| Field | Type | Meaning |
| --- | --- | --- |
| `issue_id` | integer | The issue |
| `position` | decimal, nullable | Board rank. Fractional — see the note below |
| `story_points` | integer, nullable | `null` means "not estimated", which is not the same as `0` |
| `sprint_id` | integer, nullable | Assigned sprint |

### `PUT /issues/:id/expert_agile_data.:format`

Requires edit rights on the issue. Returns `204 No Content` on success.

```bash
curl -X PUT -H "X-Redmine-API-Key: $KEY" -H "Content-Type: application/json" \
     -d '{"expert_agile_data": {"story_points": 8, "sprint_id": 7}}' \
     "$REDMINE_URL/issues/42/expert_agile_data.json"
```

| Parameter | Type | Notes |
| --- | --- | --- |
| `story_points` | integer ≥ 0 | Send `""` to clear |
| `sprint_id` | integer | Send `null` to unassign. Must be a sprint the issue's project may plan into, otherwise `422` |

Omitted keys are left untouched, so a partial update is safe.

> **Why this exists.** RedmineUP's Agile plugin exposes agile data read-only, so story points and
> sprint assignment can only be set through nested attributes on the issue endpoint. This is a
> first-class write endpoint instead.

`position` is deliberately **not** writable. Ranks are fractional and computed by the server from
the two neighbours a card was dropped between; letting a client post an arbitrary rank would
reintroduce exactly the concurrency problem the design avoids. Reorder through the board.

---

## Sprints

### `GET /projects/:project_id/expert_agile_sprints.:format`

Requires `manage_expert_agile_sprints` and the `expert_agile` module.

```json
{
  "expert_agile_sprints": [
    {
      "id": 7,
      "project_id": 1,
      "name": "Sprint 12",
      "description": "Checkout rework",
      "status": "active",
      "sharing": "none",
      "start_date": "2026-01-05",
      "end_date": "2026-01-18"
    }
  ],
  "total_count": 1
}
```

`status` is one of `open`, `active`, `closed`. `sharing` is one of `none`, `descendants`,
`hierarchy`, `tree`, `system` — the same semantics as Redmine version sharing.

### `GET /projects/:project_id/expert_agile_sprints/:id.:format`

The single-sprint form adds aggregates:

| Field | Meaning |
| --- | --- |
| `issue_count` | Issues currently in the sprint |
| `story_points` | Sum of story points in the sprint |

### `POST /projects/:project_id/expert_agile_sprints.:format`

Returns `201 Created`.

```bash
curl -X POST -H "X-Redmine-API-Key: $KEY" -H "Content-Type: application/json" \
     -d '{"expert_agile_sprint": {"name": "Sprint 13", "start_date": "2026-01-19", "end_date": "2026-02-01"}}' \
     "$REDMINE_URL/projects/1/expert_agile_sprints.json"
```

| Parameter | Required | Notes |
| --- | --- | --- |
| `name` | yes | Unique within the project |
| `start_date` | yes | `YYYY-MM-DD` |
| `end_date` | yes | Must not precede `start_date` |
| `description` | no | |
| `status` | no | `0` open (default), `1` active, `2` closed |
| `sharing` | no | `0` none (default) … `4` system |

Setting `status` to active stands the project's other active sprint down. A sprint cannot be
closed while it still holds open issues. Overlapping unshared sprints are rejected unless
*Allow overlapping sprints* is enabled.

### `PUT /projects/:project_id/expert_agile_sprints/:id.:format`

Same parameters. Returns `204 No Content`.

### `DELETE /projects/:project_id/expert_agile_sprints/:id.:format`

Returns `204 No Content`. Issues in the sprint are **unassigned, not deleted**.

---

## Errors

| Status | Meaning |
| --- | --- |
| `401 Unauthorized` | Missing or invalid credentials |
| `403 Forbidden` | Authenticated, but lacking the permission or the module is disabled |
| `404 Not Found` | Not visible, or does not exist |
| `422 Unprocessable Entity` | Validation failed; the body carries `errors` |

```json
{ "errors": ["End date must not be before the start date"] }
```
