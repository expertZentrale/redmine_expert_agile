/* Agile charts.
 *
 * Reads the endpoint from the #ea-chart-data JSON island, fetches the series,
 * and draws them with the Chart.js build vendored alongside this file.
 *
 * Chart.js is shipped by this plugin rather than borrowed from another plugin's
 * asset directory or from a Chart global some other plugin put on the page:
 * either would be a runtime dependency nothing declares.
 *
 * Chart.js v4 option shapes throughout.
 */
(function () {
  'use strict';

  function readConfig() {
    var island = document.getElementById('ea-chart-data');
    if (!island) { return null; }
    try { return JSON.parse(island.textContent); } catch (e) { return null; }
  }

  function message(text) {
    var box = document.getElementById('ea-chart-message');
    if (!box) { return; }
    box.textContent = text || '';
    box.style.display = text ? 'block' : 'none';
  }

  function draw(canvas, config, payload) {
    var stacked = !!payload.stacked;
    new Chart(canvas.getContext('2d'), {
      type: payload.type || config.type || 'line',
      data: { labels: payload.labels, datasets: payload.datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: { mode: 'index', intersect: false },
        plugins: {
          title: { display: !!payload.title, text: payload.title },
          legend: { position: 'bottom' },
          tooltip: { enabled: true }
        },
        scales: {
          x: { stacked: stacked },
          y: {
            stacked: stacked,
            beginAtZero: true,
            title: { display: !!payload.y_title, text: payload.y_title }
          }
        }
      }
    });
  }

  function init() {
    var config = readConfig();
    var canvas = document.getElementById('ea-chart');
    if (!config || !canvas) { return; }

    fetch(config.url, {
      credentials: 'same-origin',
      headers: {
        'X-Requested-With': 'XMLHttpRequest',
        /* text/javascript, not application/json: a .json request is an API
         * request to Redmine and would ignore the session cookie. */
        'Accept': 'text/javascript'
      }
    }).then(function (response) {
      return response.json().then(function (payload) {
        if (!response.ok || payload.error) {
          message(payload.error || 'Error');
          canvas.style.display = 'none';
          return;
        }
        message('');
        draw(canvas, config, payload);
      });
    }).catch(function () {
      message('Error');
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
