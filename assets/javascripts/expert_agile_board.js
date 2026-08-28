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
        return response.json().then(function (payload) {
          saved = true;
          applyMove(payload);
        });
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
