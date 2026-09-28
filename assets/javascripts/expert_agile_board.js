/* Agile board drag & drop.
 *
 * Reads its configuration from the #ea-board-data JSON island rather than from
 * inline <script> blocks, so the board runs under `script-src 'self'`.
 *
 * The client's job is deliberately small: report which card moved, into which
 * column, and which two cards it landed between. The server computes the rank.
 * RedmineUP re-indexes the whole column in the browser and PUTs every card's
 * new index, which loses concurrent moves and corrupts order against cards that
 * are paginated out of view.
 */
(function () {
  'use strict';

  var config = null;
  var dragged = null;
  /* Where the dragged card sat before it was picked up: its cell and the card
   * it stood in front of. Kept so a move the server refuses can be put back
   * exactly there. */
  var origin = null;
  /* Status columns the dragged card may be dropped into, read from the card
   * at dragstart; null when the card carries no such list. */
  var allowedTargets = null;

  function readConfig() {
    var island = document.getElementById('ea-board-data');
    if (!island) { return null; }
    try {
      return JSON.parse(island.textContent);
    } catch (e) {
      return null;
    }
  }

  function csrfToken() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute('content') : '';
  }

  function cardsIn(cell) {
    return Array.prototype.slice.call(cell.querySelectorAll('.ea-card'));
  }

  /* The cards immediately either side of the drop point — all the server needs
   * to place the moved card between them. The dragover handler has already put
   * the card in position, so this is just a sibling walk. */
  function siblingId(card, direction) {
    var node = card[direction];
    while (node && !node.classList.contains('ea-card')) { node = node[direction]; }
    return node ? node.getAttribute('data-issue-id') : '';
  }

  function neighbours(card) {
    return {
      prev: siblingId(card, 'previousElementSibling'),
      next: siblingId(card, 'nextElementSibling')
    };
  }

  /* `details` carries what the server knows about a refusal beyond the headline:
   * which statuses are open from here, and for an administrator a link into the
   * workflow that refused. Both are built as elements rather than as markup, so
   * nothing the server sends is ever parsed as HTML. */
  function setMessage(text, isError, details) {
    var box = document.getElementById('ea-board-message');
    if (!box) {
      box = document.createElement('div');
      box.id = 'ea-board-message';
      var anchor = document.getElementById('ea-board') || document.getElementById('ea-backlog');
      anchor.parentNode.insertBefore(box, anchor);
    }
    box.className = isError ? 'flash error' : 'flash notice';
    /* Assigning textContent also drops whatever the last message appended. */
    box.textContent = text || '';
    box.style.display = text ? 'block' : 'none';
    if (!text || !details) { return; }

    if (details.hint) {
      var hint = document.createElement('div');
      hint.className = 'ea-board-message-hint';
      hint.textContent = details.hint;
      box.appendChild(hint);
    }
    if (details.link && details.link.url) {
      var link = document.createElement('a');
      link.className = 'ea-board-message-link';
      link.href = details.link.url;
      link.textContent = details.link.label || details.link.url;
      box.appendChild(link);
    }
  }

  /* One implementation drives both the board and the backlog planner. The two
   * differ only in the endpoint and in what the drop target means — a status
   * on the board, a sprint or version in the planner — so both are read from
   * the JSON island. RedmineUP carries two separate initSortable
   * implementations with divergent payloads. */
  function submitMove(card, cell, from) {
    var issueId = card.getAttribute('data-issue-id');
    var dropId = cell.getAttribute('data-drop-id');
    var around = neighbours(card);

    var body = new URLSearchParams();
    body.append(config.dropParam, dropId === null ? '' : dropId);
    body.append('prev_id', around.prev);
    body.append('next_id', around.next);
    if (config.queryId) { body.append('query_id', config.queryId); }
    /* Which board the card sits on. On a parent project's board the card can
     * belong to a subproject, and the counts the server answers with have to
     * be the board's, not that subproject's. Empty means the global board. */
    if (config.mode === 'board') {
      body.append('board_project_id', config.projectId === null || config.projectId === undefined ? '' : config.projectId);
    }
    if (config.containerType) { body.append('container_type', config.containerType); }

    /* Set the moment the server says it saved, so a failure *after* that is not
     * mistaken for a move that never happened. Putting the card back then would
     * show the user the opposite of what the server holds. */
    var saved = false;

    fetch(config.updateUrlTemplate.replace('__ID__', issueId), {
      method: 'PUT',
      credentials: 'same-origin',
      headers: {
        'X-CSRF-Token': csrfToken(),
        'X-Requested-With': 'XMLHttpRequest',
        /* text/javascript, not application/json: Redmine treats a .json request
         * as an API request and ignores the session cookie, so the board would
         * authenticate as anonymous. The response body is still JSON. */
        'Accept': 'text/javascript',
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      body: body.toString()
    }).then(function (response) {
      if (response.ok) {
        /* Set here, not after the body parses: by the time the server answers
         * 200 it has written the move, so a body that will not parse is a
         * display problem, not a move that never happened. */
        saved = true;
        return response.json().then(function (payload) { applyMove(payload); });
      }
      /* A refusal does not always carry a body. Redmine answers a request it
       * will not serve with `head :forbidden` / `head :unauthorized` — no
       * content at all — so parsing the answer as JSON threw and every such
       * refusal reached the user as the bare "the move could not be saved",
       * with nothing to act on. Read the body as text, use it only if it
       * parses, and otherwise say what the status code means. */
      return response.text().then(function (text) {
        var payload = null;
        try { payload = JSON.parse(text); } catch (e) { payload = null; }
        if (!payload || !payload.error) { payload = { error: refusalMessage(response.status) }; }
        revertMove(payload, from);
      });
    }).catch(function () {
      /* Nothing came back at all — no network, a proxy that answered with its
       * own page, a request the browser dropped. */
      if (saved) {
        setMessage(config.labels.saveNotShown, true);
        return;
      }
      revertMove({ error: config.labels.moveFailed }, from);
    });
  }

  /* What to say when the server refused without saying why. A move that fails
   * for lack of a permission and one that fails because the session ran out
   * look identical to the user otherwise, and only one of them is worth
   * telling an administrator about. */
  function refusalMessage(status) {
    if (status === 401) { return config.labels.sessionExpired || config.labels.moveFailed; }
    if (status === 403) { return config.labels.notPermitted || config.labels.moveFailed; }
    return config.labels.moveFailed;
  }

  function applyMove(payload) {
    setMessage('', false);
    var card = document.getElementById('ea-card-' + payload.issueId);
    if (card && payload.card) {
      var holder = document.createElement('div');
      holder.innerHTML = payload.card;
      var fresh = holder.firstElementChild;
      card.parentNode.replaceChild(fresh, card);
      makeDraggable(fresh);
    }
    updateColumns(payload.columns);
    updateLaneTotals(payload.totals, payload.containerId);
  }

  /* Puts a card back where it was picked up. `where` is passed down through the
   * move rather than read from `origin`, because by the time a response arrives
   * the user may already be dragging the next card.
   *
   * Both cards are looked up again rather than kept as nodes: a move that was
   * accepted in the meantime replaces the card it redrew, and re-inserting the
   * node we picked up would put a detached duplicate of it back on the board. */
  function restore(where) {
    if (!where || !where.parent) { return; }
    var card = document.getElementById(where.cardId);
    if (!card) { return; }
    var before = where.nextId ? document.getElementById(where.nextId) : null;
    /* The card it stood in front of may itself have moved since. */
    if (before && before.parentNode !== where.parent) { before = null; }
    where.parent.insertBefore(card, before);
  }

  /* A refused move has written nothing, so the board must show what the server
   * holds: the card goes back to the position it was picked up from, not to the
   * end of its old column. It used to stay wherever it was dropped, which read
   * as the board accepting a move it had just reported as refused. */
  function revertMove(payload, from) {
    restore(from);
    setMessage(payload && payload.error ? payload.error : config.labels.moveFailed, true, payload);
  }

  function updateColumns(columns) {
    if (!columns) { return; }
    columns.forEach(function (column) {
      var headers = document.querySelectorAll('.ea-column-header[data-column-id="' + column.id + '"]');
      Array.prototype.forEach.call(headers, function (header) {
        var count = header.querySelector('.ea-column-count');
        if (count) { count.textContent = column.issue_count; }
        header.classList.toggle('ea-wip-over', !!column.over_wip_limit);
      });
    });
  }

  /* Backlog planner: refresh the counts in the two lanes a move touched. */
  function updateLaneTotals(totals, containerId) {
    if (!totals) { return; }
    applyLaneTotals('', totals.backlog);
    if (totals.container) {
      applyLaneTotals(containerId === null || containerId === undefined ? '' : containerId,
                      totals.container);
    }
  }

  function applyLaneTotals(containerId, values) {
    if (!values) { return; }
    var header = document.querySelector('.ea-backlog-lane-header[data-container-id="' + containerId + '"]');
    if (!header) { return; }
    var count = header.querySelector('.ea-lane-count');
    if (count) { count.textContent = values.issue_count; }
    var points = header.querySelector('.ea-lane-points');
    if (points) { points.textContent = values.story_points || 0; }
  }

  function makeDraggable(card) {
    if (!config.editable) { return; }
    /* The board-wide flag answers "may this user move cards here at all". This
     * one answers it per card, because a board carries more than one project:
     * a parent's board carries its subprojects, the global board carries
     * everything, and the permission lives with the issue. Without it, cards
     * the server was always going to refuse were still offered for dragging. */
    if (card.getAttribute('data-movable') === '0') { return; }
    card.setAttribute('draggable', 'true');
    card.addEventListener('dragstart', function (event) {
      dragged = card;
      var next = card.nextElementSibling;
      origin = { cardId: card.id, parent: card.parentNode, nextId: next ? next.id : null };
      allowedTargets = allowedStatusIds(card);
      card.classList.add('ea-dragging');
      markDropTargets(card);
      event.dataTransfer.effectAllowed = 'move';
      event.dataTransfer.setData('text/plain', card.getAttribute('data-issue-id'));
    });
    card.addEventListener('dragend', function () {
      card.classList.remove('ea-dragging');
      clearDropTargets();
      /* No drop took it: the drag was cancelled with Escape or let go
       * outside the board. dragover has meanwhile carried the card through
       * every cell it crossed, so without this it stayed wherever the pointer
       * last was — drawn in a column it never moved to, no request sent,
       * nothing said, and back in its old place on the next reload. */
      if (dragged === card) {
        restore(origin);
        dragged = null;
        origin = null;
        allowedTargets = null;
      }
    });
  }

  /* Where the workflow lets the card go: ids of the status columns it may
   * be dropped into, its own included. The server works this out per card
   * with the calls it enforces moves with. null means the card carries no
   * such list — the backlog planner — and nothing is gated or marked. */
  function allowedStatusIds(card) {
    var value = card.getAttribute('data-allowed-status-ids');
    if (value === null) { return null; }
    return value === '' ? [] : value.split(',');
  }

  function dropAllowed(cell) {
    if (!allowedTargets) { return true; }
    return allowedTargets.indexOf(cell.getAttribute('data-column-id')) !== -1;
  }

  function boardRoot() {
    return document.getElementById('ea-board');
  }

  /* Marks every column allowed or blocked for the card just picked up, cells
   * and headers alike, so a move the workflow forbids is visibly impossible
   * before the drop instead of being refused after it. Per column, identical
   * in every swimlane: only the status decides. */
  function markDropTargets(card) {
    var root = boardRoot();
    if (!root || !allowedTargets) { return; }
    var own = card.getAttribute('data-status-id');
    root.classList.add('ea-drag-active');
    var targets = root.querySelectorAll('.ea-cell[data-column-id], .ea-column-header[data-column-id]');
    Array.prototype.forEach.call(targets, function (node) {
      var id = node.getAttribute('data-column-id');
      var allowed = allowedTargets.indexOf(id) !== -1;
      node.classList.add(allowed ? 'ea-drop-allowed' : 'ea-drop-blocked');
      if (id === own) { node.classList.add('ea-drop-origin'); }
      if (node.classList.contains('ea-column-header')) {
        node.setAttribute('data-ea-title', node.getAttribute('title') || '');
        node.setAttribute('title', allowed ? config.labels.dropAllowed : config.labels.dropBlocked);
      }
    });
  }

  function clearDropTargets() {
    var root = boardRoot();
    if (!root) { return; }
    root.classList.remove('ea-drag-active');
    var marked = root.querySelectorAll('.ea-drop-allowed, .ea-drop-blocked');
    Array.prototype.forEach.call(marked, function (node) {
      node.classList.remove('ea-drop-allowed', 'ea-drop-blocked', 'ea-drop-origin');
      if (node.hasAttribute('data-ea-title')) {
        var title = node.getAttribute('data-ea-title');
        if (title) { node.setAttribute('title', title); } else { node.removeAttribute('title'); }
        node.removeAttribute('data-ea-title');
      }
    });
  }

  function columnName(statusId) {
    var match = (config.columns || []).filter(function (column) {
      return String(column.id) === String(statusId);
    })[0];
    return match ? match.name : String(statusId);
  }

  function fill(template, values) {
    return String(template || '').replace(/%\{(\w+)\}/g, function (all, key) {
      return values.hasOwnProperty(key) ? values[key] : all;
    });
  }

  /* A drop onto a blocked column, should one get through anyway. Said in the
   * words the server would have used, without asking it: the answer is
   * already known. */
  function refuseBlockedDrop(card, cell, from, allowed) {
    var own = card.getAttribute('data-status-id');
    var tracker = card.querySelector('.ea-card-tracker');
    var open = (allowed || []).filter(function (id) { return id !== own; }).map(columnName);
    var hint = open.length ?
      fill(config.labels.transitionsAllowed, { from: columnName(own), statuses: open.join(', ') }) :
      fill(config.labels.transitionsNone, { from: columnName(own) });
    revertMove({
      error: fill(config.labels.transitionBlocked, {
        tracker: tracker ? tracker.textContent : '',
        from: columnName(own),
        to: columnName(cell.getAttribute('data-column-id'))
      }),
      hint: hint
    }, from);
  }

  /* Whether the card still stands where it was picked up. */
  function atOrigin(card) {
    if (!origin) { return true; }
    var next = card.nextElementSibling;
    return card.parentNode === origin.parent && (next ? next.id : null) === origin.nextId;
  }

  /* Insert before whichever card the pointer is above, so the drop position is
   * what the user sees. */
  function insertionPoint(container, y) {
    var cards = cardsIn(container).filter(function (c) { return c !== dragged; });
    for (var i = 0; i < cards.length; i++) {
      var box = cards[i].getBoundingClientRect();
      if (y < box.top + box.height / 2) { return cards[i]; }
    }
    return null;
  }

  function makeDroppable(cell) {
    var container = cell.querySelector('.ea-cell-issues') || cell;
    cell.addEventListener('dragover', function (event) {
      if (!dragged) { return; }
      /* Not accepting the dragover is what makes the browser show "no drop"
       * and never fire drop here. The card goes back where it came from
       * rather than hanging in the last cell it crossed, so what is drawn is
       * always a place it may actually go. */
      if (!dropAllowed(cell)) {
        event.dataTransfer.dropEffect = 'none';
        if (!atOrigin(dragged)) { restore(origin); }
        return;
      }
      event.preventDefault();
      event.dataTransfer.dropEffect = 'move';
      cell.classList.add('ea-cell-hover');
      var reference = insertionPoint(container, event.clientY);
      if (reference) {
        container.insertBefore(dragged, reference);
      } else {
        container.appendChild(dragged);
      }
    });
    cell.addEventListener('dragleave', function () {
      cell.classList.remove('ea-cell-hover');
    });
    cell.addEventListener('drop', function (event) {
      event.preventDefault();
      cell.classList.remove('ea-cell-hover');
      if (!dragged) { return; }
      var card = dragged;
      var from = origin;
      var allowed = allowedTargets;
      var permitted = dropAllowed(cell);
      dragged = null;
      origin = null;
      allowedTargets = null;
      clearDropTargets();
      if (!permitted) {
        refuseBlockedDrop(card, cell, from, allowed);
        return;
      }
      submitMove(card, cell, from);
    });
  }

  function init() {
    config = readConfig();
    if (!config) { return; }
    /* Same script, either screen. */
    var root = document.getElementById('ea-board') || document.getElementById('ea-backlog');
    if (!root) { return; }

    Array.prototype.forEach.call(root.querySelectorAll('.ea-card'), makeDraggable);
    Array.prototype.forEach.call(root.querySelectorAll('.ea-cell'), makeDroppable);
  }

  window.ExpertAgileBoard = {
    applyMove: applyMove,
    revertMove: revertMove
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
