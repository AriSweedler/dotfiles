# Contrast gate for Mermaid sources. Reads a .mmd and prints one record per violation:
#
#   line|directive|name|fill|color|ratio|reason
#
# A violation is a `classDef` or `style` line that sets `fill` without `color`, uses a
# color the checker cannot parse (only #rgb, #rrggbb, white, black), or pairs them at a
# WCAG contrast ratio below `min_ratio` (pass with -v min_ratio=3.0). Exit code is 0
# either way; the caller counts records.

function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }

function hex6(c) {
  c = tolower(trim(c))
  if (c == "white") return "ffffff"
  if (c == "black") return "000000"
  if (c ~ /^#[0-9a-f][0-9a-f][0-9a-f]$/) {
    return substr(c, 2, 1) substr(c, 2, 1) substr(c, 3, 1) substr(c, 3, 1) substr(c, 4, 1) substr(c, 4, 1)
  }
  if (c ~ /^#[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$/) return substr(c, 2)
  return ""
}

function hexval(h,    i, v) {
  v = 0
  for (i = 1; i <= length(h); i++) v = v * 16 + index("0123456789abcdef", substr(h, i, 1)) - 1
  return v
}

# sRGB channel -> linear light, per WCAG 2.x.
function lin(c) { c = c / 255; return (c <= 0.03928) ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4 }

function lum(h) {
  return 0.2126 * lin(hexval(substr(h, 1, 2))) + 0.7152 * lin(hexval(substr(h, 3, 2))) + 0.0722 * lin(hexval(substr(h, 5, 2)))
}

function ratio(a, b,    la, lb, t) {
  la = lum(a); lb = lum(b)
  if (la < lb) { t = la; la = lb; lb = t }
  return (la + 0.05) / (lb + 0.05)
}

$1 == "classDef" || $1 == "style" {
  name = $2; fill = ""; color = ""
  rest = $0
  sub(/^[ \t]*(classDef|style)[ \t]+[^ \t]+[ \t]+/, "", rest)
  n = split(rest, kv, ",")
  for (i = 1; i <= n; i++) {
    split(kv[i], p, ":")
    k = trim(p[1]); v = trim(p[2])
    if (k == "fill") fill = v
    if (k == "color") color = v
  }
  if (fill == "" || tolower(fill) == "none" || tolower(fill) == "transparent") next
  if (color == "") { printf "%d|%s|%s|%s|-|-|fill without color\n", NR, $1, name, fill; next }
  fh = hex6(fill); ch = hex6(color)
  if (fh == "" || ch == "") { printf "%d|%s|%s|%s|%s|-|unparseable color (use #rrggbb)\n", NR, $1, name, fill, color; next }
  r = ratio(fh, ch)
  if (r < min_ratio) printf "%d|%s|%s|%s|%s|%.2f|contrast below %.1f\n", NR, $1, name, fill, color, r, min_ratio
}
