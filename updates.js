(function() {
  var APPCAST_URL = 'https://poirpom.github.io/loucede/appcast.xml';
  var MARKED_URL = 'https://cdn.jsdelivr.net/npm/marked@12.0.0/marked.min.js';
  var MAX_ITEMS = 5;

  function init() {
    var statusEl = document.getElementById('loucede-updates-status');
    var listEl = document.getElementById('loucede-updates-list');
    if (!statusEl || !listEl) {
      console.error('[loucede-updates] containers not found');
      return;
    }

    function loadScript(src, callback, onerror) {
      var s = document.createElement('script');
      s.src = src;
      s.onload = callback;
      s.onerror = onerror;
      document.head.appendChild(s);
    }

    function formatDate(rfcDate) {
      try {
        var d = new Date(rfcDate);
        if (isNaN(d.getTime())) return rfcDate;
        var months = ['janvier','février','mars','avril','mai','juin','juillet','août','septembre','octobre','novembre','décembre'];
        return d.getDate() + ' ' + months[d.getMonth()] + ' ' + d.getFullYear();
      } catch (e) {
        return rfcDate;
      }
    }

    function getText(item, tag) {
      var el = item.getElementsByTagName(tag)[0];
      return el ? el.textContent.trim() : '';
    }

    function renderMarkdown(text) {
      if (typeof marked !== 'undefined' && marked.parse) {
        try {
          marked.setOptions({ breaks: true, gfm: true });
          return marked.parse(text);
        } catch (e) {
          console.error('[loucede-updates] marked error', e);
        }
      }
      var escaped = text
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
      return '<pre style="white-space: pre-wrap; font-family: inherit;">' + escaped + '</pre>';
    }

    function fetchAndRender() {
      fetch(APPCAST_URL, { cache: 'no-store' })
        .then(function(response) {
          if (!response.ok) throw new Error('HTTP ' + response.status);
          return response.text();
        })
        .then(function(xmlText) {
          var parser = new DOMParser();
          var xml = parser.parseFromString(xmlText, 'application/xml');
          var parseError = xml.getElementsByTagName('parsererror');
          if (parseError.length > 0) throw new Error('Erreur de parsing XML');

          var items = Array.prototype.slice.call(xml.getElementsByTagName('item'));
          if (items.length === 0) {
            statusEl.textContent = 'Aucune version publiée pour le moment.';
            return;
          }

          items.sort(function(a, b) {
            var dateA = new Date(getText(a, 'pubDate')).getTime() || 0;
            var dateB = new Date(getText(b, 'pubDate')).getTime() || 0;
            return dateB - dateA;
          });

          var visible = items.slice(0, MAX_ITEMS);
          statusEl.style.display = 'none';

          visible.forEach(function(item) {
            var title = getText(item, 'title');
            var pubDate = getText(item, 'pubDate');
            var description = getText(item, 'description');

            var article = document.createElement('article');
            article.className = 'loucede-update';

            var header = document.createElement('div');
            header.className = 'loucede-update-header';

            var version = document.createElement('h2');
            version.className = 'loucede-update-version';
            version.textContent = title || 'Version';
            header.appendChild(version);

            if (pubDate) {
              var date = document.createElement('span');
              date.className = 'loucede-update-date';
              date.textContent = formatDate(pubDate);
              header.appendChild(date);
            }

            article.appendChild(header);

            if (description) {
              var notes = document.createElement('div');
              notes.className = 'loucede-update-notes';
              notes.innerHTML = renderMarkdown(description);
              notes.querySelectorAll('a').forEach(function(a) {
                a.setAttribute('target', '_blank');
                a.setAttribute('rel', 'noopener noreferrer');
              });
              article.appendChild(notes);
            }

            listEl.appendChild(article);
          });
        })
        .catch(function(err) {
          statusEl.textContent = 'Impossible de charger les versions. Voir l\'historique sur GitHub.';
          console.error('[loucede-updates] fetch/render error', err);
        });
    }

    loadScript(MARKED_URL, fetchAndRender, function() {
      console.warn('[loucede-updates] marked.js failed to load, falling back to plain text');
      fetchAndRender();
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
