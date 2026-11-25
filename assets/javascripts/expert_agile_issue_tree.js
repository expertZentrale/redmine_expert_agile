/* Epics on Redmine's issue list.
 *
 * Sorted by parent task, core draws the subtask tree: every row carries
 * `idnt-N` for its depth. The #ea-issue-tree-data island names the epic rows
 * (colour, progress) and the epic every other row belongs to. This script
 * highlights the epic rows, lets each fold its rows away, draws tree lines in
 * place of core's indent arrows and colours each row with its epic.
 *
 * It only decorates the rows core rendered; it never moves or adds one, so
 * selection, the context menu and every link keep working as before. Which
 * epics are folded is remembered per browser.
 */
(function () {
  'use strict';

  var STORAGE_KEY = 'expert_agile.issue_tree.collapsed';
  var STORAGE_LIMIT = 500;

  function readData() {
    var island = document.getElementById('ea-issue-tree-data');
    if (!island) { return null; }
    try {
      return JSON.parse(island.textContent);
    } catch (e) {
      return null;
    }
  }

  function loadCollapsed() {
    var collapsed = {};
    try {
      var ids = JSON.parse(window.localStorage.getItem(STORAGE_KEY) || '[]');
      if (Array.isArray(ids)) {
        ids.forEach(function (id) { collapsed[String(id)] = true; });
      }
    } catch (e) { /* storage unavailable or unreadable: nothing folded */ }
    return collapsed;
  }

  function saveCollapsed(collapsed) {
    try {
      var ids = Object.keys(collapsed).filter(function (id) { return collapsed[id]; });
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(ids.slice(-STORAGE_LIMIT)));
    } catch (e) { /* storage unavailable: folding lasts for this page only */ }
  }

  function levelOf(row) {
    var match = /(?:^|\s)idnt-(\d+)(?:\s|$)/.exec(row.className);
    return match ? parseInt(match[1], 10) : 0;
  }

  function issueIdOf(row) {
    var match = /^issue-(\d+)$/.exec(row.id || '');
    return match ? match[1] : null;
  }

  /* One entry per body row, group headers included: they end every run of
   * rows, since the rows of two groups never belong to one tree. */
  function readRows(table) {
    var entries = [];
    Array.prototype.forEach.call(table.tBodies, function (body) {
      Array.prototype.forEach.call(body.rows, function (row) {
        if (row.classList.contains('group')) {
          entries.push({ row: row, group: true });
          return;
        }
        var id = issueIdOf(row);
        if (id) { entries.push({ row: row, id: id, level: levelOf(row) }); }
      });
    });
    return entries;
  }

  /* For every indented row, which tree lines pass through it: one per level
   * above it whose run goes on further down, plus its own branch, which ends
   * halfway when it is the last row of its parent. One pass from the bottom. */
  function drawGuides(entries) {
    var continues = [];
    for (var i = entries.length - 1; i >= 0; i--) {
      var entry = entries[i];
      if (entry.group) { continues = []; continue; }
      var level = entry.level;
      if (level > 0) {
        var cell = entry.row.querySelector('td.subject');
        if (cell) {
          var guides = document.createElement('span');
          guides.className = 'ea-tree-guides';
          guides.setAttribute('aria-hidden', 'true');
          for (var k = 1; k <= level; k++) {
            if (k < level && !continues[k]) { continue; }
            var guide = document.createElement('span');
            guide.className = 'ea-tree-guide' + (k === level ? ' ea-tree-branch' : '') +
              (k === level && !continues[k] ? ' ea-tree-last' : '');
            guide.style.setProperty('--ea-tree-level', String(k));
            guides.appendChild(guide);
          }
          cell.insertBefore(guides, cell.firstChild);
        }
      }
      continues[level] = true;
      continues.length = level + 1;
    }
  }

  function setToggleState(button, collapsed, labels) {
    button.setAttribute('aria-expanded', String(!collapsed));
    var label = collapsed ? labels.expand : labels.collapse;
    button.setAttribute('aria-label', label);
    button.title = label;
  }

  function init() {
    var data = readData();
    var table = document.querySelector('table.list.issues');
    if (!data || !table) { return; }

    var epics = data.epics || {};
    var members = data.members || {};
    var labels = data.labels || {};
    var entries = readRows(table);
    var collapsed = loadCollapsed();
    var toggles = {};

    table.classList.add('ea-issue-tree');
    drawGuides(entries);

    entries.forEach(function (entry, index) {
      if (entry.group) { return; }
      var epic = epics[entry.id];
      var memberOf = members[entry.id] ? epics[members[entry.id]] : null;
      if (epic && epic.progress !== undefined) {
        entry.epic = true;
        entry.row.classList.add('ea-epic-row');
        if (epic.color) { entry.row.style.setProperty('--ea-epic', epic.color); }
        decorateEpic(entry, entries[index + 1], epic);
      } else if (memberOf) {
        entry.row.classList.add('ea-epic-member');
        if (memberOf.color) { entry.row.style.setProperty('--ea-epic', memberOf.color); }
      }
    });

    function decorateEpic(entry, next, epic) {
      var cell = entry.row.querySelector('td.subject');
      if (!cell) { return; }
      var hasRows = next && !next.group && next.level > entry.level;
      if (hasRows) {
        var button = document.createElement('button');
        button.type = 'button';
        button.className = 'ea-tree-toggle';
        button.setAttribute('data-ea-epic', entry.id);
        setToggleState(button, !!collapsed[entry.id], labels);
        var guides = cell.querySelector('.ea-tree-guides');
        cell.insertBefore(button, guides ? guides.nextSibling : cell.firstChild);
        toggles[entry.id] = button;
      }
      var meta = document.createElement('span');
      meta.className = 'ea-epic-meta';
      meta.textContent = epic.progress;
      if (epic.title) { meta.title = epic.title; }
      cell.appendChild(meta);
    }

    /* A row is hidden while any epic above it is folded. */
    function applyVisibility() {
      var stack = [];
      entries.forEach(function (entry) {
        if (entry.group) { stack = []; return; }
        while (stack.length && stack[stack.length - 1].level >= entry.level) { stack.pop(); }
        var hidden = stack.some(function (above) { return above.folded; });
        entry.row.classList.toggle('ea-tree-hidden', hidden);
        stack.push({ level: entry.level, folded: !!(entry.epic && toggles[entry.id] && collapsed[entry.id]) });
      });
      Object.keys(toggles).forEach(function (id) { setToggleState(toggles[id], !!collapsed[id], labels); });
      refreshAllButton();
    }

    var allButton = null;
    var foldable = Object.keys(toggles);
    if (foldable.length > 1) {
      var bar = document.createElement('p');
      bar.className = 'ea-issue-tree-actions';
      /* A link, so it takes the theme's link colour like core's own
       * "Collapse all/Expand all". */
      allButton = document.createElement('a');
      allButton.href = '#';
      allButton.setAttribute('role', 'button');
      allButton.className = 'ea-tree-all';
      bar.appendChild(allButton);
      var anchor = table.closest('.autoscroll') || table;
      anchor.parentNode.insertBefore(bar, anchor);
      allButton.addEventListener('click', function (event) {
        event.preventDefault();
        var fold = !foldable.every(function (id) { return collapsed[id]; });
        foldable.forEach(function (id) { collapsed[id] = fold; });
        saveCollapsed(collapsed);
        applyVisibility();
      });
    }

    function refreshAllButton() {
      if (!allButton) { return; }
      var allFolded = foldable.every(function (id) { return collapsed[id]; });
      allButton.textContent = allFolded ? labels.expandAll : labels.collapseAll;
    }

    /* Core selects a row on any click inside it; a fold is not a selection. */
    table.addEventListener('click', function (event) {
      var button = event.target.closest && event.target.closest('.ea-tree-toggle');
      if (!button) { return; }
      event.preventDefault();
      event.stopPropagation();
      var id = button.getAttribute('data-ea-epic');
      collapsed[id] = !collapsed[id];
      saveCollapsed(collapsed);
      applyVisibility();
    });

    applyVisibility();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
