// Bookmarks for a published Doc. The Docs REST API has no bookmark request; DocumentApp does.
// addBookmarks(docId, targets) -> {key: bookmarkId}. targets: [{key, url, text}]. Each target is found
// in the first tab by its link URL (a fresh import still carries "#bm-<slug>" / "#aside-n") or, failing
// that, by its exact text (after the link style was stripped or relinked). Every bookmark in that tab is
// removed first so a rerun is a no-op, not a pile-up. ping() is the setup probe: it returns "ok" only when
// scripts.run reaches this project from the caller's OAuth client.
function ping() {
  return 'ok';
}

function escapeRegExp(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function findByLinkUrl(body, url) {
  var paragraphs = body.getParagraphs();
  for (var p = 0; p < paragraphs.length; p++) {
    var text = paragraphs[p].editAsText();
    var indices = text.getTextAttributeIndices();
    for (var i = 0; i < indices.length; i++) {
      if (text.getLinkUrl(indices[i]) === url) {
        return {element: text, offset: indices[i]};
      }
    }
  }
  return null;
}

function findByText(body, needle) {
  var pattern = escapeRegExp(needle);
  var hit = body.findText(pattern);
  if (!hit) {
    return null;
  }
  if (body.findText(pattern, hit)) {
    throw new Error('target text occurs more than once | text=' + needle);
  }
  return {element: hit.getElement().asText(), offset: hit.getStartOffset()};
}

function addBookmarks(docId, targets) {
  var doc = DocumentApp.openById(docId);
  var tab = doc.getTabs()[0].asDocumentTab();
  tab.getBookmarks().forEach(function (bookmark) { bookmark.remove(); });
  var body = tab.getBody();
  var out = {};
  targets.forEach(function (target) {
    var found = findByLinkUrl(body, target.url) || findByText(body, target.text);
    if (!found) {
      throw new Error('target not found | key=' + target.key + ' text=' + target.text);
    }
    out[target.key] = tab.addBookmark(tab.newPosition(found.element, found.offset)).getId();
  });
  return out;
}
