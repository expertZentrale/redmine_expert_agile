/* Agile board drag & drop.
 *
 * Reads its configuration from the #ea-board-data JSON island rather than from
 * inline <script> blocks, so the board runs under `script-src 'self'`.
 *
 * The client's job is deliberately small: report which card moved, into which
 * column, and which two cards it landed between. The server computes the rank,
 * so concurrent moves are not lost and cards paginated out of view keep their
 * order.
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
  /* The lane the dragged card was picked up from, '' for the "no value"
   * lane; null on an ungrouped board and in the backlog planner. */
  var originLane = null;
  /* Set by pinHeader: redraws the pinned copy of the column headers after
   * the board was redrawn. */
  var refreshPinnedHead = null;

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

  function csrfParam() {
    var meta = document.querySelector('meta[name="csrf-param"]');
    return meta ? meta.getAttribute('content') : 'authenticity_token';
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
   * the JSON island. */
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
    /* What the lanes on screen are grouped by, so the answer refreshes those
     * lanes. The lane itself only when the card left its own: that drop sets
     * the field, and only then. */
    if (config.swimlaneField) {
      body.append('swimlane_field', config.swimlaneField);
      var lane = laneOf(cell);
      if (from && !sameLane(lane, from.lane)) { body.append('swimlane_id', lane); }
    }

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
      placeInLane(fresh, payload);
    }
    /* Other cards the move changed — a story counting the subtask that just
     * moved. Swapped in place: they did not move, only their content did. */
    (payload.relatedCards || []).forEach(function (related) {
      var old = document.getElementById('ea-card-' + related.issueId);
      if (!old) { return; }
      var holder = document.createElement('div');
      holder.innerHTML = related.card;
      var replacement = holder.firstElementChild;
      old.parentNode.replaceChild(replacement, old);
      makeDraggable(replacement);
    });
    updateColumns(payload.columns);
    updateLaneTotals(payload.totals, payload.containerId, payload.progress);
    updateSwimlanes(payload.lanes);
    applyPanelProgress(payload.panelProgress);
  }

  /* --- Epic panel (backlog planner) ---------------------------------------
   *
   * Beside the sprint and version lanes the planner lists its epics. Their
   * entries are links that filter the planner, and drop targets: a card let go
   * on an epic is hung under it (#update_epic), on "without epic" it leaves
   * its epic. The card stays in its lane; it only leaves the screen when it no
   * longer passes the planner's filters, an epic filter above all. */

  function epicPanel() {
    return document.getElementById('ea-epic-panel');
  }

  function applyPanelProgress(progress) {
    var panel = epicPanel();
    if (!progress || !panel) { return; }
    Object.keys(progress).forEach(function (id) {
      applyEpicProgress(panel.querySelector('[data-epic-drop="' + id + '"]'), progress[id]);
    });
  }

  function makeEpicDroppable(item) {
    item.addEventListener('dragover', function (event) {
      if (!dragged) { return; }
      event.preventDefault();
      event.dataTransfer.dropEffect = 'move';
      /* The card is not going into another lane: it goes back where it was
       * while the pointer is over the panel. */
      if (!atOrigin(dragged)) { restore(origin); }
      item.classList.add('ea-epic-drop-hover');
    });
    item.addEventListener('dragleave', function () {
      item.classList.remove('ea-epic-drop-hover');
    });
    item.addEventListener('drop', function (event) {
      event.preventDefault();
      item.classList.remove('ea-epic-drop-hover');
      if (!dragged) { return; }
      var card = dragged;
      dragged = null;
      origin = null;
      allowedTargets = null;
      originLane = null;
      clearDropTargets();
      submitEpicMove(card, item.getAttribute('data-epic-drop'));
    });
  }

  function submitEpicMove(card, epicId) {
    var body = new URLSearchParams();
    body.append('epic_id', epicId || '');
    /* The planner on screen, so the answer can tell whether the card still
     * passes its filters. */
    if (config.queryId) { body.append('query_id', config.queryId); }
    if (config.containerType) { body.append('container_type', config.containerType); }
    var saved = false;

    fetch(config.epicUpdateUrlTemplate.replace('__ID__', card.getAttribute('data-issue-id')), {
      method: 'PUT',
      credentials: 'same-origin',
      headers: {
        'X-CSRF-Token': csrfToken(),
        'X-Requested-With': 'XMLHttpRequest',
        'Accept': 'text/javascript',
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      body: body.toString()
    }).then(function (response) {
      if (response.ok) {
        saved = true;
        return response.json().then(applyEpicMove);
      }
      return response.text().then(function (text) {
        var payload = null;
        try { payload = JSON.parse(text); } catch (e) { payload = null; }
        if (!payload || !payload.error) { payload = { error: refusalMessage(response.status) }; }
        setMessage(payload.error, true, payload);
      });
    }).catch(function () {
      setMessage(saved ? config.labels.saveNotShown : config.labels.moveFailed, true);
    });
  }

  function applyEpicMove(payload) {
    setMessage('', false);
    var card = document.getElementById('ea-card-' + payload.issueId);
    if (card && payload.shown === false) {
      card.parentNode.removeChild(card);
      setMessage(config.labels.cardHiddenByFilter, false);
    } else if (card && payload.card) {
      var holder = document.createElement('div');
      holder.innerHTML = payload.card;
      var fresh = holder.firstElementChild;
      card.parentNode.replaceChild(fresh, card);
      makeDraggable(fresh);
    }
    updateLaneTotals(payload.totals, payload.containerId, null);
    applyPanelProgress(payload.panelProgress);
  }

  /* --- Folding lanes (backlog planner, list layout) -----------------------
   *
   * In the list layout the lanes stand one under another, and a sprint that
   * is planned can be folded down to its header. Which lanes are folded is
   * remembered per browser. A folded lane still takes a card dropped on its
   * header, at its end. */

  function laneStorageKey(lane) {
    return config.laneStoragePrefix + '.' + lane.getAttribute('data-lane-key');
  }

  function setLaneFolded(lane, folded) {
    var button = lane.querySelector('.ea-lane-toggle');
    lane.classList.toggle('ea-lane-folded', folded);
    if (!button) { return; }
    button.setAttribute('aria-expanded', String(!folded));
    var label = folded ? config.labels.expand : config.labels.collapse;
    if (label) {
      button.setAttribute('aria-label', label);
      button.title = label;
    }
  }

  function setupLane(root, lane) {
    var list = root.classList.contains('ea-backlog-list');
    var button = lane.querySelector('.ea-lane-toggle');
    if (button && list && config.laneStoragePrefix) {
      var folded = false;
      try { folded = window.localStorage.getItem(laneStorageKey(lane)) === '1'; } catch (e) { folded = false; }
      setLaneFolded(lane, folded);
      button.addEventListener('click', function (event) {
        event.preventDefault();
        event.stopPropagation();
        var fold = !lane.classList.contains('ea-lane-folded');
        setLaneFolded(lane, fold);
        try {
          if (fold) {
            window.localStorage.setItem(laneStorageKey(lane), '1');
          } else {
            window.localStorage.removeItem(laneStorageKey(lane));
          }
        } catch (e) { /* storage unavailable: the fold lasts for this page */ }
      });
    }

    var header = lane.querySelector('.ea-backlog-lane-header');
    var cell = lane.querySelector('.ea-cell');
    if (!header || !cell) { return; }
    header.addEventListener('dragover', function (event) {
      if (!dragged || !lane.classList.contains('ea-lane-folded')) { return; }
      event.preventDefault();
      event.dataTransfer.dropEffect = 'move';
      if (!atOrigin(dragged)) { restore(origin); }
      lane.classList.add('ea-lane-drop-hover');
    });
    header.addEventListener('dragleave', function () {
      lane.classList.remove('ea-lane-drop-hover');
    });
    header.addEventListener('drop', function (event) {
      lane.classList.remove('ea-lane-drop-hover');
      if (!dragged || !lane.classList.contains('ea-lane-folded')) { return; }
      event.preventDefault();
      var card = dragged;
      var from = origin;
      dragged = null;
      origin = null;
      allowedTargets = null;
      originLane = null;
      clearDropTargets();
      (cell.querySelector('.ea-cell-issues') || cell).appendChild(card);
      submitMove(card, cell, from);
    });
  }

  function initPlanner(root) {
    Array.prototype.forEach.call(root.querySelectorAll('.ea-card'), makeDraggable);
    Array.prototype.forEach.call(root.querySelectorAll('.ea-cell'), makeDroppable);
    Array.prototype.forEach.call(root.querySelectorAll('.ea-backlog-lane'), function (lane) {
      setupLane(root, lane);
    });
    var panel = epicPanel();
    if (panel && config.epicUpdateUrlTemplate && config.editable) {
      Array.prototype.forEach.call(panel.querySelectorAll('[data-epic-drop]'), makeEpicDroppable);
    }
  }

  /* The lane of a board cell, or null where cells carry none. */
  function laneOf(cell) {
    return cell ? cell.getAttribute('data-swimlane-id') : null;
  }

  function cellOf(card) {
    var node = card.parentNode;
    while (node && !(node.classList && node.classList.contains('ea-cell'))) { node = node.parentNode; }
    return node;
  }

  /* The card belongs in the cell of its status and the lane the server says
   * it is in, which is not always the cell it was dropped into: a move can
   * change the lane on its own, as claiming a card on a board grouped by
   * assignee does. A lane that is not on the page cannot take it; the card
   * leaves the board then rather than be drawn somewhere it is not. */
  function placeInLane(card, payload) {
    if (payload.swimlaneId === undefined || payload.swimlaneId === null) { return; }
    var current = cellOf(card);
    var lane = String(payload.swimlaneId);
    if (current && laneOf(current) === lane &&
        current.getAttribute('data-column-id') === String(payload.statusId)) { return; }
    var root = boardRoot();
    var target = root && Array.prototype.filter.call(
      root.querySelectorAll('.ea-cell[data-column-id="' + payload.statusId + '"]'),
      function (cell) { return laneOf(cell) === lane; }
    )[0];
    if (!target) {
      card.parentNode.removeChild(card);
      setMessage(config.labels.laneNotShown, false);
      return;
    }
    (target.querySelector('.ea-cell-issues') || target).appendChild(card);
  }

  /* Board: the issue and story point totals of every lane band. A lane the
   * answer does not list holds no card any more. */
  function updateSwimlanes(lanes) {
    if (!lanes) { return; }
    var root = boardRoot();
    if (!root) { return; }
    var byId = {};
    lanes.forEach(function (lane) { byId[String(lane.id)] = lane; });
    Array.prototype.forEach.call(root.querySelectorAll('tr.ea-swimlane-title[data-swimlane-id]'), function (band) {
      var values = byId[band.getAttribute('data-swimlane-id')] || { issue_count: 0, story_points: 0 };
      var count = band.querySelector('.ea-swimlane-count');
      if (count) { count.textContent = values.issue_count; }
      var points = band.querySelector('.ea-swimlane-points');
      if (points) {
        var value = parseInt(values.story_points, 10) || 0;
        points.textContent = value;
        points.hidden = value <= 0;
      }
      applyEpicProgress(band, values.progress);
    });
  }

  /* An epic lane's progress bar, from the numbers the server answered with. */
  function applyEpicProgress(container, progress) {
    if (!container || !progress) { return; }
    var bar = container.querySelector('.ea-epic-progress');
    if (!bar) { return; }
    bar.style.setProperty('--ea-progress', progress.percent + '%');
    bar.title = progress.title;
    var text = bar.querySelector('.ea-epic-progress-text');
    if (text) { text.textContent = progress.percent + ' %'; }
  }

  /* Puts a card back where it was picked up. `where` is passed down through the
   * move rather than read from `origin`, because by the time a response arrives
   * the user may already be dragging the next card.
   *
   * Both cards are looked up again rather than kept as nodes: a move that was
   * accepted in the meantime replaces the card it redrew, and re-inserting the
   * node we picked up would put a detached duplicate of it back on the board. */
  function restore(where) {
    /* A parent no longer on the page belongs to a board that was redrawn
     * since; the card there already stands where the server has it. */
    if (!where || !where.parent || !where.parent.isConnected) { return; }
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
  function updateLaneTotals(totals, containerId, progress) {
    if (!totals) { return; }
    applyLaneTotals('', totals.backlog);
    /* The lane the card left, when it was neither the backlog nor the target. */
    if (totals.source) { applyLaneTotals(totals.source.id, totals.source); }
    if (progress) {
      Object.keys(progress).forEach(function (id) {
        applyEpicProgress(document.querySelector('.ea-backlog-lane-header[data-container-id="' + id + '"]'),
                          progress[id]);
      });
    }
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
      originLane = laneOf(cellOf(card));
      origin = { cardId: card.id, parent: card.parentNode, nextId: next ? next.id : null, lane: originLane };
      allowedTargets = allowedStatusIds(card);
      card.classList.add('ea-dragging');
      markDropTargets(card);
      var panel = epicPanel();
      if (panel && config.epicUpdateUrlTemplate) { panel.classList.add('ea-epic-panel-active'); }
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
        originLane = null;
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
    return columnAllowed(cell) && laneAllowed(cell);
  }

  function columnAllowed(cell) {
    if (!allowedTargets) { return true; }
    return allowedTargets.indexOf(cell.getAttribute('data-column-id')) !== -1;
  }

  /* Another lane takes the card only where dropping it there sets the field
   * the lanes are grouped by. Whether this user may set it on this card is
   * the server's to say; a refusal puts the card back. */
  function laneAllowed(cell) {
    return config.swimlaneWritable || sameLane(laneOf(cell), originLane);
  }

  function sameLane(lane, own) {
    return own === null || own === undefined || lane === null || lane === own;
  }

  function boardRoot() {
    return document.getElementById('ea-board');
  }

  /* Marks every column allowed or blocked for the card just picked up, cells
   * and headers alike, so a move the workflow forbids is visibly impossible
   * before the drop instead of being refused after it. The headers answer for
   * the status alone; a cell is blocked as well when it lies in another lane. */
  function markDropTargets(card) {
    var root = boardRoot();
    if (!root || !allowedTargets) { return; }
    var own = card.getAttribute('data-status-id');
    root.classList.add('ea-drag-active');
    var targets = root.querySelectorAll('.ea-cell[data-column-id], .ea-column-header[data-column-id]');
    Array.prototype.forEach.call(targets, function (node) {
      var id = node.getAttribute('data-column-id');
      var allowed = allowedTargets.indexOf(id) !== -1;
      var cell = node.classList.contains('ea-cell');
      if (cell && !laneAllowed(node)) { allowed = false; }
      node.classList.add(allowed ? 'ea-drop-allowed' : 'ea-drop-blocked');
      /* The cell it came from, not the same column in every lane. */
      if (id === own && allowed && (!cell || sameLane(laneOf(node), originLane))) {
        node.classList.add('ea-drop-origin');
      }
      if (node.classList.contains('ea-column-header')) {
        node.setAttribute('data-ea-title', node.getAttribute('title') || '');
        node.setAttribute('title', allowed ? config.labels.dropAllowed : config.labels.dropBlocked);
      }
    });
  }

  function clearDropTargets() {
    var panel = epicPanel();
    if (panel) { panel.classList.remove('ea-epic-panel-active'); }
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
    if (!config.swimlaneWritable && from && !sameLane(laneOf(cell), from.lane)) {
      revertMove({ error: config.labels.laneBlocked || config.labels.moveFailed }, from);
      return;
    }
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
      originLane = null;
      clearDropTargets();
      if (!permitted) {
        refuseBlockedDrop(card, cell, from, allowed);
        return;
      }
      submitMove(card, cell, from);
    });
  }

  /* Where the copy of the column headers may pin: the top of the window,
   * or just below a header bar fixed over the page. Redmine's narrow-screen
   * layout fixes its own, 64px high and above everything else, so a copy at
   * the very top would sit behind it, out of sight. */
  function windowTopEdge() {
    var bar = document.getElementById('header');
    if (!bar || window.getComputedStyle(bar).position !== 'fixed') { return 0; }
    return Math.max(0, bar.getBoundingClientRect().bottom);
  }

  /* Keeps the column headers at the top of the window while a tall board
   * scrolls past, from the moment the real ones leave it until the last row
   * goes. position: sticky cannot do this: the board scrolls sideways, and a
   * box that scrolls on one axis is the scroll container on both, so a sticky
   * head would pin to the board, never to the page.
   *
   * A copy of the head is shown fixed instead, clipped to the board's visible
   * width and shifted by its sideways scroll. It lives inside the board, so
   * the count updates and the drop marking, which query for every header of
   * a column, reach it without knowing it is there. */
  function pinHeader(root) {
    var table = boardTable(root);
    var head = table && table.tHead;
    if (!head) { return; }

    var pinnedHead = document.createElement('div');
    pinnedHead.className = 'ea-pinned-head';
    pinnedHead.hidden = true;
    /* The real head is still in the page; nobody needs the columns read out
     * twice. */
    pinnedHead.setAttribute('aria-hidden', 'true');
    var copy = document.createElement('table');
    copy.className = table.className;
    copy.appendChild(head.cloneNode(true));
    pinnedHead.appendChild(copy);
    root.insertBefore(pinnedHead, root.firstChild);
    var printing = false;

    /* Run straight from the scroll event rather than deferred to an animation
     * frame: browsers already fire scroll once per frame, and deferring would
     * draw the copy a frame behind the page. Every measurement comes before
     * every write, so the handler never makes the browser lay the page out a
     * second time. The real head stands in for the copy's height: both are
     * the same rows under the same rules. */
    function place() {
      /* Read from the table each time: a redrawn board brings a head of
       * its own. */
      var head = table.tHead;
      var edge = windowTopEdge();
      var tableBox = table.getBoundingClientRect();
      var headTop = head.getBoundingClientRect().top;
      var headHeight = head.offsetHeight;
      var boardLeft = root.getBoundingClientRect().left + root.clientLeft;
      var boardWidth = root.clientWidth;

      var shown = !printing && headTop < edge && tableBox.bottom > edge;
      pinnedHead.hidden = !shown;
      if (!shown) { return; }
      pinnedHead.style.left = boardLeft + 'px';
      pinnedHead.style.width = boardWidth + 'px';
      /* Pushed up with the last row rather than left hanging over the page
       * beneath the board. */
      pinnedHead.style.top = Math.min(edge, tableBox.bottom - headHeight) + 'px';
      copy.style.transform = 'translateX(' + (tableBox.left - boardLeft) + 'px)';
    }

    window.addEventListener('scroll', place, { passive: true });
    window.addEventListener('resize', place);
    root.addEventListener('scroll', place, { passive: true });
    /* The board changes width without the window resizing when Redmine's
     * sidebar is collapsed or expanded. */
    new ResizeObserver(place).observe(root);
    /* Redmine's narrow-screen menu slides the whole page aside by a class on
     * <html>, which moves the board without resizing or scrolling anything. */
    new MutationObserver(place).observe(document.documentElement,
                                        { attributes: true, attributeFilter: ['class'] });
    /* A printout has the real head; the copy, fixed, would repeat on every
     * page at a position worked out for the screen. */
    window.addEventListener('beforeprint', function () { printing = true; place(); });
    window.addEventListener('afterprint', function () { printing = false; place(); });
    refreshPinnedHead = function () {
      copy.replaceChild(table.tHead.cloneNode(true), copy.tHead);
      place();
    };
    place();
  }

  /* The board's own table. The pinned copy of the head is a table of the same
   * class inside the board, ahead of it, so a plain lookup would find that. */
  function boardTable(root) {
    return root ? root.querySelector(':scope > table.ea-board-table') : null;
  }

  /* --- Context menu -----------------------------------------------------
   *
   * The menu is Redmine's own: context_menu.js opens it on a right click on
   * a card, or on the card's actions link, and the server decides which
   * entries this user may use on the selected issues. Its field entries —
   * status, tracker, priority, version, assignee, category, done ratio,
   * custom fields — are PATCH links that come back to this board through
   * back_url: to the issue itself when one card is selected, to bulk_update
   * when several are. Followed as links they reload the whole page;
   * the board sends them itself instead and redraws from the answer, so it
   * stays where it was scrolled to. Every other entry (edit, copy, log time,
   * delete, watch) is left to Redmine. */

  /* A right click on the card's own links, its number and its subject.
   * Redmine's menu script leaves every link to the browser's menu, as in the
   * issue list; on a card the subject covers most of it, so a right click
   * would rarely reach the menu. The click is handed to the card itself,
   * where Redmine opens its menu as for any other part of it. Links to other
   * issues (epic, story, subtasks, field values) keep the browser's menu:
   * Redmine's would act on the card, not on the issue the link names. */
  function forwardCardLinkContextMenu(event) {
    var target = event.target;
    var link = target && target.closest ? target.closest('a') : null;
    if (!link || !link.closest('.ea-card-id, .ea-card-subject')) { return; }
    var card = link.closest('.ea-card.hascontextmenu');
    var root = boardRoot() || document.getElementById('ea-backlog');
    if (!card || !root || !root.contains(card)) { return; }
    event.preventDefault();
    event.stopPropagation();
    card.dispatchEvent(new MouseEvent('contextmenu', {
      bubbles: true,
      cancelable: true,
      view: window,
      button: 2,
      buttons: event.buttons,
      clientX: event.clientX,
      clientY: event.clientY,
      screenX: event.screenX,
      screenY: event.screenY,
      ctrlKey: event.ctrlKey,
      shiftKey: event.shiftKey,
      altKey: event.altKey,
      metaKey: event.metaKey
    }));
  }

  /* The address of a field entry, or null for any other link. */
  function bulkUpdateUrl(target) {
    var link = target && target.closest ? target.closest('#context-menu a[data-method]') : null;
    if (!link || link.hasAttribute('data-confirm') || link.hasAttribute('data-remote')) { return null; }
    if (String(link.getAttribute('data-method')).toLowerCase() !== 'patch') { return null; }
    var url;
    try {
      url = new URL(link.getAttribute('href'), window.location.href);
    } catch (e) {
      return null;
    }
    if (url.origin !== window.location.origin || !/\/issues\/(\d+|bulk_update)$/.test(url.pathname)) {
      return null;
    }
    return url.href;
  }

  /* Registered for the capture phase, so it runs before Redmine's own link
   * handler, which would submit the link as a form. */
  function interceptBulkUpdate(event) {
    var url = bulkUpdateUrl(event.target);
    if (!url) { return; }
    event.preventDefault();
    event.stopPropagation();
    /* Stopping the click also kept it from Redmine's handler that closes
     * the menu. */
    if (typeof window.contextMenuHide === 'function') { window.contextMenuHide(); }
    submitBulkUpdate(url);
  }

  function submitBulkUpdate(url) {
    var body = new URLSearchParams();
    body.append('_method', 'patch');
    body.append(csrfParam(), csrfToken());

    fetch(url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        'X-CSRF-Token': csrfToken(),
        'Accept': 'text/html',
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      body: body.toString()
    }).then(function (response) {
      return response.text().then(function (html) {
        var page = new DOMParser().parseFromString(html, 'text/html');
        /* The session ran out: Redmine sent the request to its sign-in page
         * and changed nothing. */
        if (page.getElementById('login-form')) {
          setMessage(config.labels.sessionExpired || config.labels.changeFailed, true);
          return;
        }
        /* Saved: Redmine redirected to back_url and fetch followed, so the
         * answer already is this board after the change. Nothing is said, as
         * after a move: the redrawn board shows it, and a notice would push
         * the board down on every change. */
        if (response.ok && response.redirected) {
          setMessage('', false);
          if (!swapScreen(page)) { refreshBoard(); }
          return;
        }
        /* Refused: Redmine answers with the issue's edit form, or for several
         * issues its bulk edit form, and the reasons. With several cards
         * selected the others may have been saved, so the board is redrawn
         * all the same. */
        var refusal = response.ok ? bulkUpdateRefusal(page) : null;
        setMessage(refusal ? refusal.error : changeRefusalMessage(response.status), true, refusal);
        refreshBoard();
      });
    }).catch(function () {
      setMessage(config.labels.changeFailed, true);
    });
  }

  /* The reasons on the form Redmine answered a refusal with: one line per
   * reason, under a headline naming the issues that were not saved on the
   * bulk edit form. Taken as text only, like every other message the board
   * shows. */
  function bulkUpdateRefusal(page) {
    var box = page.getElementById('errorExplanation');
    if (!box) { return null; }
    var headline = box.querySelector('span');
    var reasons = Array.prototype.map.call(box.querySelectorAll('li'), function (item) {
      return item.textContent.trim();
    }).filter(function (text) { return text !== ''; });
    return {
      error: headline ? headline.textContent.trim() : config.labels.changeFailed,
      hint: reasons.join('; ')
    };
  }

  function changeRefusalMessage(status) {
    if (status === 401) { return config.labels.sessionExpired || config.labels.changeFailed; }
    if (status === 403) { return config.labels.changeNotPermitted || config.labels.changeFailed; }
    return config.labels.changeFailed;
  }

  /* Redraws the board from a fresh copy of this page, for the answers that
   * do not carry one. */
  function refreshBoard() {
    fetch(window.location.href, { credentials: 'same-origin', headers: { 'Accept': 'text/html' } })
      .then(function (response) {
        if (!response.ok) { throw new Error('board not loaded'); }
        return response.text();
      })
      .then(function (html) {
        if (!swapScreen(new DOMParser().parseFromString(html, 'text/html'))) {
          throw new Error('no board on the page');
        }
      })
      .catch(reportBoardStale);
  }

  /* Said in addition to whatever the board already reports, which is the
   * more important part: what happened to the change itself. */
  function reportBoardStale() {
    var box = document.getElementById('ea-board-message');
    if (!box || box.style.display === 'none' || !box.textContent) {
      setMessage(config.labels.boardNotRefreshed, true);
      return;
    }
    var line = document.createElement('div');
    line.className = 'ea-board-message-hint';
    line.textContent = config.labels.boardNotRefreshed;
    box.appendChild(line);
    box.className = 'flash error';
  }

  /* Shows a fresh render of the board in place of the one on screen: the
   * head with its counts and WIP marks, every lane and card, and the data
   * this script runs on. The table itself stays, and with it the board's
   * sideways scroll, the page's scroll and the pinned head. Answers false
   * when the page holds no board, so the caller can fetch one. */
  function swapBoard(page) {
    var table = boardTable(boardRoot());
    var fresh = boardTable(page.getElementById('ea-board'));
    var island = page.getElementById('ea-board-data');
    var ownIsland = document.getElementById('ea-board-data');
    if (!table || !table.tHead || !table.tBodies[0] || !fresh || !fresh.tHead || !fresh.tBodies[0] ||
        !island || !ownIsland) {
      return false;
    }
    var freshConfig;
    try {
      freshConfig = JSON.parse(island.textContent);
    } catch (e) {
      return false;
    }

    abandonDrag();
    config = freshConfig;
    ownIsland.textContent = island.textContent;
    table.replaceChild(document.importNode(fresh.tHead, true), table.tHead);
    table.replaceChild(document.importNode(fresh.tBodies[0], true), table.tBodies[0]);
    Array.prototype.forEach.call(table.querySelectorAll('.ea-card'), makeDraggable);
    Array.prototype.forEach.call(table.querySelectorAll('.ea-cell'), makeDroppable);
    if (refreshPinnedHead) { refreshPinnedHead(); }
    return true;
  }

  function swapScreen(page) {
    return boardRoot() ? swapBoard(page) : swapBacklog(page);
  }

  /* The planner's counterpart: every lane and card, the epic panel with its
   * progress, and the data this script runs on, in place of the ones on
   * screen. The page and its scroll stay. */
  function swapBacklog(page) {
    var root = document.getElementById('ea-backlog');
    var fresh = page.getElementById('ea-backlog');
    var island = page.getElementById('ea-board-data');
    var ownIsland = document.getElementById('ea-board-data');
    if (!root || !fresh || !island || !ownIsland) { return false; }
    var freshConfig;
    try {
      freshConfig = JSON.parse(island.textContent);
    } catch (e) {
      return false;
    }

    abandonDrag();
    config = freshConfig;
    ownIsland.textContent = island.textContent;
    root.className = fresh.className;
    while (root.firstChild) { root.removeChild(root.firstChild); }
    Array.prototype.forEach.call(fresh.childNodes, function (node) {
      root.appendChild(document.importNode(node, true));
    });
    var panel = epicPanel();
    var freshPanel = page.getElementById('ea-epic-panel');
    if (panel && freshPanel) { panel.parentNode.replaceChild(document.importNode(freshPanel, true), panel); }
    initPlanner(root);
    return true;
  }

  /* A card picked up from the board that was just replaced can no longer
   * land anywhere; the drag ends without a move. */
  function abandonDrag() {
    if (dragged) { dragged.classList.remove('ea-dragging'); }
    dragged = null;
    origin = null;
    allowedTargets = null;
    originLane = null;
    clearDropTargets();
  }

  function init() {
    config = readConfig();
    if (!config) { return; }
    /* Same script, either screen. */
    var root = document.getElementById('ea-board') || document.getElementById('ea-backlog');
    if (!root) { return; }

    if (root === boardRoot()) {
      Array.prototype.forEach.call(root.querySelectorAll('.ea-card'), makeDraggable);
      Array.prototype.forEach.call(root.querySelectorAll('.ea-cell'), makeDroppable);
      pinHeader(root);
    } else {
      initPlanner(root);
    }
    if (document.getElementById('ea-board-form')) {
      document.addEventListener('click', interceptBulkUpdate, true);
      document.addEventListener('contextmenu', forwardCardLinkContextMenu, true);
    }
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
