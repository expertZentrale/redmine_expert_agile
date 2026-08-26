/* Keeps the "current colour" field in step with the swatch you click.
 *
 * Without this the field only tells you what was saved, so picking a colour and
 * reading back what you picked would take a round trip to the server. Every
 * value it writes comes from the radio that was chosen, so the field cannot
 * drift from what the form will post.
 *
 * No configuration and no JSON island: the markup carries what is needed, and
 * the page works without this file — it just stops updating until saved.
 */
(function () {
  'use strict';

  function field(radio) {
    var node = radio.parentNode;
    while (node && !(node.classList && node.classList.contains('ea-color-field'))) {
      node = node.parentNode;
    }
    return node;
  }

  function update(radio) {
    var box = field(radio);
    if (!box) { return; }

    var hex = radio.getAttribute('data-color-hex') || '';
    var name = radio.getAttribute('data-color-name') || '';

    var swatch = box.querySelector('[data-role="ea-color-current-swatch"]');
    if (swatch) {
      /* Written the way the server writes it, so the field looks the same
       * before and after a save: a colour, or an empty box with a cross. */
      swatch.style.backgroundColor = hex || '#fff';
      swatch.style.color = hex ? '' : '#999';
      swatch.innerHTML = hex ? '' : '&times;';
    }

    var label = box.querySelector('[data-role="ea-color-current-name"]');
    if (label) { label.textContent = name; }

    var code = box.querySelector('[data-role="ea-color-current-hex"]');
    if (code) { code.textContent = hex; }
  }

  function init() {
    /* One listener for the whole document: the issue form renders its picker
     * through a hook, and bulk screens render many, so binding per radio would
     * mean rebinding whenever something re-renders. */
    document.addEventListener('change', function (event) {
      var target = event.target;
      if (target && target.type === 'radio' && target.hasAttribute('data-color-hex')) {
        update(target);
      }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
