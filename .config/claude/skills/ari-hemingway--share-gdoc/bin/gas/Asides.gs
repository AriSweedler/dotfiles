// Bookmarks for aside markers. The Docs REST API cannot create bookmarks; DocumentApp can.
// addMarkerBookmarks(docId, maxN) -> {"1": bookmarkId, ...}: one bookmark at each marker in the first
// tab, found by its anchor link "#aside-n" (fresh import) or by its text "aside n ℹ️" (already relinked
// to a tab). Every bookmark in that tab is removed first so a rerun is a no-op, not a pile-up.
var MARKER_TEXT_SUFFIX = ' ℹ️';

function findMarker(body, n) {
  var anchor = '#aside-' + n;
  var text = 'aside ' + n + MARKER_TEXT_SUFFIX;
  var hit = body.findText(text);
  while (hit) {
    var element = hit.getElement().asText();
    var url = element.getLinkUrl(hit.getStartOffset());
    if (url === anchor || url === null || url === '') {
      return hit;
    }
    hit = body.findText(text, hit);
  }
  return null;
}

function addMarkerBookmarks(docId, maxN) {
  var doc = DocumentApp.openById(docId);
  var tab = doc.getTabs()[0].asDocumentTab();
  tab.getBookmarks().forEach(function (bookmark) { bookmark.remove(); });
  var body = tab.getBody();
  var out = {};
  for (var n = 1; n <= (maxN || 9); n++) {
    var hit = findMarker(body, n);
    if (!hit) { continue; }
    var position = tab.newPosition(hit.getElement(), hit.getStartOffset());
    out[String(n)] = tab.addBookmark(position).getId();
  }
  return out;
}
