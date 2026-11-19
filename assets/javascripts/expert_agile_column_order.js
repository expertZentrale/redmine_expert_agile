(function () {
  'use strict';

  function init() {
    var panel = document.getElementById('ea-columns-options');
    if (!panel) { return; }

    var grid = panel.querySelector('.ea-status-grid');
    var order = panel.querySelector('[name="board_column_order"]');
    var reset = panel.querySelector('.ea-column-order-reset');
    var defaultRows = Array.from(grid.querySelectorAll('.ea-status-row')).sort(function (a, b) {
      return Number(a.dataset.defaultPosition) - Number(b.dataset.defaultPosition);
    });

    if (defaultRows.length < 2) { return; }

    function updateButtons(rows) {
      rows.forEach(function (row, index) {
        row.querySelector('[data-ea-move="up"]').disabled = index === 0;
        row.querySelector('[data-ea-move="down"]').disabled = index === rows.length - 1;
      });
    }

    defaultRows.forEach(function (row) {
      row.querySelector('.ea-status-order').hidden = false;
    });
    updateButtons(Array.from(grid.querySelectorAll('.ea-status-row')));
    reset.hidden = false;

    grid.addEventListener('click', function (event) {
      var button = event.target.closest('[data-ea-move]');
      if (!button || button.disabled) { return; }

      var row = button.closest('.ea-status-row');
      var up = button.dataset.eaMove === 'up';
      if (up) {
        row.previousElementSibling.before(row);
      } else {
        row.nextElementSibling.after(row);
      }

      var rows = Array.from(grid.querySelectorAll('.ea-status-row'));
      order.value = rows.map(function (item) { return item.dataset.statusId; }).join(',');
      updateButtons(rows);
      (button.disabled ? row.querySelector('[data-ea-move="' + (up ? 'down' : 'up') + '"]') : button).focus();
    });

    reset.addEventListener('click', function () {
      defaultRows.forEach(function (row) { grid.appendChild(row); });
      order.value = '';
      updateButtons(defaultRows);
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
