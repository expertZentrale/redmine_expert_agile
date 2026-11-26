/* The epic picker on Redmine's issue form.
 *
 * An epic is the parent task. The #ea-epic-picker-data island lists the open
 * epics the issue may hang under, with colour and progress; this script draws
 * a searchable picker for them right under the "Parent task" field and, on a
 * choice, writes that field and fires its change event. Core then redraws the
 * form from the server as it does for any parent change, the picker included,
 * so saving, validation and permissions never leave core.
 *
 * An issue under a story gets no choice, only its epic and where it comes
 * from: picking an epic would tear it out of the story.
 *
 * The row stays hidden until this script fills it, so without the script the
 * form is exactly core's.
 */
(function () {
  'use strict';

  var ISLAND_ID = 'ea-epic-picker-data';
  var ROW_ID = 'ea-epic-picker';
  var LIST_ID = 'ea-epic-picker-list';
  var picker = null; // the picker on the page, redrawn with the form
  var refocus = false; // a choice was made, the redrawn picker takes the focus

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) { node.className = className; }
    if (text !== undefined && text !== null) { node.textContent = text; }
    return node;
  }

  function transparent(colour) {
    return !colour || colour === 'transparent' || /rgba\([^)]*,\s*0(\.0+)?\)$/.test(colour);
  }

  // The picker takes the look of the theme's own text fields, whatever the
  // theme; its list needs a solid background, found further up where the
  // field itself has none.
  function adoptFieldLook(holder, field) {
    var style = window.getComputedStyle(field);
    var background = style.backgroundColor;
    var node = field;
    while (transparent(background) && node.parentElement) {
      node = node.parentElement;
      background = window.getComputedStyle(node).backgroundColor;
    }
    if (!transparent(background)) { holder.style.setProperty('--ea-picker-bg', background); }
    if (style.color) { holder.style.setProperty('--ea-picker-fg', style.color); }
    if (style.borderTopColor && style.borderTopWidth !== '0px') {
      holder.style.setProperty('--ea-picker-border', style.borderTopColor);
    }
    if (style.borderTopLeftRadius) { holder.style.setProperty('--ea-picker-radius', style.borderTopLeftRadius); }
  }

  function swatch(epic) {
    var node = el('span', 'ea-epic-swatch');
    node.setAttribute('aria-hidden', 'true');
    if (epic && epic.color) { node.style.setProperty('--ea-epic', epic.color); }
    if (!epic) { node.classList.add('ea-epic-swatch-none'); }
    return node;
  }

  function progress(epic) {
    var node = el('span', 'ea-epic-picker-progress');
    node.title = epic.title || '';
    var bar = el('span', 'ea-epic-picker-bar');
    bar.setAttribute('aria-hidden', 'true');
    bar.style.setProperty('--ea-progress', (epic.percent || 0) + '%');
    if (epic.color) { bar.style.setProperty('--ea-epic', epic.color); }
    node.appendChild(bar);
    node.appendChild(el('span', 'ea-epic-picker-count', epic.done + '/' + epic.total));
    return node;
  }

  function meta(epic, labels) {
    var parts = ['#' + epic.id];
    if (epic.project) { parts.push(epic.project); }
    if (epic.closed) { parts.push(labels.closed); }
    return parts.join(' · ');
  }

  // --- An issue under a story: its epic, no choice -------------------------

  function drawReadOnly(holder, data) {
    var current = el('span', 'ea-epic-picker-current');
    current.appendChild(swatch(data.current));
    current.appendChild(el('span', 'ea-epic-picker-value', data.current ? data.current.subject : data.labels.none));
    if (data.current) { current.appendChild(progress(data.current)); }
    holder.appendChild(current);
    holder.appendChild(el('span', 'ea-epic-picker-hint', data.labels.via));
  }

  // --- The picker ----------------------------------------------------------

  function Picker(holder, data, field) {
    this.holder = holder;
    this.data = data;
    this.field = field;
    this.isOpen = false;
    this.active = 0;
    this.shown = [];
    this.none = { id: '', subject: data.labels.none };
    this.byId = {};
    var self = this;
    data.epics.forEach(function (epic) { self.byId[epic.id] = epic; });
    this.build();
  }

  Picker.prototype.build = function () {
    var self = this;
    this.button = el('button', 'ea-epic-picker-button');
    this.button.type = 'button';
    this.button.id = 'ea-epic-picker-button';
    this.button.setAttribute('aria-haspopup', 'listbox');
    this.button.setAttribute('aria-expanded', 'false');
    this.button.setAttribute('aria-labelledby', 'ea-epic-picker-label ea-epic-picker-value');

    this.pop = el('div', 'ea-epic-picker-pop');
    this.pop.hidden = true;
    this.search = el('input', 'ea-epic-picker-search');
    this.search.type = 'search';
    this.search.autocomplete = 'off';
    this.search.placeholder = this.data.labels.search;
    this.search.setAttribute('aria-label', this.data.labels.search);
    this.search.setAttribute('role', 'combobox');
    this.search.setAttribute('aria-autocomplete', 'list');
    this.search.setAttribute('aria-expanded', 'true');
    this.search.setAttribute('aria-controls', LIST_ID);
    this.list = el('ul', 'ea-epic-picker-list');
    this.list.id = LIST_ID;
    this.list.setAttribute('role', 'listbox');
    this.list.setAttribute('aria-label', this.data.labels.list);
    this.pop.appendChild(this.search);
    this.pop.appendChild(this.list);

    this.holder.appendChild(this.button);
    this.holder.appendChild(this.pop);
    this.drawButton();

    this.button.addEventListener('click', function () { self.toggle(); });
    this.button.addEventListener('keydown', function (event) {
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
        event.preventDefault();
        self.open();
      }
    });
    this.search.addEventListener('input', function () {
      self.active = 0;
      self.drawList();
    });
    this.search.addEventListener('keydown', function (event) { self.onSearchKey(event); });
    // Keeps the focus in the search field, so a click does not close the list
    // before it lands.
    this.list.addEventListener('mousedown', function (event) { event.preventDefault(); });
    this.list.addEventListener('click', function (event) {
      var option = event.target.closest && event.target.closest('[role="option"]');
      if (!option) { return; }
      self.choose(self.shown[Number(option.getAttribute('data-index'))]);
    });
    this.list.addEventListener('mousemove', function (event) {
      var option = event.target.closest && event.target.closest('[role="option"]');
      if (!option) { return; }
      var index = Number(option.getAttribute('data-index'));
      if (index !== self.active) { self.setActive(index); }
    });
  };

  Picker.prototype.currentEpic = function () {
    return this.data.current ? this.byId[this.data.current] || null : null;
  };

  Picker.prototype.drawButton = function () {
    var epic = this.currentEpic();
    this.button.textContent = '';
    this.button.appendChild(swatch(epic));
    var value = el('span', 'ea-epic-picker-value', epic ? epic.subject : this.data.labels.none);
    value.id = 'ea-epic-picker-value';
    this.button.appendChild(value);
    if (epic) { this.button.appendChild(progress(epic)); }
  };

  Picker.prototype.matches = function () {
    var query = this.search.value.trim().toLowerCase().replace(/^#/, '');
    var epics = this.data.epics;
    if (!query) { return [this.none].concat(epics); }
    return epics.filter(function (epic) {
      var text = (epic.subject + ' ' + epic.id + ' ' + (epic.project || '')).toLowerCase();
      return text.indexOf(query) !== -1;
    });
  };

  Picker.prototype.drawList = function () {
    var self = this;
    var labels = this.data.labels;
    var current = this.data.current || '';
    this.shown = this.matches();
    if (this.active >= this.shown.length) { this.active = Math.max(0, this.shown.length - 1); }
    this.list.textContent = '';
    if (!this.shown.length) {
      var empty = el('li', 'ea-epic-picker-empty', labels.noMatch);
      empty.setAttribute('role', 'presentation');
      this.list.appendChild(empty);
      this.search.removeAttribute('aria-activedescendant');
      return;
    }
    this.shown.forEach(function (epic, index) {
      var option = el('li', 'ea-epic-picker-option');
      option.id = 'ea-epic-option-' + (epic.id || 'none');
      option.setAttribute('role', 'option');
      option.setAttribute('data-index', String(index));
      option.setAttribute('aria-selected', String(epic.id === current));
      if (epic.color) { option.style.setProperty('--ea-epic', epic.color); }
      option.appendChild(swatch(epic.id ? epic : null));
      option.appendChild(el('span', 'ea-epic-picker-option-subject', epic.subject));
      if (epic.id) {
        option.appendChild(el('span', 'ea-epic-picker-option-meta', meta(epic, labels)));
        option.appendChild(progress(epic));
      } else {
        option.classList.add('ea-epic-picker-option-none');
      }
      self.list.appendChild(option);
    });
    this.setActive(this.active);
    this.place();
  };

  Picker.prototype.setActive = function (index) {
    var options = this.list.querySelectorAll('[role="option"]');
    if (!options.length) { return; }
    this.active = Math.max(0, Math.min(index, options.length - 1));
    for (var i = 0; i < options.length; i++) {
      options[i].classList.toggle('ea-active', i === this.active);
    }
    var option = options[this.active];
    this.search.setAttribute('aria-activedescendant', option.id);
    if (option.scrollIntoView) { option.scrollIntoView({ block: 'nearest' }); }
  };

  Picker.prototype.open = function () {
    if (this.isOpen) { return; }
    this.isOpen = true;
    this.search.value = '';
    var current = this.data.current || '';
    var list = [this.none].concat(this.data.epics);
    this.active = 0;
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === current) { this.active = i; }
    }
    this.pop.hidden = false;
    this.button.setAttribute('aria-expanded', 'true');
    this.holder.classList.add('ea-open');
    this.drawList();
    this.search.focus({ preventScroll: true });
  };

  // The list is fixed to the viewport, under the button or above it where
  // there is no room below: core's form rows clip what overflows them.
  Picker.prototype.place = function () {
    if (!this.isOpen) { return; }
    var rect = this.button.getBoundingClientRect();
    var width = this.pop.offsetWidth;
    var height = this.pop.offsetHeight;
    var viewWidth = document.documentElement.clientWidth;
    var viewHeight = window.innerHeight;
    var rtl = window.getComputedStyle(this.holder).direction === 'rtl';
    var left = rtl ? rect.right - width : rect.left;
    left = Math.max(8, Math.min(left, viewWidth - width - 8));
    var fitsBelow = viewHeight - rect.bottom - 8 >= height;
    var top = fitsBelow || rect.top < height + 8 ? rect.bottom + 4 : rect.top - height - 4;
    this.pop.style.left = left + 'px';
    this.pop.style.top = top + 'px';
  };

  Picker.prototype.close = function (refocus) {
    if (!this.isOpen) { return; }
    this.isOpen = false;
    this.pop.hidden = true;
    this.button.setAttribute('aria-expanded', 'false');
    this.holder.classList.remove('ea-open');
    if (refocus) { this.button.focus(); }
  };

  Picker.prototype.toggle = function () {
    if (this.isOpen) { this.close(true); } else { this.open(); }
  };

  Picker.prototype.onSearchKey = function (event) {
    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault();
        this.setActive(this.active + 1);
        break;
      case 'ArrowUp':
        event.preventDefault();
        this.setActive(this.active - 1);
        break;
      case 'Enter':
        // Never submits the issue form.
        event.preventDefault();
        if (this.shown.length) { this.choose(this.shown[this.active]); }
        break;
      case 'Escape':
        event.preventDefault();
        event.stopPropagation();
        this.close(true);
        break;
      case 'Tab':
        this.close(false);
        break;
    }
  };

  // Writes the parent task field and lets core take over from there: its
  // change handler redraws the form with this issue's new parent.
  Picker.prototype.choose = function (epic) {
    if (!epic) { return; }
    this.close(true);
    var value = epic.id || '';
    if (value === (this.data.current || '')) { return; }
    this.data.current = value || null;
    this.drawButton();
    refocus = true;
    this.field.value = value;
    var event;
    try {
      event = new Event('change', { bubbles: true });
    } catch (e) {
      event = document.createEvent('HTMLEvents');
      event.initEvent('change', true, false);
    }
    this.field.dispatchEvent(event);
  };

  // --- Setup ---------------------------------------------------------------

  function init() {
    var island = document.getElementById(ISLAND_ID);
    var row = document.getElementById(ROW_ID);
    if (picker && !document.body.contains(picker.holder)) { picker = null; }
    if (!island || !row || island.getAttribute('data-ea-ready')) { return; }
    island.setAttribute('data-ea-ready', '1');
    var data;
    try {
      data = JSON.parse(island.textContent);
    } catch (e) {
      return;
    }
    var field = document.getElementById('issue_parent_issue_id');
    var holder = row.querySelector('.ea-epic-picker');
    if (!field || !holder || !data || !data.labels) { return; }

    // Under the parent task field, where the plugin's hook cannot reach.
    var anchor = document.getElementById('parent_issue');
    if (anchor && anchor.parentNode) { anchor.parentNode.insertBefore(row, anchor.nextSibling); }

    adoptFieldLook(holder, field);
    holder.textContent = '';
    if (data.via !== undefined && data.via !== null) {
      picker = null;
      drawReadOnly(holder, data);
    } else {
      picker = new Picker(holder, data, field);
    }
    row.hidden = false;
    // Core's redraw replaces the button the choice was made with.
    if (refocus) {
      refocus = false;
      if (picker) { picker.button.focus(); }
    }
  }

  // A click or focus anywhere outside closes the list.
  function closeFromOutside(event) {
    if (picker && picker.isOpen && !picker.holder.contains(event.target)) { picker.close(false); }
  }

  function placeOpenList() {
    if (picker && picker.isOpen) { picker.place(); }
  }

  function start() {
    init();
    document.addEventListener('mousedown', closeFromOutside);
    document.addEventListener('focusin', closeFromOutside);
    window.addEventListener('scroll', placeOpenList, true);
    window.addEventListener('resize', placeOpenList);
    // Core replaces the form's attributes after every tracker, status,
    // project or parent change; the new island is picked up from there.
    var attributes = document.getElementById('all_attributes');
    if (attributes && window.MutationObserver) {
      new MutationObserver(init).observe(attributes, { childList: true });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
