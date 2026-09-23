/* Turns the colour screen's hex fields into Coloris pickers.
 *
 * Everything the picker needs — the palette swatches and its labels in the
 * user's language — comes from the data-ea-coloris attribute on the form, so
 * the page carries no inline script. Without this file, or without Coloris,
 * the fields stay plain hex inputs and the form still saves.
 */
(function () {
  'use strict';

  function init() {
    var host = document.querySelector('[data-ea-coloris]');
    if (!host || typeof window.Coloris !== 'function') { return; }

    var config;
    try {
      config = JSON.parse(host.getAttribute('data-ea-coloris'));
    } catch (e) {
      return;
    }

    window.Coloris({
      el: '.ea-color-input',
      theme: 'default',
      themeMode: 'light',
      format: 'hex',
      formatToggle: false,
      alpha: false,
      // What an empty field opens on: a palette colour rather than Coloris'
      // black, so a first click in the colour area lands somewhere usable.
      defaultColor: config.defaultColor || '#3d7ec4',
      swatches: config.swatches || [],
      clearButton: true,
      clearLabel: config.clearLabel,
      closeButton: true,
      closeLabel: config.closeLabel,
      a11y: config.a11y
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
