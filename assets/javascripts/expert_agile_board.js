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

  function setMessage(text, isError) {
    var box = document.getElementById('ea-board-message');
    if (!box) {
      box = document.createElement('div');
      box.id = 'ea-board-message';
      var anchor = document.getElementById('ea-board') || document.getElementById('ea-backlog');
      anchor.parentNode.insertBefore(box, anchor);
    }
    box.className = isError ? 'flash error' : 'flash notice';
    box.textContent = text || '';
    box.style.display = text ? 'block' : 'none';
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
    if (config.containerType) { body.append('container_type', config.containerType); }

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
      return response.json().then(function (payload) {
        if (response.ok) { applyMove(payload); } else { revertMove(payload, from); }
      });
    }).catch(function () {
      revertMove({ error: config.labels.moveFailed }, from);
    });
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
    setMessage(payload && payload.error ? payload.error : config.labels.moveFailed, true);
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
    card.setAttribute('draggable', 'true');
    card.addEventListener('dragstart', function (event) {
      dragged = card;
      var next = card.nextElementSibling;
      origin = { cardId: card.id, parent: card.parentNode, nextId: next ? next.id : null };
      card.classList.add('ea-dragging');
      event.dataTransfer.effectAllowed = 'move';
      event.dataTransfer.setData('text/plain', card.getAttribute('data-issue-id'));
    });
    card.addEventListener('dragend', function () {
      card.classList.remove('ea-dragging');
    });
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
      dragged = null;
      origin = null;
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
