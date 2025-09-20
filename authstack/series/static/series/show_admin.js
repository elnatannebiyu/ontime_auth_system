(function() {
  function onReady(fn) {
    if (document.readyState !== 'loading') {
      fn();
    } else {
      document.addEventListener('DOMContentLoaded', fn);
    }
  }

  function buildFetchUrl(channelId) {
    return window.location.origin + '/admin/series/show/fetch_channel_playlists/?channel_id=' + encodeURIComponent(channelId);
  }

  function attachChannelChangeForTitleSuggestions() {
    var channelField = document.querySelector('select[name="channel"]');
    var titleField = document.querySelector('input[name="title"]');
    if (!channelField || !titleField) return;

    // Create a datalist for suggestions
    var listId = 'playlist_title_suggestions';
    var existing = document.getElementById(listId);
    var dataList = existing || document.createElement('datalist');
    dataList.id = listId;
    if (!existing) document.body.appendChild(dataList);

    // Bind the datalist to the title input (keeps it editable)
    titleField.setAttribute('list', listId);

    function updateSuggestions(items) {
      // Clear old options
      while (dataList.firstChild) dataList.removeChild(dataList.firstChild);
      items.forEach(function(it) {
        var opt = document.createElement('option');
        opt.value = it.title; // suggestion shows playlist title, user can edit
        dataList.appendChild(opt);
      });
    }

    channelField.addEventListener('change', function() {
      var channelId = channelField.value;
      if (!channelId) return;
      fetch(buildFetchUrl(channelId), { credentials: 'same-origin' })
        .then(function(res) { return res.json(); })
        .then(function(data) { updateSuggestions((data && data.results) || []); })
        .catch(function() { /* ignore */ });
    });
  }

  onReady(attachChannelChangeForTitleSuggestions);
})();
