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
      var board = document.getElementById('ea-board');
      board.parentNode.insertBefore(box, board);
    }
    box.className = isError ? 'flash error' : 'flash notice';
    box.textContent = text || '';
    box.style.display = text ? 'block' : 'none';
  }

  function submitMove(card, cell) {
    var issueId = card.getAttribute('data-issue-id');
    var statusId = cell.getAttribute('data-column-id');
    var around = neighbours(card);

    var body = new URLSearchParams();
    body.append('status_id', statusId);
    body.append('prev_id', around.prev);
    body.append('next_id', around.next);
    if (config.queryId) { body.append('query_id', config.queryId); }

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
        if (response.ok) { applyMove(payload); } else { revertMove(payload); }
      });
    }).catch(function () {
      revertMove({ error: config.labels.moveFailed });
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
    origin = null;
  }

  function revertMove(payload) {
    if (dragged && origin) { origin.appendChild(dragged); }
    setMessage(payload && payload.error ? payload.error : config.labels.moveFailed, true);
    origin = null;
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

  function makeDraggable(card) {
    if (!config.editable) { return; }
    card.setAttribute('draggable', 'true');
    card.addEventListener('dragstart', function (event) {
      dragged = card;
      origin = card.parentNode;
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
      dragged = null;
      submitMove(card, cell);
    });
  }

  function init() {
    config = readConfig();
    if (!config) { return; }
    var board = document.getElementById('ea-board');
    if (!board) { return; }

    Array.prototype.forEach.call(board.querySelectorAll('.ea-card'), makeDraggable);
    Array.prototype.forEach.call(board.querySelectorAll('.ea-cell'), makeDroppable);
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
