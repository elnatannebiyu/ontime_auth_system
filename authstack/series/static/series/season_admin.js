(function() {
  function onReady(fn) {
    if (document.readyState !== 'loading') {
      fn();
    } else {
      document.addEventListener('DOMContentLoaded', fn);
    }
  }

  function buildFetchUrl(showId) {
    // Admin URL for custom view registered in SeasonAdmin.get_urls
    return window.location.origin + '/admin/series/season/fetch_playlists/?show_id=' + encodeURIComponent(showId);
  }

  function ensureSelectForPlaylistField() {
    var field = document.querySelector('input[name="yt_playlist_id"], select[name="yt_playlist_id"]');
    if (!field) return null;
    if (field.tagName.toLowerCase() === 'select') return field;
    var select = document.createElement('select');
    select.name = 'yt_playlist_id';
    select.id = field.id || 'id_yt_playlist_id';
    select.className = field.className;
    // Copy current value as a first option if present
    if (field.value) {
      var opt = document.createElement('option');
      opt.value = field.value;
      opt.textContent = field.value + ' (manual value)';
      opt.selected = true;
      select.appendChild(opt);
    }
    field.parentNode.replaceChild(select, field);
    return select;
  }

  function populatePlaylistChoices(selectEl, items) {
    // Preserve currently selected value if still present
    var current = selectEl.value;
    // Clear options
    while (selectEl.firstChild) selectEl.removeChild(selectEl.firstChild);

    if (!items || !items.length) {
      // Fallback to an input if nothing to show
      var input = document.createElement('input');
      input.type = 'text';
      input.name = 'yt_playlist_id';
      input.id = selectEl.id || 'id_yt_playlist_id';
      input.className = selectEl.className;
      selectEl.parentNode.replaceChild(input, selectEl);
      return;
    }

    items.forEach(function(it) {
      var opt = document.createElement('option');
      opt.value = it.id;
      opt.textContent = it.title + ' (' + it.id + ')';
      selectEl.appendChild(opt);
    });

    // Try to restore previous selection
    if (current) {
      for (var i = 0; i < selectEl.options.length; i++) {
        if (selectEl.options[i].value === current) {
          selectEl.selectedIndex = i;
          break;
        }
      }
    }
  }

  function attachShowChangeHandler() {
    var showField = document.querySelector('select[name="show"]');
    if (!showField) return;

    var playlistField = document.querySelector('input[name="yt_playlist_id"], select[name="yt_playlist_id"]');
    if (!playlistField) return;

    showField.addEventListener('change', function() {
      var showId = showField.value;
      if (!showId) return;
      // Ensure we have a <select> to populate
      var select = ensureSelectForPlaylistField();
      if (!select) return;

      fetch(buildFetchUrl(showId), { credentials: 'same-origin' })
        .then(function(res) { return res.json(); })
        .then(function(data) {
          populatePlaylistChoices(select, (data && data.results) || []);
        })
        .catch(function() {
          // On error, leave manual input in place
        });
    });
  }

  onReady(attachShowChangeHandler);
})();
